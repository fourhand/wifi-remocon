#!/usr/bin/env python3
"""GitHub main 최신 커밋을 확인하고, 변경 시에만 반영 후 서버를 재시작한다."""
from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

REPO = os.environ.get("WIFI_REMOCON_REPO", "fourhand/wifi-remocon")
BRANCH = os.environ.get("WIFI_REMOCON_BRANCH", "main")
DEST = Path(os.environ.get("WIFI_REMOCON_DIR", Path(__file__).resolve().parent))
SHA_FILE = DEST / ".deploy-sha"
LOCK_FILE = DEST / ".deploy-lock"
LOG_PREFIX = "[github-pull]"

PRESERVE = {
    "logs",
    "schedules.db",
    "run-forever.sh",
    "venv",
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


def download(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "wifi-remocon-updater"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dest, "wb") as out:
        shutil.copyfileobj(resp, out)


def acquire_lock() -> None:
    now = time.time()
    if LOCK_FILE.exists():
        age = now - LOCK_FILE.stat().st_mtime
        if age < 300:
            log("다른 업데이트가 실행 중이라 건너뜁니다.")
            sys.exit(0)
    LOCK_FILE.write_text(str(os.getpid()), encoding="utf-8")


def release_lock() -> None:
    try:
        LOCK_FILE.unlink(missing_ok=True)
    except OSError:
        pass


def latest_remote_sha() -> str:
    data = request_json(f"https://api.github.com/repos/{REPO}/commits/{BRANCH}")
    sha = data.get("sha")
    if not sha:
        raise RuntimeError("GitHub API에서 sha를 찾지 못했습니다.")
    return sha


def find_git() -> str | None:
    found = shutil.which("git")
    if found:
        return found
    if platform.system() == "Windows":
        for candidate in (
            r"C:\Program Files\Git\cmd\git.exe",
            r"C:\Program Files (x86)\Git\cmd\git.exe",
        ):
            if os.path.isfile(candidate):
                return candidate
    return None


def run_git(git: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [git, *args],
        cwd=str(DEST),
        capture_output=True,
        text=True,
        check=check,
        encoding="utf-8",
        errors="replace",
    )


def is_git_repo(git: str) -> bool:
    result = run_git(git, "rev-parse", "--is-inside-work-tree", check=False)
    return result.returncode == 0 and result.stdout.strip() == "true"


def current_deployed_sha(git: str | None) -> str:
    if SHA_FILE.exists():
        return SHA_FILE.read_text(encoding="utf-8").strip()
    if git and is_git_repo(git):
        result = run_git(git, "rev-parse", "HEAD", check=False)
        if result.returncode == 0:
            return result.stdout.strip()
    return ""


def git_is_dirty(git: str) -> bool:
    result = run_git(git, "status", "--porcelain", check=False)
    return bool(result.stdout.strip())


def update_via_git(git: str, remote_sha: str) -> None:
    run_git(git, "fetch", "--all", check=False)
    # origin/<branch>가 있으면 그걸 우선 사용
    origin_ref = f"origin/{BRANCH}"
    rev = run_git(git, "rev-parse", origin_ref, check=False)
    target = rev.stdout.strip() if rev.returncode == 0 else remote_sha
    if git_is_dirty(git):
        raise RuntimeError("로컬 변경사항이 있어 git 업데이트를 건너뜁니다. 커밋/정리 후 다시 시도하세요.")
    run_git(git, "reset", "--hard", target)
    SHA_FILE.write_text(remote_sha + "\n", encoding="utf-8")
    log(f"git reset --hard {target[:10]} 완료")


def copy_tree(src: Path, dest: Path) -> None:
    for root, dirs, files in os.walk(src):
        root_path = Path(root)
        rel = root_path.relative_to(src)
        rel_posix = "." if str(rel) == "." else rel.as_posix()
        dirs[:] = [
            d
            for d in dirs
            if not any(
                (f"{rel_posix}/{d}/" if rel_posix != "." else f"{d}/").startswith(p)
                for p in SKIP_PREFIXES
            )
            and d not in PRESERVE
            and d != "__pycache__"
        ]
        dest_root = dest if str(rel) == "." else dest / rel
        dest_root.mkdir(parents=True, exist_ok=True)
        for name in files:
            if name in PRESERVE and str(rel) == ".":
                continue
            if name.endswith(".pyc"):
                continue
            shutil.copy2(root_path / name, dest_root / name)


def update_via_tarball(remote_sha: str) -> None:
    url = f"https://github.com/{REPO}/archive/{remote_sha}.tar.gz"
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        tgz = tmp_path / "src.tar.gz"
        download(url, tgz)
        with tarfile.open(tgz, "r:gz") as tar:
            tar.extractall(tmp_path)
        extracted = [p for p in tmp_path.iterdir() if p.is_dir()]
        if not extracted:
            raise RuntimeError("압축에서 소스 디렉터리를 찾지 못했습니다.")
        copy_tree(extracted[0], DEST)
        for script in DEST.glob("*.sh"):
            try:
                os.chmod(script, 0o755)
            except OSError:
                pass
    SHA_FILE.write_text(remote_sha + "\n", encoding="utf-8")
    log("tarball 파일 반영 완료")


def control_server_running() -> bool:
    if platform.system() == "Windows":
        ps = (
            "$p = Get-CimInstance Win32_Process | "
            "Where-Object { $_.CommandLine -and $_.CommandLine -match 'control-server\\.py' }; "
            "if ($p) { exit 0 } else { exit 1 }"
        )
        return (
            subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
                check=False,
            ).returncode
            == 0
        )
    return subprocess.call(["pgrep", "-f", f"{DEST.as_posix()}/control-server.py"], stdout=subprocess.DEVNULL) == 0


def kill_control_server() -> None:
    if platform.system() == "Windows":
        ps = (
            "Get-CimInstance Win32_Process | "
            "Where-Object { $_.CommandLine -and $_.CommandLine -match 'control-server\\.py' } | "
            "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
        )
        subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
            check=False,
        )
    else:
        subprocess.call(["pkill", "-f", f"{DEST.as_posix()}/control-server.py"])
    for _ in range(10):
        if not control_server_running():
            break
        time.sleep(0.5)


def start_control_server() -> None:
    if platform.system() == "Windows":
        # 기존 자동시작 작업이 있으면 그걸로 기동 (SYSTEM/권한 일관성)
        for _ in range(3):
            run = subprocess.run(
                ["schtasks", "/Run", "/TN", "WifiRemoconControlServer"],
                capture_output=True,
                text=True,
                check=False,
                encoding="utf-8",
                errors="replace",
            )
            if run.returncode == 0:
                log("WifiRemoconControlServer 작업을 다시 실행했습니다.")
                return
            time.sleep(2)
        bat = DEST / "start-server-autostart.bat"
        if bat.exists():
            flags = 0
            if hasattr(subprocess, "DETACHED_PROCESS"):
                flags |= subprocess.DETACHED_PROCESS
            if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
                flags |= subprocess.CREATE_NEW_PROCESS_GROUP
            subprocess.Popen(
                ["cmd.exe", "/c", str(bat)],
                cwd=str(DEST),
                creationflags=flags,
                close_fds=True,
            )
            log("start-server-autostart.bat으로 서버를 기동했습니다.")
            return
        log("서버 시작 스크립트/작업을 찾지 못했습니다.")
        return

    # Linux/Yocto: inittab respawn 또는 start-server.sh
    time.sleep(2)
    if not control_server_running():
        start = DEST / "start-server.sh"
        if start.exists():
            subprocess.Popen(
                ["/bin/bash", str(start)],
                cwd=str(DEST),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )


def restart_server() -> None:
    log("서버 재시작")
    kill_control_server()
    start_control_server()


def main() -> int:
    acquire_lock()
    try:
        remote_sha = latest_remote_sha()
        git = find_git()
        prev = current_deployed_sha(git)
        if prev == remote_sha:
            log(f"이미 최신입니다 ({remote_sha[:10]})")
            return 0

        log(f"새 커밋 {remote_sha[:10]} (이전 {prev[:10] or '없음'}) 반영 중...")
        if git and is_git_repo(git):
            try:
                update_via_git(git, remote_sha)
            except RuntimeError as exc:
                log(str(exc))
                return 0
        else:
            update_via_tarball(remote_sha)

        restart_server()
        log("배포 완료")
        return 0
    finally:
        release_lock()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"실패: {exc}")
        sys.exit(1)
