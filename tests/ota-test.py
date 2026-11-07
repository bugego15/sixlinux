#!/usr/bin/env python3
"""验证 A/B OTA 升级、试启动确认和失败回滚。"""

from pathlib import Path
import json
import os
import shutil
import socket
import subprocess
import sys
import time

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
AB_DIR = ROOT_DIR / "artifacts" / "ab"
AB_BASE = AB_DIR / "sixlinux-ab.img"
AB_WORK = AB_DIR / "work.img"
AB_ENV = AB_DIR / "base.env"
OTA_DIR = ROOT_DIR / "artifacts" / "ota"
OTA_ENV = OTA_DIR / "ota.env"
KEY_PATH = ROOT_DIR / "artifacts" / "keys" / "sixlinux-dev-key"
LOG_PATH = ROOT_DIR / "artifacts" / "ota-test.log"
JSON_PATH = ROOT_DIR / "artifacts" / "ota-test.json"
SSH_PORT = 2225


def read_env(path: Path) -> dict:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def ssh_run(command: str, timeout: int = 180) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            "ssh",
            "-i", str(KEY_PATH),
            "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-p", str(SSH_PORT),
            "dev@127.0.0.1",
            f"sudo -n {command}",
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def wait_ssh(deadline: float) -> bool:
    while time.time() < deadline:
        try:
            result = subprocess.run(
                [
                    "ssh",
                    "-i", str(KEY_PATH),
                    "-o", "IdentitiesOnly=yes",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", str(SSH_PORT),
                    "dev@127.0.0.1",
                    "id -un",
                ],
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.returncode == 0 and result.stdout.strip() == "dev":
                return True
        except Exception:  # noqa: BLE001 - 启动早期连接失败属于预期
            pass
        time.sleep(2)
    return False


def start_http() -> tuple[subprocess.Popen, object]:
    log = (ROOT_DIR / "artifacts" / "ota-http.log").open("w", encoding="utf-8")
    server = subprocess.Popen(
        [
            sys.executable, "-m", "http.server", "8080",
            "--bind", "0.0.0.0",
            "--directory", str(OTA_DIR),
        ],
        cwd=str(ROOT_DIR),
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
    )
    for _ in range(50):
        if server.poll() is not None:
            raise RuntimeError("OTA HTTP 服务启动失败（8080 端口可能被占用）")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=1):
                return server, log
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("OTA HTTP 服务连接超时")


def boot(expect_login: bool, timeout: int = 300) -> pexpect.spawn | None:
    child = pexpect.spawn(
        "bash",
        [str(ROOT_DIR / "scripts" / "run-ab.sh")],
        cwd=str(ROOT_DIR),
        encoding="utf-8",
        codec_errors="replace",
        timeout=timeout,
        env=dict(os.environ, AB_IMAGE=str(AB_WORK), SSH_PORT=str(SSH_PORT)),
    )
    child.logfile = SERIAL_LOG
    if expect_login:
        child.expect(r"login:", timeout=timeout)
        if not wait_ssh(time.time() + 120):
            child.close(force=True)
            raise RuntimeError("A/B 系统启动后 SSH 未就绪")
        return child

    index = child.expect([r"login:", pexpect.EOF], timeout=timeout)
    if index == 0:
        child.close(force=True)
        raise RuntimeError(f"预期第 {BOOT_ATTEMPT} 次启动失败，实际进入了系统")
    return None


def shutdown(child: pexpect.spawn | None) -> None:
    if child is None:
        return
    try:
        ssh_run("poweroff", timeout=30)
    except Exception:  # noqa: BLE001 - 关机时连接可能提前断开
        pass
    try:
        child.expect(pexpect.EOF, timeout=90)
    except Exception:  # noqa: BLE001
        child.close(force=True)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


SERIAL_LOG = None
BOOT_ATTEMPT = 0


def main() -> int:
    global SERIAL_LOG, BOOT_ATTEMPT
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    require(AB_BASE.is_file(), f"缺少 A/B 基础磁盘 {AB_BASE}，请先执行 make ab-disk")
    require(OTA_ENV.is_file(), f"缺少 OTA 升级包信息 {OTA_ENV}，请先执行 make ota-bundle")

    ab = read_env(AB_ENV)
    ota = read_env(OTA_ENV)
    bundle = ota["OTA_BUNDLE"]
    payload_version = ota["OTA_PAYLOAD_VERSION"]
    tampered = OTA_DIR / f"{bundle}-tampered.tar.gz"
    tampered_sig = OTA_DIR / f"{tampered.name}.sig"

    shutil.copyfile(AB_BASE, AB_WORK)

    server, server_log = start_http()
    SERIAL_LOG = LOG_PATH.open("w", encoding="utf-8")
    results = []

    def record(name: str, ok: bool, detail: str) -> None:
        results.append({"name": name, "status": "PASS" if ok else "FAIL",
                        "detail": detail})
        print(f"{results[-1]['status']:4s} {name:18s} {detail}")

    try:
        # 阶段 1：初始系统运行在 slot A
        BOOT_ATTEMPT = 1
        child = boot(True)
        status = ssh_run("sixlinux-ota status").stdout
        require("slot=a" in status, f"初始状态不是 slot a：{status!r}")
        require("/dev/vda2" in status, f"初始根设备不是 /dev/vda2：{status!r}")
        record("initial-slot-a", True, "root=/dev/vda2 slot=a")

        # 阶段 2：从签名 OTA 源升级到 slot B
        result = ssh_run(f"sixlinux-ota install http://10.0.2.2:8080/{bundle}",
                         timeout=300)
        output = result.stdout + result.stderr
        require(result.returncode == 0 and "staged" in output,
                f"OTA 安装失败：{output!r}")
        record("install", True, "bundle 验签通过并写入 slot B")
        shutdown(child)

        # 阶段 3：重启后运行在 slot B，且试启动被确认
        BOOT_ATTEMPT = 2
        child = boot(True)
        time.sleep(2)
        status = ssh_run("sixlinux-ota status").stdout
        require("slot=b" in status, f"升级后状态不是 slot b：{status!r}")
        require("/dev/vda3" in status, f"升级后根设备不是 /dev/vda3：{status!r}")
        require("pending=0" in status, f"试启动未被 mark-good 确认：{status!r}")
        version = ssh_run("cat /etc/sixlinux-ota-version").stdout.strip()
        require(version == payload_version,
                f"新槽版本标记错误：{version!r} != {payload_version!r}")
        record("boot-slot-b", True, f"root=/dev/vda3 version={version} pending=0")

        # 阶段 4：篡改升级包必须被签名校验拒绝
        payload = (OTA_DIR / bundle).read_bytes()
        tampered.write_bytes(payload[:1024] + bytes([payload[1024] ^ 0xFF]) +
                             payload[1025:])
        tampered_sig.write_bytes((OTA_DIR / f"{bundle}.sig").read_bytes())
        result = ssh_run(
            f"sixlinux-ota install http://10.0.2.2:8080/{tampered.name}",
            timeout=120,
        )
        output = result.stdout + result.stderr
        require(result.returncode != 0 and "签名校验失败" in output,
                f"篡改升级包没有被拒绝：{output!r}")
        status = ssh_run("sixlinux-ota status").stdout
        require("slot=b" in status and "pending=0" in status,
                f"篡改测试改变了启动状态：{status!r}")
        record("tamper-rejected", True, "篡改升级包验签失败且启动状态未变")
        shutdown(child)

        # 阶段 4：破坏 slot B，验证连续失败后回滚到 slot A
        b_start_mb = int(ab["AB_SLOT_B_START_MB"])
        subprocess.run(
            ["dd", "if=/dev/zero", f"of={AB_WORK}", "bs=1M",
             f"seek={b_start_mb}", "count=8", "conv=notrunc"],
            check=True, capture_output=True,
        )
        state_file = AB_DIR / "rollback-state.env"
        state_file.write_text("slot=b\nprev=a\npending=1\nbootcount=0\n",
                              encoding="utf-8")
        boot_start_bytes = int(ab["AB_BOOT_START_MB"]) * 1024 * 1024
        subprocess.run(
            ["mcopy", "-o", "-i", f"{AB_WORK}@@{boot_start_bytes}",
             str(state_file), "::/state.env"],
            check=True, capture_output=True,
        )

        failed_boots = 0
        for attempt in (1, 2):
            BOOT_ATTEMPT = 2 + attempt
            boot(False, timeout=240)
            failed_boots += 1
        record("failed-boots", failed_boots == 2,
               f"连续 {failed_boots} 次启动失败（预期）")

        BOOT_ATTEMPT = 5
        child = boot(True, timeout=300)
        status = ssh_run("sixlinux-ota status").stdout
        require("slot=a" in status, f"回滚后状态不是 slot a：{status!r}")
        require("/dev/vda2" in status, f"回滚后根设备不是 /dev/vda2：{status!r}")
        record("rollback", True, "连续失败后回滚到 slot A")
        shutdown(child)

        serial = LOG_PATH.read_text(encoding="utf-8", errors="replace")
        require("too many failed boots" in serial,
                "串口日志缺少回滚提示")
        require("OTA: booting slot b" in serial, "串口日志缺少 slot b 启动记录")
        record("serial-log", True, "串口日志包含回滚与槽位切换记录")

        summary = {"total": len(results),
                   "passed": sum(1 for r in results if r["status"] == "PASS"),
                   "failed": sum(1 for r in results if r["status"] != "PASS"),
                   "tests": results}
        JSON_PATH.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
        print()
        print(f"A/B OTA 测试结果：{summary['passed']}/{summary['total']} 通过")
        print(f"串口日志：{LOG_PATH}")
        print(f"JSON：{JSON_PATH}")
        return 0
    except Exception as exc:  # noqa: BLE001 - 汇总失败原因
        print(f"A/B OTA 测试失败：{exc}", file=sys.stderr)
        print(f"请检查串口日志：{LOG_PATH}", file=sys.stderr)
        summary = {"total": len(results),
                   "passed": sum(1 for r in results if r["status"] == "PASS"),
                   "failed": len(results) - sum(1 for r in results if r["status"] == "PASS"),
                   "error": str(exc),
                   "tests": results}
        JSON_PATH.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
        return 1
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
        server_log.close()
        for path in (tampered, tampered_sig):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        if SERIAL_LOG is not None and not SERIAL_LOG.closed:
            SERIAL_LOG.close()


if __name__ == "__main__":
    sys.exit(main())
