#!/usr/bin/env python3
"""手工输入 U-Boot 命令，验证 TF-A → U-Boot → SixLinux 启动链。"""

from pathlib import Path
import sys

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "firmware-boot.log"
ROOT_PROMPT = r"root@[^\r\n]*# "
UBOOT_PROMPT = r"=> "
BOOTARGS = (
    "root=/dev/vda rw console=ttyAMA0 earlycon=pl011,0x09000000 "
    "keep_bootcon ip=dhcp swiotlb=0"
)
BOOT_COMMAND = "booti 0x40200000 - 0x44000000"


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


def wait_uboot_prompt(child: pexpect.spawn, timeout: int = 300) -> None:
    """等待 U-Boot 命令行。

    上游 qemu_arm64_defconfig 默认启用标准启动扫描，没有可启动介质时会扫描
    网络并最终回到命令行。这里先让扫描超时，保证走的是手工命令路径。
    """
    child.expect(r"U-Boot 2024\.01", timeout=timeout)
    child.sendline("")
    child.expect(UBOOT_PROMPT, timeout=timeout)


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
    )
    child.logfile = log

    try:
        wait_uboot_prompt(child)

        # P2 阶段由测试代替人工输入，P3 再把这两条命令固化进 U-Boot。
        child.sendline(f"setenv bootargs {BOOTARGS}")
        child.expect(UBOOT_PROMPT, timeout=30)
        child.sendline(BOOT_COMMAND)
        child.expect("Starting kernel", timeout=120)

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
            (f"setenv bootargs {BOOTARGS}", "手工写入 bootargs"),
            (BOOT_COMMAND, "手工 booti 命令"),
            ("Starting kernel", "Linux 内核启动"),
        ):
            if marker not in boot_log:
                raise RuntimeError(f"串口日志缺少{description}：{marker}")

        print("TF-A → U-Boot → SixLinux 手工启动链验证通过。")
        print(f"串口日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"固件启动链测试失败：{exc}", file=sys.stderr)
        print(f"请检查串口日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        if not log.closed:
            log.close()


if __name__ == "__main__":
    sys.exit(main())
