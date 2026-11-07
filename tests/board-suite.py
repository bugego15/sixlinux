#!/usr/bin/env python3
"""在 SixLinux 目标系统中运行板级验证套件并汇总结果。"""

from pathlib import Path
import json
import os
import socket
import subprocess
import sys
import time

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "artifacts" / "board-test.log"
JSON_PATH = ROOT_DIR / "artifacts" / "board-test.json"
HTTP_DIR = ROOT_DIR / "artifacts" / "board-http"
HTTP_LOG_PATH = ROOT_DIR / "artifacts" / "board-http.log"
KEY_PATH = ROOT_DIR / "artifacts" / "keys" / "sixlinux-dev-key"
ROOT_PROMPT = r"root@[^\r\n]*# "
SSH_PORT = 2223
TEST_TIMEOUT = 300


def ssh_args(command: str) -> list[str]:
    return [
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
    ]


def ssh_run(command: str, timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(
        ssh_args(command),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def wait_for_ssh(deadline: float) -> None:
    last_error = "unknown"
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
                return
            last_error = result.stderr.strip() or f"rc={result.returncode}"
        except Exception as exc:  # noqa: BLE001 - 重试直到超时
            last_error = str(exc)
        time.sleep(2)
    raise RuntimeError(f"等待目标 SSH 就绪超时：{last_error}")


def start_http() -> tuple[subprocess.Popen, object]:
    HTTP_DIR.mkdir(parents=True, exist_ok=True)
    (HTTP_DIR / "boardtest.txt").write_text("sixlinux-boardtest\n", encoding="utf-8")
    log = HTTP_LOG_PATH.open("w", encoding="utf-8")
    server = subprocess.Popen(
        [
            sys.executable, "-m", "http.server", "8080",
            "--bind", "0.0.0.0",
            "--directory", str(HTTP_DIR),
        ],
        cwd=str(ROOT_DIR),
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
    )
    for _ in range(30):
        if server.poll() is not None:
            raise RuntimeError("HTTP feed 服务启动失败（8080 端口可能被占用）")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=1):
                return server, log
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("HTTP feed 服务连接超时")


def main() -> int:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    server, server_log = start_http()
    log = LOG_PATH.open("w", encoding="utf-8")
    child = pexpect.spawn(
        "bash",
        [str(ROOT_DIR / "scripts" / "run-firmware.sh"), "snapshot"],
        cwd=str(ROOT_DIR),
        encoding="utf-8",
        codec_errors="replace",
        timeout=240,
        env=dict(os.environ, SSH_PORT=str(SSH_PORT)),
    )
    child.logfile = log

    results: list[dict] = []
    errors: list[str] = []

    try:
        child.expect([r"login:", ROOT_PROMPT], timeout=240)
        deadline = time.time() + 180
        wait_for_ssh(deadline)

        listing = ssh_run("sixlinux-boardtest --list", timeout=60)
        if listing.returncode != 0:
            raise RuntimeError(
                f"无法获取测试列表（镜像里可能没装 sixlinux-boardtest）："
                f"{listing.stdout}{listing.stderr}"
            )
        tests = [line.strip() for line in listing.stdout.splitlines() if line.strip()]
        if not tests:
            raise RuntimeError("测试列表为空")

        for name in tests:
            started = time.time()
            record = {"name": name, "status": "FAIL", "pass": 0, "fail": 0,
                      "seconds": 0.0, "output": "", "error": ""}
            try:
                result = ssh_run(f"sixlinux-boardtest {name}", timeout=TEST_TIMEOUT)
                record["output"] = (result.stdout + result.stderr).strip()
                summaries = [
                    line for line in result.stdout.splitlines()
                    if line.startswith("SUMMARY ")
                ]
                if summaries:
                    fields = summaries[-1].split()
                    record["pass"] = int(fields[3].split("=")[1])
                    record["fail"] = int(fields[4].split("=")[1])
                if result.returncode == 0 and summaries and fields[2] == "PASS":
                    record["status"] = "PASS"
                else:
                    record["error"] = f"rc={result.returncode}"
            except subprocess.TimeoutExpired:
                record["error"] = f"超时（>{TEST_TIMEOUT}s）"
            except Exception as exc:  # noqa: BLE001 - 单测失败不影响其余测试
                record["error"] = str(exc)
            record["seconds"] = round(time.time() - started, 2)
            results.append(record)
            log.write(f"\n### {name} ({record['seconds']}s) {record['status']}\n")
            log.write(record["output"] + "\n")
            log.flush()
            print(
                f"{record['status']:4s} {name:8s} pass={record['pass']} "
                f"fail={record['fail']} {record['seconds']}s"
                + (f" ({record['error']})" if record["error"] else "")
            )

        try:
            ssh_run("poweroff", timeout=30)
        except Exception:  # noqa: BLE001 - 关机时连接可能提前断开
            pass
        child.expect(pexpect.EOF, timeout=90)
    except Exception as exc:  # noqa: BLE001 - 统一记录并继续清理
        errors.append(str(exc))
        print(f"板级测试运行失败：{exc}", file=sys.stderr)
    finally:
        try:
            child.close(force=True)
        except Exception:  # noqa: BLE001
            pass
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
        server_log.close()
        log.close()

    summary = {
        "total": len(results),
        "passed": sum(1 for r in results if r["status"] == "PASS"),
        "failed": sum(1 for r in results if r["status"] != "PASS"),
        "errors": errors,
        "tests": results,
    }
    JSON_PATH.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print()
    print(f"板级测试结果：{summary['passed']}/{summary['total']} 通过")
    print(f"日志：{LOG_PATH}")
    print(f"JSON：{JSON_PATH}")
    if errors or summary["failed"]:
        for err in errors:
            print(f"运行错误：{err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
