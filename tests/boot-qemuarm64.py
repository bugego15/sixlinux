#!/usr/bin/env python3
"""启动 SixLinux QEMU 镜像，登录并执行最小运行时检查。"""

from pathlib import Path
import sys

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "qemu-boot.log"
PROMPT = r"root@[^\r\n]*# "


def command_output(child: pexpect.spawn, command: str, timeout: int = 60) -> str:
    child.sendline(command)
    child.expect(PROMPT, timeout=timeout)
    lines = []
    for line in child.before.splitlines():
        stripped = line.strip()
        if stripped and stripped != command:
            lines.append(stripped)
    return "\n".join(lines)


def require_line(output: str, expected: str, description: str) -> None:
    if expected not in output.splitlines():
        raise RuntimeError(f"{description}检查失败，期望 {expected!r}，实际输出：{output!r}")


def main() -> int:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    log = LOG_PATH.open("w", encoding="utf-8")
    child = pexpect.spawn(
        "bash",
        [str(ROOT_DIR / "scripts" / "run-qemuarm64.sh"), "snapshot"],
        cwd=str(ROOT_DIR),
        encoding="utf-8",
        codec_errors="replace",
        timeout=240,
    )
    child.logfile = log

    try:
        index = child.expect([r"login:", PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(PROMPT, timeout=60)

        require_line(command_output(child, "uname -m"), "aarch64", "架构")
        require_line(command_output(child, "nproc"), "2", "vCPU 数量")

        os_release = command_output(child, "cat /etc/os-release")
        if "SixLinux" not in os_release:
            raise RuntimeError(f"发行版标识检查失败：{os_release!r}")

        state = command_output(child, "systemctl is-system-running", timeout=90)
        require_line(state, "running", "systemd 状态")

        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=90)
        print("SixLinux QEMU 直接内核启动、登录、架构、SMP 和 systemd 检查通过。")
        print(f"串口日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"QEMU 启动测试失败：{exc}", file=sys.stderr)
        print(f"请检查串口日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
