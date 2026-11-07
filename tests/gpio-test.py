#!/usr/bin/env python3
"""在直接启动（secure=off）镜像中验证 PL061 GPIO 子系统。"""

from pathlib import Path
import sys

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "gpio-test.log"
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
        index = child.expect([r"login:", ROOT_PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(ROOT_PROMPT, timeout=60)

        command_output(
            child,
            "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug",
        )

        gpio_list = command_output(child, "ls /dev/gpiochip* 2>&1")
        require_output(gpio_list, "/dev/gpiochip0", "GPIO chardev 节点")

        result = command_output(child, "sixlinux-boardtest gpio", timeout=120)
        require_output(result, "SUMMARY gpio PASS", "GPIO 板级测试")

        summary = [line for line in result.splitlines() if "gpio debugfs" in line]
        check_lines = [line for line in result.splitlines() if line.startswith("CHECK gpio/")]
        if not check_lines:
            raise RuntimeError(f"没有收到 GPIO 检查结果：{result!r}")

        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=90)
        print("PL061 GPIO 直接启动验证通过。")
        for line in check_lines:
            print(line)
        print(f"测试日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"GPIO 测试失败：{exc}", file=sys.stderr)
        print(f"请检查日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
