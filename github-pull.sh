#!/bin/bash
# GitHub main 최신 커밋을 받아 /opt/wifi-remocon 에 반영한다.
# git이 없는 보드(Yocto)에서도 python3 + HTTPS 로 동작한다.
set -euo pipefail
cd "$(dirname "$0")"
exec /usr/bin/python3 - "$@" <<'PY'
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

REPO = os.environ.get("WIFI_REMOCON_REPO", "fourhand/wifi-remocon")
BRANCH = os.environ.get("WIFI_REMOCON_BRANCH", "main")
DEST = os.environ.get("WIFI_REMOCON_DIR", os.path.dirname(os.path.abspath(__file__)))
SHA_FILE = os.path.join(DEST, ".deploy-sha")
LOCK_FILE = os.path.join(DEST, ".deploy-lock")
LOG_PREFIX = "[github-pull]"

PRESERVE = {
    "logs",
    "schedules.db",
    "run-forever.sh",
    ".deploy-sha",
    ".deploy-lock",
}
SKIP_PREFIXES = ("circuit/", ".git/", "venv/", "__pycache__/")


def log(msg: str) -> None:
    print(f"{LOG_PREFIX} {msg}", flush=True)


def request_json(url: str):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "wifi-remocon-updater",
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def download(url: str, dest: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "wifi-remocon-updater"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dest, "wb") as out:
        shutil.copyfileobj(resp, out)


def acquire_lock() -> None:
    now = time.time()
    if os.path.exists(LOCK_FILE):
        age = now - os.path.getmtime(LOCK_FILE)
        if age < 300:
            log("다른 업데이트가 실행 중이라 건너뜁니다.")
            sys.exit(0)
    with open(LOCK_FILE, "w") as f:
        f.write(str(os.getpid()))


def latest_sha() -> str:
    data = request_json(f"https://api.github.com/repos/{REPO}/commits/{BRANCH}")
    sha = data.get("sha")
    if not sha:
        raise RuntimeError("GitHub API에서 sha를 찾지 못했습니다.")
    return sha


def copy_tree(src: str, dest: str) -> None:
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        rel_posix = "." if rel == "." else rel.replace(os.sep, "/")
        # skip noisy / heavy paths
        dirs[:] = [
            d
            for d in dirs
            if not any((f"{rel_posix}/{d}/" if rel_posix != "." else f"{d}/").startswith(p) for p in SKIP_PREFIXES)
            and d not in PRESERVE
            and d != "__pycache__"
        ]
        dest_root = dest if rel == "." else os.path.join(dest, rel)
        os.makedirs(dest_root, exist_ok=True)
        for name in files:
            if name in PRESERVE and rel == ".":
                continue
            if name.endswith(".pyc"):
                continue
            shutil.copy2(os.path.join(root, name), os.path.join(dest_root, name))


def restart_server() -> None:
    log("서버 재시작 (inittab respawn 또는 직접 기동)")
    subprocess.call(["pkill", "-f", f"{DEST}/control-server.py"])
    time.sleep(2)
    if subprocess.call(["pgrep", "-f", f"{DEST}/control-server.py"], stdout=subprocess.DEVNULL) != 0:
        log("respawn이 없어 start-server.sh로 기동합니다.")
        start = os.path.join(DEST, "start-server.sh")
        if os.path.exists(start):
            subprocess.Popen(
                ["/bin/bash", start],
                cwd=DEST,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )


def main() -> int:
    acquire_lock()
    try:
        sha = latest_sha()
        prev = ""
        if os.path.exists(SHA_FILE):
            prev = open(SHA_FILE, encoding="utf-8").read().strip()
        if prev == sha:
            log(f"이미 최신입니다 ({sha[:10]})")
            return 0

        log(f"새 커밋 {sha[:10]} (이전 {prev[:10] or '없음'}) 받는 중...")
        url = f"https://github.com/{REPO}/archive/{sha}.tar.gz"
        with tempfile.TemporaryDirectory() as tmp:
            tgz = os.path.join(tmp, "src.tar.gz")
            download(url, tgz)
            with tarfile.open(tgz, "r:gz") as tar:
                tar.extractall(tmp)
            extracted = [
                os.path.join(tmp, name)
                for name in os.listdir(tmp)
                if os.path.isdir(os.path.join(tmp, name))
            ]
            if not extracted:
                raise RuntimeError("압축에서 소스 디렉터리를 찾지 못했습니다.")
            copy_tree(extracted[0], DEST)
            for script in os.listdir(DEST):
                if script.endswith(".sh"):
                    path = os.path.join(DEST, script)
                    os.chmod(path, 0o755)

        with open(SHA_FILE, "w", encoding="utf-8") as f:
            f.write(sha + "\n")
        log("파일 반영 완료")
        restart_server()
        log("배포 완료")
        return 0
    finally:
        try:
            os.remove(LOCK_FILE)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"실패: {exc}")
        sys.exit(1)
PY
