#!/usr/bin/env python3
"""通过本地 HTTP feed 验证 SixLinux opkg 安装和升级。"""

from pathlib import Path
import os
import socket
import subprocess
import sys
import time

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
FEED_DIR = ROOT_DIR / "build" / "qemuarm64" / "tmp" / "deploy" / "ipk"
LOG_PATH = ROOT_DIR / "artifacts" / "opkg-test.log"
ROOT_PROMPT = r"root@[^\r\n]*# "


def command_output(child: pexpect.spawn, command: str, timeout: int = 90) -> str:
    child.sendline(command)
    child.expect(ROOT_PROMPT, timeout=timeout)
    lines = []
    for line in child.before.splitlines():
        stripped = line.strip()
        if stripped and stripped != command:
            lines.append(stripped)
    return "\n".join(lines)


def require_output(output: str, expected: str, description: str) -> None:
    if expected not in output:
        raise RuntimeError(f"{description}失败，未找到 {expected!r}：{output!r}")


def wait_for_server(process: subprocess.Popen) -> None:
    for _ in range(30):
        if process.poll() is not None:
            raise RuntimeError("HTTP feed 服务启动失败")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=1):
                return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("HTTP feed 服务连接超时")


def main() -> int:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    server_log = (ROOT_DIR / "artifacts" / "opkg-http.log").open("w", encoding="utf-8")
    server = subprocess.Popen(
        [sys.executable, "-m", "http.server", "8080", "--bind", "0.0.0.0",
         "--directory", str(FEED_DIR)],
        cwd=str(ROOT_DIR),
        stdout=server_log,
        stderr=subprocess.STDOUT,
        text=True,
    )
    child = None
    log = None

    try:
        wait_for_server(server)
        log = LOG_PATH.open("w", encoding="utf-8")
        child = pexpect.spawn(
            "bash",
            [str(ROOT_DIR / "scripts" / "run-firmware.sh"), "snapshot"],
            cwd=str(ROOT_DIR),
            encoding="utf-8",
            codec_errors="replace",
            timeout=240,
            env=dict(os.environ, SSH_PORT="none"),
        )
        child.logfile = log

        index = child.expect([r"login:", ROOT_PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(ROOT_PROMPT, timeout=60)

        update_output = command_output(child, "opkg update", timeout=120)
        require_output(update_output, "sixlinux-cortexa53", "opkg 源更新")

        package_list = command_output(child, "opkg list sixlinux-hello")
        require_output(package_list, "1.1-r0", "1.1 软件包索引")

        command_output(child, "opkg install sixlinux-hello=1.0-r0", timeout=120)
        require_output(command_output(child, "sixlinux-hello"), "SixLinux hello v1.0", "1.0 安装")

        command_output(child, "opkg upgrade sixlinux-hello", timeout=120)
        require_output(command_output(child, "sixlinux-hello"), "SixLinux hello v1.1", "1.1 升级")

        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=90)
        print("opkg HTTP 软件仓库、1.0 安装及 1.1 升级验证通过。")
        print(f"测试日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"opkg 测试失败：{exc}", file=sys.stderr)
        print(f"请检查日志：{LOG_PATH}", file=sys.stderr)
        if child is not None:
            child.close(force=True)
        return 1
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
        server_log.close()
        if log is not None:
            log.close()


if __name__ == "__main__":
    sys.exit(main())
