#!/usr/bin/env python3
"""验证 release 镜像的非 root SSH 公钥登录及拒绝策略。"""

from pathlib import Path
import subprocess
import sys
import time

import pexpect

ROOT_DIR = Path(__file__).resolve().parents[1]
KEY_PATH = ROOT_DIR / "artifacts" / "keys" / "sixlinux-dev-key"
LOG_PATH = ROOT_DIR / "artifacts" / "release-security.log"
ROOT_PROMPT = r"root@[^\r\n]*# "


def ssh_command(user: str, command: str, key: bool = True) -> subprocess.CompletedProcess:
    args = [
        "ssh",
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-p", "2222",
    ]
    if key:
        args += ["-i", str(KEY_PATH)]
    else:
        args += ["-o", "PubkeyAuthentication=no",
                 "-o", "PreferredAuthentications=password",
                 "-o", "NumberOfPasswordPrompts=0"]
    args.append(f"{user}@127.0.0.1")
    args.append(command)
    return subprocess.run(args, capture_output=True, text=True, timeout=25)


def main() -> int:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    log = LOG_PATH.open("w", encoding="utf-8")
    child = pexpect.spawn(
        "bash",
        [str(ROOT_DIR / "scripts" / "run-release.sh"), "snapshot"],
        cwd=str(ROOT_DIR),
        encoding="utf-8",
        codec_errors="replace",
        timeout=240,
    )
    child.logfile = log

    try:
        # release 镜像的 root 密码已锁定，控制台只等待 sshd 起来，不做 root 登录。
        child.expect([r"login:", ROOT_PROMPT], timeout=240)
        time.sleep(2)

        result = ssh_command("dev", "id -un")
        if result.returncode != 0 or result.stdout.strip() != "dev":
            raise RuntimeError(f"dev 公钥登录失败：{result.stdout}{result.stderr}")

        result = ssh_command("dev", "sudo -n id -u root")
        if result.returncode != 0:
            raise RuntimeError(f"dev sudo 失败：{result.stdout}{result.stderr}")

        result = ssh_command("dev", "sudo -n sshd -T")
        sshd_config = result.stdout.lower()
        required = [
            "permitrootlogin no",
            "passwordauthentication no",
            "pubkeyauthentication yes",
            "permitemptypasswords no",
            "allowusers dev",
            "x11forwarding no",
        ]
        for item in required:
            if item not in sshd_config:
                raise RuntimeError(f"sshd 配置缺少 {item}：{result.stdout}{result.stderr}")

        result = ssh_command("dev", "sudo -n systemctl is-system-running")
        if result.returncode != 0 or result.stdout.strip() != "running":
            raise RuntimeError(f"systemd 状态异常：{result.stdout}{result.stderr}")

        root_result = ssh_command("root", "true")
        if root_result.returncode == 0:
            raise RuntimeError("root SSH 登录未按预期被拒绝")

        password_result = ssh_command("dev", "true", key=False)
        if password_result.returncode == 0:
            raise RuntimeError("密码认证未按预期被拒绝")

        result = ssh_command("dev", "sudo -n poweroff")
        if result.returncode != 0:
            raise RuntimeError(f"dev 关机失败：{result.stdout}{result.stderr}")
        child.expect(pexpect.EOF, timeout=90)
        print("release SSH 公钥登录、sudo、root/密码拒绝及 sshd 配置验证通过。")
        print(f"测试日志：{LOG_PATH}")
        return 0
    except Exception as exc:
        print(f"release 安全测试失败：{exc}", file=sys.stderr)
        print(f"请检查日志：{LOG_PATH}", file=sys.stderr)
        child.close(force=True)
        return 1
    finally:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
