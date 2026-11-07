#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import time
import pexpect

ROOT = Path(__file__).resolve().parents[1]
PROMPT = r"root@[^\r\n]*# "
KEY = ROOT / "artifacts" / "keys" / "sixlinux-dev-key"


def run(child, command, timeout=60):
    child.sendline(command)
    child.expect(PROMPT, timeout=timeout)
    print(f"\n### {command}\n{child.before}")


def main():
    child = pexpect.spawn("bash", [str(ROOT / "scripts" / "run-firmware.sh"), "snapshot"],
                          cwd=str(ROOT), encoding="utf-8", codec_errors="replace", timeout=240)
    try:
        index = child.expect([r"login:", PROMPT], timeout=240)
        if index == 0:
            child.sendline("root")
            child.expect(PROMPT, timeout=60)
        run(child, "sshd -V")
        run(child, "sshd -h")
        time.sleep(1)
        result = subprocess.run([
            "ssh", "-i", str(KEY), "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-p", "2222",
            "dev@127.0.0.1", "id -un"
        ], capture_output=True, text=True, timeout=20)
        print(f"\n### SSH result {result.returncode}\n{result.stdout}\n{result.stderr}")
        child.expect(PROMPT, timeout=20)
        print(f"\n### sshd foreground output\n{child.before}")
        run(child, "poweroff")
        child.expect(pexpect.EOF, timeout=90)
        return 0
    except Exception as exc:
        print(exc, file=sys.stderr)
        child.close(force=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
