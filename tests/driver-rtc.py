#!/usr/bin/env python3
"""在 SixLinux QEMU 中验证 RTC platform driver 的 MMIO、IRQ 和 debugfs。"""

from pathlib import Path
import sys

import os

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "rtc-driver-test.log"
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


def numeric_line(output: str, description: str) -> int:
    lines = output.splitlines()
    if len(lines) != 1 or not lines[0].isdigit():
        raise RuntimeError(f"{description}输出不是单个整数：{output!r}")
    return int(lines[0])


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
        index = child.expect([r"login:", ROOT_PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(ROOT_PROMPT, timeout=60)

        command_output(child, "modprobe sixlinux_rtc")
        command_output(child, "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug")

        rtc_id = numeric_line(command_output(child, "cat /sys/kernel/debug/sixlinux_rtc/id"), "AMBA ID")
        if (rtc_id & 0x000fffff) != 0x00041031:
            raise RuntimeError(f"AMBA ID 不匹配：0x{rtc_id:08x}")

        numeric_line(command_output(child, "cat /sys/kernel/debug/sixlinux_rtc/data"), "RTC 数据")

        command_output(child, "sleep 2")
        first_count = numeric_line(command_output(child, "cat /sys/kernel/debug/sixlinux_rtc/irq_count"), "首次 IRQ 计数")
        if first_count < 1:
            raise RuntimeError("未收到第一次 RTC alarm 中断")

        command_output(child, "echo 1 > /sys/kernel/debug/sixlinux_rtc/trigger")
        command_output(child, "sleep 2")
        second_count = numeric_line(command_output(child, "cat /sys/kernel/debug/sixlinux_rtc/irq_count"), "第二次 IRQ 计数")
        if second_count <= first_count:
            raise RuntimeError("debugfs trigger 未产生新的 RTC 中断")

        dmesg = command_output(child, "dmesg")
        if "SixLinux RTC probed" not in dmesg:
            raise RuntimeError("dmesg 中缺少 RTC probe 日志")

        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=90)
        print(f"RTC platform driver MMIO/IRQ 验证通过：AMBA ID=0x{rtc_id:08x}, IRQ {first_count}→{second_count}")
        print(f"测试日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"RTC 驱动测试失败：{exc}", file=sys.stderr)
        print(f"请检查日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
