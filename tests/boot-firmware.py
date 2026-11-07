#!/usr/bin/env python3
"""零输入验证 TF-A → U-Boot → SixLinux 自动启动链。"""

from pathlib import Path
import sys

import os

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "firmware-boot.log"
ROOT_PROMPT = r"root@[^\r\n]*# "


def command_output(child: pexpect.spawn, command: str, timeout: int = 60) -> str:
    child.sendline(command)
    child.expect(ROOT_PROMPT, timeout=timeout)
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
        [str(ROOT_DIR / "scripts" / "run-firmware.sh"), "snapshot"],
        cwd=str(ROOT_DIR),
        encoding="utf-8",
        codec_errors="replace",
        timeout=240,
        env=dict(os.environ, SSH_PORT="none"),
    )
    child.logfile = log

    try:
        # 登录前不向 U-Boot 或 Linux 发送任何内容，验证 CONFIG_BOOTCOMMAND 自动执行。
        index = child.expect([r"login:", ROOT_PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(ROOT_PROMPT, timeout=60)

        require_line(command_output(child, "uname -m"), "aarch64", "架构")
        require_line(command_output(child, "nproc"), "2", "vCPU 数量")

        os_release = command_output(child, "cat /etc/os-release")
        if "SixLinux" not in os_release:
            raise RuntimeError(f"发行版标识检查失败：{os_release!r}")

        state = command_output(child, "systemctl is-system-running", timeout=90)
        require_line(state, "running", "systemd 状态")

        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=90)
        log.flush()
        log.close()
        boot_log = LOG_PATH.read_text(encoding="utf-8", errors="replace")
        for marker, description in (
            ("BL1", "TF-A BL1 启动阶段"),
            ("BL31", "TF-A BL31 启动阶段"),
            ("U-Boot 2024.01", "U-Boot 启动阶段"),
            ("## Flattened Device Tree blob at 44000000", "自动 booti 加载设备树"),
            ("Starting kernel", "Linux 内核启动"),
        ):
            if marker not in boot_log:
                raise RuntimeError(f"串口日志缺少{description}：{marker}")
        if "Scanning for bootflows" in boot_log:
            raise RuntimeError("U-Boot 未按固化的 CONFIG_BOOTCOMMAND 启动")
        if "setenv bootargs" in boot_log:
            raise RuntimeError("串口日志出现手工输入痕迹，自动启动验证不成立")

        print("TF-A → U-Boot → SixLinux 零输入自动启动验证通过。")
        print(f"串口日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"固件自动启动测试失败：{exc}", file=sys.stderr)
        print(f"请检查串口日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        if not log.closed:
            log.close()


if __name__ == "__main__":
    sys.exit(main())
