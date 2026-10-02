# Upload a local Flutter web build to the server over SFTP (paramiko).
# Used by Deploy-Web.ps1 — OpenSSH password prompts hang in non-interactive runs.
#
# Usage:
#   py -3 deploy/publish_web.py
#   py -3 deploy/publish_web.py --skip-nginx

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("ERROR: paramiko required. Install with: py -3 -m pip install paramiko", file=sys.stderr)
    raise SystemExit(1)

HOST = "187.124.92.119"
USER = "root"
REMOTE_DIR = "/var/www/cockpit"
NGINX_REMOTE = "/etc/nginx/sites-available/cockpit-app"


def ssh_password() -> str:
    pw = os.environ.get("COCKPIT_SSH_PASSWORD", "").strip()
    if pw:
        return pw
    # Local-only fallback file (gitignored via info.md workflow — create if needed).
    secret = Path(__file__).resolve().parents[3] / ".deploy-ssh-password"
    if secret.is_file():
        return secret.read_text(encoding="utf-8").strip()
    print(
        "ERROR: set COCKPIT_SSH_PASSWORD or create repo-root .deploy-ssh-password",
        file=sys.stderr,
    )
    raise SystemExit(1)


def ensure_dir(sftp: paramiko.SFTPClient, path: str) -> None:
    parts = path.strip("/").split("/")
    cur = ""
    for part in parts:
        cur += "/" + part
        try:
            sftp.stat(cur)
        except FileNotFoundError:
            sftp.mkdir(cur)


def upload_tree(sftp: paramiko.SFTPClient, local: Path, remote: str) -> int:
    ensure_dir(sftp, remote)
    count = 0
    for root, dirs, files in os.walk(local):
        rel = os.path.relpath(root, local).replace("\\", "/")
        rdir = remote if rel == "." else f"{remote}/{rel}"
        ensure_dir(sftp, rdir)
        for d in dirs:
            ensure_dir(sftp, f"{rdir}/{d}")
        for name in files:
            lp = os.path.join(root, name)
            rp = f"{rdir}/{name}"
            sftp.put(lp, rp)
            count += 1
            if count % 25 == 0:
                print(f"  uploaded {count} files...")
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--web-dir",
        default=str(Path(__file__).resolve().parent.parent / "build" / "web"),
    )
    parser.add_argument(
        "--nginx-conf",
        default=str(Path(__file__).resolve().parent / "nginx-app.conf"),
    )
    parser.add_argument("--skip-nginx", action="store_true")
    parser.add_argument("--remote-dir", default=REMOTE_DIR)
    args = parser.parse_args()
    remote_dir = args.remote_dir

    web_dir = Path(args.web_dir)
    if not web_dir.is_dir():
        print(f"ERROR: missing build output: {web_dir}", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        username=USER,
        password=ssh_password(),
        timeout=30,
        allow_agent=False,
        look_for_keys=False,
    )
    sftp = client.open_sftp()
    try:
        print(f">> Uploading {web_dir} -> {remote_dir}")
        n = upload_tree(sftp, web_dir, remote_dir)
        print(f">> Uploaded {n} files")

        if not args.skip_nginx:
            nginx_local = Path(args.nginx_conf)
            print(f">> Installing nginx site {NGINX_REMOTE}")
            sftp.put(str(nginx_local), NGINX_REMOTE)
            cmd = (
                f"ln -sf {NGINX_REMOTE} /etc/nginx/sites-enabled/cockpit-app && "
                "nginx -t && systemctl reload nginx"
            )
            _, stdout, stderr = client.exec_command(cmd)
            out = stdout.read().decode()
            err = stderr.read().decode()
            code = stdout.channel.recv_exit_status()
            if out.strip():
                print(out)
            if err.strip():
                print(err, file=sys.stderr)
            if code != 0:
                return code

        _, stdout, _ = client.exec_command(f"cat {remote_dir}/BUILD_ID")
        build_id = stdout.read().decode().strip()
        print(f">> Live BUILD_ID={build_id or '(missing)'}")
    finally:
        sftp.close()
        client.close()

    print(">> Publish complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
