#!/usr/bin/env python3
import sys
import threading
import socket
import json
import time
from typing import Dict, Any
import concurrent.futures

import requests
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from pydantic import BaseModel
import uvicorn
import os
import subprocess
import platform
import shutil
import sqlite3
from datetime import datetime, timedelta

try:
    from zeroconf import ServiceInfo, Zeroconf
    from zeroconf._exceptions import NonUniqueNameException
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False
    NonUniqueNameException = None
    print("[경고] zeroconf가 설치되지 않았습니다. mDNS 기능을 사용할 수 없습니다.")
    print("      설치: pip install zeroconf")

# ========================
# 설정
# ========================
UDP_LISTEN_IP = ""           # 모든 인터페이스
UDP_LISTEN_PORT = 4210       # ESP8266과 동일
DEVICE_TIMEOUT_SEC = 60 * 5  # 5분
SERVER_HOST = "0.0.0.0"
SERVER_PORT = 8000
MDNS_HOSTNAME = "aircon-controller"
MDNS_SERVICE_TYPE = "_http._tcp.local."

HTTP_PATH_SET = "/ac/set"    # ESP8266 코드에 맞춤
HTTP_TIMEOUT = 2.0
# 전체 제어 시, 장치별 최대 대기 시간(초) - 초과 시 타임아웃으로 처리
ALL_CMD_PER_DEVICE_TIMEOUT_SEC = int(os.getenv("ALL_CMD_PER_DEVICE_TIMEOUT_SEC", "10"))

# ========================
# 시계 동기화 설정
# ========================
TIME_SYNC_ENABLED = os.getenv("TIME_SYNC_ENABLED", "1").lower() in ("1", "true", "yes")
TIME_SYNC_INTERVAL_SEC = int(os.getenv("TIME_SYNC_INTERVAL_SEC", str(60 * 60 * 24)))  # 기본 24시간
DEFAULT_NTP_SERVER = "time.apple.com" if platform.system() == "Darwin" else "pool.ntp.org"
NTP_SERVER = os.getenv("NTP_SERVER", DEFAULT_NTP_SERVER)
TIME_SYNC_COMMAND = os.getenv("TIME_SYNC_COMMAND")  # 커스텀 명령이 필요할 때 사용

# ========================
# 장치 목록
# ========================
devices_lock = threading.Lock()
devices: Dict[str, Dict[str, Any]] = {}

# ========================
# UDP 수신 스레드
# ========================
def udp_listener():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((UDP_LISTEN_IP, UDP_LISTEN_PORT))
    print(f"[UDP] Listening on port {UDP_LISTEN_PORT}")

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            msg = json.loads(data.decode("utf-8").strip())
            dev_id = msg.get("id")
            if not dev_id:
                continue

            with devices_lock:
                devices[dev_id] = {
                    "id": dev_id,
                    "ip": msg.get("ip", addr[0]),
                    "port": int(msg.get("port", 80)),
                    "last_seen": time.time(),
                }
        except Exception as e:
            print("[UDP] error:", e)

listener_thread = threading.Thread(target=udp_listener, daemon=True)
listener_thread.start()

# ========================
# FastAPI 서버
# ========================
app = FastAPI(title="IR Remote Server")

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 정적 파일 서빙 (웹 인터페이스) - API 엔드포인트 이후에 마운트

class AcCommand(BaseModel):
    power: str | None = None
    mode: str | None = None
    temp: int | None = None
    fan: str | None = None
    swing: str | None = None

class BatchAcCommand(BaseModel):
    device_ids: list[str]
    command: AcCommand

# ========================
# 예약/스케줄 DB 및 모델
# ========================
DB_PATH = os.path.join(os.path.dirname(__file__), "schedules.db")

class ScheduleItem(BaseModel):
    id: int
    enabled: bool
    power: str  # 'on' | 'off'
    mode: str   # 'cool' | 'hot'
    temp: int
    schedule_type: str  # 'once' | 'daily' | 'weekly'
    date: str | None = None  # YYYY-MM-DD (once)
    weekday: int | None = None  # 0=월 ... 6=일
    start_time_min: int  # 0..1439
    end_time_min: int    # 0..1439

def _db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def _create_schema(conn: sqlite3.Connection):
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS schedules (
            id INTEGER PRIMARY KEY,
            enabled INTEGER NOT NULL DEFAULT 0,
            power TEXT NOT NULL DEFAULT 'on',
            mode TEXT NOT NULL DEFAULT 'cool',
            temp INTEGER NOT NULL DEFAULT 24,
            schedule_type TEXT NOT NULL DEFAULT 'daily',
            date TEXT,
            weekday INTEGER,
            start_time_min INTEGER NOT NULL DEFAULT 540,
            end_time_min INTEGER NOT NULL DEFAULT 1020
        )
    """)
    # 1..7 기본 레코드 보장
    for i in range(1, 8):
        cur.execute("INSERT OR IGNORE INTO schedules(id) VALUES (?)", (i,))
    conn.commit()

def _recreate_db_with_backup():
    try:
        if os.path.exists(DB_PATH):
            backup = DB_PATH + f".bak.{int(time.time())}"
            try:
                os.replace(DB_PATH, backup)
                print(f"[ScheduleDB] Corrupt DB backed up to {backup}")
            except Exception:
                # 백업 실패 시 삭제 시도
                try:
                    os.remove(DB_PATH)
                except Exception:
                    pass
    except Exception as e:
        print(f"[ScheduleDB] Backup/remove failed: {e}")
    # 새로 생성
    try:
        conn = _db()
        try:
            _create_schema(conn)
            print("[ScheduleDB] Recreated new schedules.db")
        finally:
            conn.close()
    except Exception as e:
        print(f"[ScheduleDB] Recreate failed: {e}")

def init_db():
    """DB 무결성 검사 후, 손상 시 새로 생성하여 서버가 중단되지 않도록."""
    try:
        conn = _db()
        try:
            # 무결성 검사
            cur = conn.cursor()
            cur.execute("PRAGMA integrity_check;")
            row = cur.fetchone()
            ok = (row and str(row[0]).lower() == "ok")
            if not ok:
                print(f"[ScheduleDB] integrity_check failed: {row[0] if row else 'unknown'}")
                conn.close()
                _recreate_db_with_backup()
                return
            # 스키마/기본 레코드 보장
            _create_schema(conn)
        finally:
            try:
                conn.close()
            except Exception:
                pass
    except sqlite3.DatabaseError as e:
        print(f"[ScheduleDB] DatabaseError on open/init: {e}")
        _recreate_db_with_backup()
    except Exception as e:
        print(f"[ScheduleDB] Unexpected error on init: {e}")
        _recreate_db_with_backup()

def row_to_schedule(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "enabled": bool(row["enabled"]),
        "power": row["power"],
        "mode": row["mode"],
        "temp": row["temp"],
        "schedule_type": row["schedule_type"],
        "date": row["date"],
        "weekday": row["weekday"],
        "start_time_min": row["start_time_min"],
        "end_time_min": row["end_time_min"],
        "summary": make_schedule_summary(
            row["schedule_type"], row["date"], row["weekday"], row["start_time_min"], row["end_time_min"]
        ),
    }

def make_schedule_summary(schedule_type: str, date: str | None, weekday: int | None, start_min: int, end_min: int) -> str:
    def format_ampm(m: int) -> str:
        h = (m // 60) % 24
        mm = m % 60
        am = "오전" if h < 12 else "오후"
        hh12 = h if 1 <= h <= 12 else (12 if h in (0, 12) else h - 12)
        return f"{am} {hh12}:{mm:02d}"
    start_s = format_ampm(start_min)
    end_s = format_ampm(end_min)
    if schedule_type == "once":
        day = date or "----/--/--"
        return f"{day} {start_s} ~ {end_s}"
    elif schedule_type == "daily":
        return f"매일 {start_s} ~ {end_s}"
    elif schedule_type == "weekly":
        # 0=월 ... 6=일
        week_names = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]
        wname = week_names[weekday] if weekday is not None and 0 <= weekday <= 6 else "요일"
        return f"매주 {wname} {start_s} ~ {end_s}"
    return ""

@app.get("/schedules")
def list_schedules():
    try:
        conn = _db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT * FROM schedules ORDER BY id")
            rows = cur.fetchall()
            return [row_to_schedule(r) for r in rows]
        finally:
            conn.close()
    except sqlite3.DatabaseError as e:
        print(f"[ScheduleDB] list_schedules error: {e} -> recreating")
        init_db()
        try:
            conn = _db()
            try:
                cur = conn.cursor()
                cur.execute("SELECT * FROM schedules ORDER BY id")
                rows = cur.fetchall()
                return [row_to_schedule(r) for r in rows]
            finally:
                conn.close()
        except Exception:
            return []

class ScheduleUpdate(BaseModel):
    enabled: bool | None = None
    power: str | None = None
    mode: str | None = None
    temp: int | None = None
    schedule_type: str | None = None
    date: str | None = None
    weekday: int | None = None
    start_time_min: int | None = None
    end_time_min: int | None = None

@app.put("/schedules/{sid}")
def update_schedule(sid: int, payload: ScheduleUpdate):
    if sid < 1 or sid > 7:
        raise HTTPException(status_code=400, detail="sid must be 1..7")
    # 유효성 간단 체크
    if payload.power and payload.power not in ("on", "off"):
        raise HTTPException(status_code=400, detail="invalid power")
    if payload.mode and payload.mode not in ("cool", "hot"):
        raise HTTPException(status_code=400, detail="invalid mode")
    if payload.schedule_type and payload.schedule_type not in ("once", "daily", "weekly"):
        raise HTTPException(status_code=400, detail="invalid schedule_type")
    if payload.start_time_min is not None and not (0 <= payload.start_time_min <= 1439):
        raise HTTPException(status_code=400, detail="invalid start_time_min")
    if payload.end_time_min is not None and not (0 <= payload.end_time_min <= 1439):
        raise HTTPException(status_code=400, detail="invalid end_time_min")
    if payload.weekday is not None and not (0 <= payload.weekday <= 6):
        raise HTTPException(status_code=400, detail="invalid weekday")
    def _do_update():
        conn = _db()
        try:
            cur = conn.cursor()
            cur.execute("INSERT OR IGNORE INTO schedules(id) VALUES (?)", (sid,))
            fields = []
            values = []
            for k, v in payload.dict(exclude_unset=True).items():
                if k == "enabled":
                    fields.append("enabled=?")
                    values.append(1 if v else 0)
                else:
                    fields.append(f"{k}=?")
                    values.append(v)
            if fields:
                values.append(sid)
                cur.execute(f"UPDATE schedules SET {', '.join(fields)} WHERE id=?", values)
                conn.commit()
            cur.execute("SELECT * FROM schedules WHERE id=?", (sid,))
            row = cur.fetchone()
            return row_to_schedule(row)
        finally:
            conn.close()
    try:
        return _do_update()
    except sqlite3.DatabaseError as e:
        print(f"[ScheduleDB] update_schedule error: {e} -> recreating")
        init_db()
        try:
            return _do_update()
        except Exception as e2:
            raise HTTPException(status_code=500, detail=f"DB error after recreate: {e2}")

def get_enabled_schedules() -> list[dict]:
    try:
        conn = _db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT * FROM schedules WHERE enabled=1 ORDER BY id")
            rows = cur.fetchall()
            return [row_to_schedule(r) for r in rows]
        finally:
            conn.close()
    except sqlite3.DatabaseError as e:
        print(f"[ScheduleDB] get_enabled_schedules error: {e} -> recreating")
        init_db()
        # 복구 후 빈 목록 반환 (스케줄 없어도 서버는 계속)
        return []

def minutes_since_midnight(dt: datetime) -> int:
    return dt.hour * 60 + dt.minute

def _within_5min_window(now_min: int, target_min: int) -> bool:
    # 순환 1440 고려
    diff = (now_min - target_min) % 1440
    return 0 <= diff <= 4

# 최근 전송(분) 기록: {(sid, 'on'|'off'): last_minute}
schedule_last_sent: dict[tuple[int, str], int] = {}

def _schedule_send_on(mode: str, temp: int):
    # 예약 시작은 항상 ON + (mode,temp)만 전송
    all_on(AcCommand(power="on", mode=mode, temp=temp))

def _schedule_send_off():
    all_off()

def _schedule_loop():
    print("[Schedule] Started (every 1 minute)")
    while True:
        try:
            now = datetime.now()
            now_min = minutes_since_midnight(now)
            weekday = (now.weekday())  # 월=0 .. 일=6
            today_str = now.strftime("%Y-%m-%d")

            schedules = get_enabled_schedules()
            for sch in schedules:
                sid = sch["id"]
                st = sch["schedule_type"]
                s_min = sch["start_time_min"]
                e_min = sch["end_time_min"]
                do_on = False
                do_off = False

                if st == "daily":
                    if _within_5min_window(now_min, s_min):
                        do_on = True
                    if _within_5min_window(now_min, e_min):
                        do_off = True
                elif st == "weekly":
                    if sch["weekday"] is not None and sch["weekday"] == weekday:
                        if _within_5min_window(now_min, s_min):
                            do_on = True
                        if _within_5min_window(now_min, e_min):
                            do_off = True
                elif st == "once":
                    if sch["date"] == today_str:
                        if _within_5min_window(now_min, s_min):
                            do_on = True
                        if _within_5min_window(now_min, e_min):
                            do_off = True

                # 동일 분 중복 방지
                if do_on:
                    key = (sid, "on")
                    if schedule_last_sent.get(key) != now_min:
                        print(f"[Schedule] #{sid} ON dispatch (mode={sch['mode']} temp={sch['temp']})")
                        _schedule_send_on(sch["mode"], sch["temp"])
                        schedule_last_sent[key] = now_min

                if do_off:
                    key = (sid, "off")
                    if schedule_last_sent.get(key) != now_min:
                        print(f"[Schedule] #{sid} OFF dispatch")
                        _schedule_send_off()
                        schedule_last_sent[key] = now_min
                        # 1회 예약은 OFF 실행 후 비활성화
                        if st == "once":
                            try:
                                update_schedule(sid, ScheduleUpdate(enabled=False))
                                print(f"[Schedule] #{sid} once disabled after OFF")
                            except Exception as _e:
                                print(f"[Schedule] #{sid} disable failed: {_e}")
        except Exception as e:
            print(f"[Schedule] Error: {e}")

        # 다음 분까지 대기 (초를 0으로 맞추는 간단한 로직)
        time_to_sleep = 60 - datetime.now().second
        if time_to_sleep <= 0:
            time_to_sleep = 60
        time.sleep(time_to_sleep)

def cleanup_devices():
    now = time.time()
    with devices_lock:
        expired = [k for k, v in devices.items() if now - v["last_seen"] > DEVICE_TIMEOUT_SEC]
        for k in expired:
            devices.pop(k, None)


def get_device(device_id: str) -> Dict[str, Any]:
    cleanup_devices()
    with devices_lock:
        dev = devices.get(device_id)
    if not dev:
        raise HTTPException(status_code=404, detail=f"Device {device_id} not found")
    return dev


def send_ac_command(dev: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
    """GET 요청으로 명령 전달 (500ms 간격으로 7번 연속 전송)"""
    try:
        url = f"http://{dev['ip']}:{dev['port']}{HTTP_PATH_SET}"
        results = []
        
        # 500ms 간격으로 7번 연속 전송
        for i in range(7):
            try:
                resp = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
                results.append({
                    "ok": resp.ok,
                    "status_code": resp.status_code,
                    "attempt": i + 1
                })
            except Exception as e:
                results.append({
                    "ok": False,
                    "error": str(e),
                    "attempt": i + 1
                })
            
            # 마지막 시도가 아니면 500ms 대기
            if i < 6:
                time.sleep(0.5)
        
        # 마지막 결과 반환
        last_result = results[-1] if results else {"ok": False, "error": "No attempts made"}
        return {
            "ok": last_result.get("ok", False),
            "status_code": last_result.get("status_code", 0),
            "body": last_result.get("body", ""),
            "attempts": len(results),
            "all_results": results
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}


def get_device_health(dev: Dict[str, Any]) -> Dict[str, Any]:
    """장치 health check"""
    try:
        url = f"http://{dev['ip']}:{dev['port']}/health"
        resp = requests.get(url, timeout=HTTP_TIMEOUT)
        return {"ok": resp.ok, "status_code": resp.status_code}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def get_device_state(dev: Dict[str, Any]) -> Dict[str, Any]:
    """장치 상태 조회"""
    try:
        url = f"http://{dev['ip']}:{dev['port']}/ac/state"
        resp = requests.get(url, timeout=HTTP_TIMEOUT)
        if resp.ok:
            return {"ok": True, "state": resp.json()}
        return {"ok": False, "status_code": resp.status_code}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ========================
# 서버 시계 동기화
# ========================
def _run_cmd(cmd: list[str], timeout_sec: float = 15.0) -> Dict[str, Any]:
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_sec,
            check=False,
            text=True,
        )
        return {
            "cmd": cmd,
            "returncode": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "ok": proc.returncode == 0,
        }
    except Exception as e:
        return {"cmd": cmd, "ok": False, "error": str(e)}


def sync_system_time(ntp_server: str | None = None) -> Dict[str, Any]:
    """시스템 시간을 NTP 서버와 동기화 시도 (권한 필요할 수 있음)"""
    target = ntp_server or NTP_SERVER
    steps: list[Dict[str, Any]] = []

    # 사용자 커스텀 명령이 지정된 경우 우선 사용
    if TIME_SYNC_COMMAND:
        steps.append(_run_cmd(["/bin/sh", "-lc", TIME_SYNC_COMMAND]))
        ok = any(s.get("ok") for s in steps)
        return {"ok": ok, "server": target, "steps": steps, "note": "TIME_SYNC_COMMAND 사용"}

    system_name = platform.system()

    if system_name == "Darwin":
        # macOS: sntp -sS <server> (권한 필요)
        if shutil.which("sntp"):
            steps.append(_run_cmd(["sntp", "-sS", target]))
        else:
            steps.append({"ok": False, "error": "sntp 명령을 찾을 수 없습니다"})
        # 참고용: 네트워크 시간 활성화 시도 (대부분 관리자 권한 필요)
        if shutil.which("systemsetup"):
            steps.append(_run_cmd(["/usr/sbin/systemsetup", "-setnetworktimeserver", target]))
            steps.append(_run_cmd(["/usr/sbin/systemsetup", "-setusingnetworktime", "on"]))

    else:
        # Linux 등: chronyc / timedatectl / ntpdate 순 시도
        if shutil.which("chronyc"):
            steps.append(_run_cmd(["chronyc", "-a", "makestep"]))
        elif shutil.which("timedatectl"):
            steps.append(_run_cmd(["timedatectl", "set-ntp", "true"]))
            # systemd-timesyncd 재시작 시도 (있을 때만)
            if shutil.which("systemctl"):
                steps.append(_run_cmd(["systemctl", "restart", "systemd-timesyncd"]))
        elif shutil.which("ntpdate"):
            steps.append(_run_cmd(["ntpdate", "-u", target]))
        else:
            steps.append({"ok": False, "error": "chronyc/timedatectl/ntpdate 명령을 찾을 수 없습니다"})

    ok = any(s.get("ok") for s in steps)
    return {
        "ok": ok,
        "server": target,
        "steps": steps,
        "hint": "권한 필요 시 관리자 권한 또는 sudoers NOPASSWD 설정이 필요할 수 있습니다.",
    }


def _time_sync_loop():
    if not TIME_SYNC_ENABLED:
        print("[TimeSync] Disabled by TIME_SYNC_ENABLED=0")
        return
    print(f"[TimeSync] Enabled: interval={TIME_SYNC_INTERVAL_SEC}s server={NTP_SERVER}")
    while True:
        try:
            result = sync_system_time(NTP_SERVER)
            status = "ok" if result.get("ok") else "fail"
            print(f"[TimeSync] Sync {status}: {result.get('server')}")
            if not result.get("ok"):
                print(f"[TimeSync] Details: {result.get('steps')}")
        except Exception as e:
            print(f"[TimeSync] Error: {e}")
        # 다음 주기까지 대기
        time.sleep(TIME_SYNC_INTERVAL_SEC)


@app.get("/devices")
def list_devices():
    cleanup_devices()
    with devices_lock:
        return list(devices.values())


@app.get("/devices/{device_id}/health")
def get_health(device_id: str):
    dev = get_device(device_id)
    result = get_device_health(dev)
    return {"device": dev["id"], "health": result}


@app.get("/devices/{device_id}/ac/state")
def get_state(device_id: str):
    dev = get_device(device_id)
    result = get_device_state(dev)
    return {"device": dev["id"], **result}


@app.get("/devices/status")
def get_all_status():
    """모든 장치의 상태를 한번에 조회"""
    cleanup_devices()
    with devices_lock:
        devs = list(devices.values())
    
    status_list = []
    for dev in devs:
        health = get_device_health(dev)
        state_result = get_device_state(dev)
        
        status = {
            "id": dev["id"],
            "ip": dev["ip"],
            "port": dev["port"],
            "health": health,
            "state": state_result.get("state") if state_result.get("ok") else None,
        }
        status_list.append(status)
    return status_list


@app.post("/time/sync")
def time_sync_now():
    """수동 시계 동기화 트리거"""
    result = sync_system_time(NTP_SERVER)
    if not result.get("ok"):
        # 권한 문제 등으로 실패해도 200으로 결과 반환하여 클라이언트가 메시지를 볼 수 있게 함
        return {"ok": False, "result": result}
    return {"ok": True, "result": result}

@app.route("/webhook", methods=["POST"])
def webhook():
    try:
        # 비차단 방식으로 배포 스크립트 실행 (실행 권한 불필요)
        subprocess.Popen(
            ["/bin/bash", "./deploy.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return {"ok": True, "message": "Deployment started"}, 202
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/devices/{device_id}/ac/set")
def set_ac(device_id: str, cmd: AcCommand):
    dev = get_device(device_id)
    params = {k: v for k, v in cmd.dict().items() if v is not None}
    if not params:
        raise HTTPException(status_code=400, detail="No parameters given")
    result = send_ac_command(dev, params)
    return {"device": dev["id"], "ip": dev["ip"], "params": params, "result": result}

@app.post("/devices/batch/ac/set")
def set_ac_batch(payload: BatchAcCommand):
    # 유효성 검사
    ids = [i for i in (payload.device_ids or []) if i]
    # 중복 제거(순서 유지)
    seen = set()
    unique_ids: list[str] = []
    for i in ids:
        if i not in seen:
            seen.add(i)
            unique_ids.append(i)
    params = {k: v for k, v in payload.command.dict().items() if v is not None}
    if not unique_ids:
        raise HTTPException(status_code=400, detail="No device_ids given")
    if not params:
        raise HTTPException(status_code=400, detail="No parameters given")

    cleanup_devices()
    with devices_lock:
        dev_map = dict(devices)

    # 대상 장치 분류
    target_devs: list[Dict[str, Any]] = []
    missing: list[str] = []
    for dev_id in unique_ids:
        dev = dev_map.get(dev_id)
        if dev:
            target_devs.append(dev)
        else:
            missing.append(dev_id)

    results: Dict[str, Dict[str, Any]] = {}
    if not target_devs:
        return {"command": params, "results": results, "missing": missing, "requested_ids": unique_ids}

    max_workers = min(16, max(1, len(target_devs)))
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        future_to_id: Dict[concurrent.futures.Future, str] = {}
        for dev in target_devs:
            fut = executor.submit(send_ac_command, dev, params)
            future_to_id[fut] = dev["id"]

        done, not_done = concurrent.futures.wait(
            list(future_to_id.keys()),
            timeout=ALL_CMD_PER_DEVICE_TIMEOUT_SEC,
            return_when=concurrent.futures.ALL_COMPLETED
        )

        for fut in list(done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            try:
                results[dev_id] = fut.result()
            except Exception as e:
                results[dev_id] = {"ok": False, "error": str(e)}

        for fut in list(not_done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            fut.cancel()
            results[dev_id] = {"ok": False, "error": "timeout", "timeout_sec": ALL_CMD_PER_DEVICE_TIMEOUT_SEC}
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    return {"command": params, "results": results, "missing": missing, "requested_ids": unique_ids}


@app.post("/all/on")
def all_on(cmd: AcCommand | None = None):
    base = {"power": "on", "mode": "cool", "temp": 24}
    if cmd:
        for k, v in cmd.dict().items():
            if v is not None:
                base[k] = v
    cleanup_devices()
    with devices_lock:
        devs = list(devices.values())

    # 장치별 명령을 병렬 전송 (쓰레드) + per-device 타임아웃
    results: Dict[str, Dict[str, Any]] = {}
    if not devs:
        return {"command": base, "results": results}

    max_workers = min(16, max(1, len(devs)))
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        future_to_id: Dict[concurrent.futures.Future, str] = {}
        for dev in devs:
            fut = executor.submit(send_ac_command, dev, base)
            future_to_id[fut] = dev["id"]

        # 지정된 타임아웃 동안 완료된 작업만 수집
        done, not_done = concurrent.futures.wait(
            list(future_to_id.keys()),
            timeout=ALL_CMD_PER_DEVICE_TIMEOUT_SEC,
            return_when=concurrent.futures.ALL_COMPLETED
        )

        # 이미 끝난 작업은 결과 수집
        for fut in list(done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            try:
                results[dev_id] = fut.result()
            except Exception as e:
                results[dev_id] = {"ok": False, "error": str(e)}

        # 타임아웃된 작업은 timeout으로 표기
        # 추가로 취소 시도 (이미 실행 중인 작업은 취소되지 않을 수 있음)
        for fut in list(not_done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            fut.cancel()
            results[dev_id] = {"ok": False, "error": "timeout", "timeout_sec": ALL_CMD_PER_DEVICE_TIMEOUT_SEC}
    finally:
        # 대기하지 않고 종료, 실행 중인 작업은 가능한 한 취소 시도
        executor.shutdown(wait=False, cancel_futures=True)

    return {"command": base, "results": results}


@app.post("/all/off")
def all_off():
    # power=off만 전송하여 각 모듈의 기존 모드/온도 값은 유지
    params = {"power": "off"}
    cleanup_devices()
    with devices_lock:
        devs = list(devices.values())

    results: Dict[str, Dict[str, Any]] = {}
    if not devs:
        return {"command": params, "results": results}

    max_workers = min(16, max(1, len(devs)))
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        future_to_id: Dict[concurrent.futures.Future, str] = {}
        for dev in devs:
            fut = executor.submit(send_ac_command, dev, params)
            future_to_id[fut] = dev["id"]

        done, not_done = concurrent.futures.wait(
            list(future_to_id.keys()),
            timeout=ALL_CMD_PER_DEVICE_TIMEOUT_SEC,
            return_when=concurrent.futures.ALL_COMPLETED
        )

        for fut in list(done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            try:
                results[dev_id] = fut.result()
            except Exception as e:
                results[dev_id] = {"ok": False, "error": str(e)}

        for fut in list(not_done):
            dev_id = future_to_id.get(fut)
            if dev_id is None:
                continue
            fut.cancel()
            results[dev_id] = {"ok": False, "error": "timeout", "timeout_sec": ALL_CMD_PER_DEVICE_TIMEOUT_SEC}
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    return {"command": params, "results": results}


# 정적 파일 서빙 (모든 API 엔드포인트 이후에 마운트)
web_dir = os.path.join(os.path.dirname(__file__), "web")

# 정적 파일 (CSS, JS 등) 서빙 - 특정 파일명만 허용 (API 경로보다 먼저 체크)
static_files = ["style.css", "api.js", "app.js"]

@app.get("/style.css")
async def serve_css():
    """CSS 파일 서빙"""
    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, "style.css")
        if os.path.exists(file_path):
            return FileResponse(
                file_path,
                media_type="text/css",
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
            )
    raise HTTPException(status_code=404, detail="File not found")

@app.get("/api.js")
async def serve_api_js():
    """api.js 파일 서빙"""
    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, "api.js")
        if os.path.exists(file_path):
            return FileResponse(
                file_path,
                media_type="application/javascript",
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
            )
    raise HTTPException(status_code=404, detail="File not found")

@app.get("/app.js")
async def serve_app_js():
    """app.js 파일 서빙"""
    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, "app.js")
        if os.path.exists(file_path):
            return FileResponse(
                file_path,
                media_type="application/javascript",
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
            )
    raise HTTPException(status_code=404, detail="File not found")

@app.get("/", response_class=HTMLResponse)
async def read_root():
    """루트 경로에서 index.html 서빙"""
    if os.path.exists(web_dir):
        index_path = os.path.join(web_dir, "index.html")
        if os.path.exists(index_path):
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()
                return HTMLResponse(
                    content=content,
                    headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
                )
    return HTMLResponse(
        content="<html><body><h1>Web interface not found</h1></body></html>",
        headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
    )


# mDNS 서비스 등록
zeroconf = None
service_info = None

def get_local_ips():
    """로컬 네트워크 IP 주소 목록 가져오기"""
    ips = []
    
    # 방법 1: 외부 연결을 통한 IP 감지 (가장 정확)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and ip != "127.0.0.1":
            ips.append(ip)
    except:
        pass
    
    # 방법 2: 호스트 이름으로 IP 가져오기
    try:
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
        if ip and ip != "127.0.0.1" and ip not in ips:
            ips.append(ip)
    except:
        pass
    
    # 방법 3: socket.getaddrinfo 사용
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if ip and ip != "127.0.0.1" and ip not in ips:
                # 사설 IP만 추가 (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
                parts = ip.split('.')
                if (parts[0] == '192' and parts[1] == '168') or \
                   parts[0] == '10' or \
                   (parts[0] == '172' and 16 <= int(parts[1]) <= 31):
                    ips.append(ip)
    except:
        pass
    
    return ips if ips else ["127.0.0.1"]

def register_mdns():
    """mDNS 서비스 등록"""
    global zeroconf, service_info
    
    if not ZEROCONF_AVAILABLE:
        print("[mDNS] ✗ zeroconf 패키지가 설치되지 않았습니다.")
        print("[mDNS]    설치: pip install zeroconf")
        print("[mDNS]    또는: install-dependencies.bat 실행")
        return False
    
    try:
        # 모든 로컬 IP 주소 가져오기
        local_ips = get_local_ips()
        primary_ip = local_ips[0] if local_ips else "127.0.0.1"
        
        print(f"[mDNS] 감지된 IP 주소: {', '.join(local_ips)}")
        
        # IPv4 주소를 바이트로 변환
        ip_addresses = []
        for ip in local_ips:
            try:
                ip_bytes = socket.inet_aton(ip)
                ip_addresses.append(ip_bytes)
            except:
                pass
        
        if not ip_addresses:
            print("[mDNS] ✗ 유효한 IP 주소를 찾을 수 없습니다.")
            return False
        
        # Zeroconf 객체 생성
        zeroconf = Zeroconf()
        
        # 서비스 정보 생성
        service_info = ServiceInfo(
            MDNS_SERVICE_TYPE,
            f"{MDNS_HOSTNAME}.{MDNS_SERVICE_TYPE}",
            addresses=ip_addresses,
            port=SERVER_PORT,
            properties={"path": "/"},
            server=f"{MDNS_HOSTNAME}.local.",
        )
        
        # 서비스 등록 시도
        try:
            zeroconf.register_service(service_info)
            # Windows에서 mDNS가 제대로 동작하는지 확인하기 위해 약간 대기
            time.sleep(0.5)
            
            print(f"[mDNS] ✓ Service registered successfully")
            print(f"[mDNS]   http://{MDNS_HOSTNAME}.local:{SERVER_PORT}/")
            print(f"[mDNS]   http://{primary_ip}:{SERVER_PORT}/")
            print(f"[mDNS]")
            print(f"[mDNS]   ⚠ Windows에서 mDNS(.local) 접속이 안 될 수 있습니다.")
            print(f"[mDNS]   이 경우 IP 주소로 직접 접속하세요: http://{primary_ip}:{SERVER_PORT}/")
            print(f"[mDNS]   또는 hosts 파일에 추가: {primary_ip}  {MDNS_HOSTNAME}.local")
            return True
        except NonUniqueNameException:
            # 같은 이름의 서비스가 이미 등록된 경우
            print(f"[mDNS] ⚠ Service name already exists, attempting to unregister and re-register...")
            try:
                # 이전 서비스 해제 시도
                zeroconf.unregister_service(service_info)
                time.sleep(0.5)
                # 다시 등록
                zeroconf.register_service(service_info)
                time.sleep(0.5)
                print(f"[mDNS] ✓ Service re-registered successfully")
                print(f"[mDNS]   http://{MDNS_HOSTNAME}.local:{SERVER_PORT}/")
                print(f"[mDNS]   http://{primary_ip}:{SERVER_PORT}/")
                return True
            except Exception as e2:
                print(f"[mDNS] ⚠ Could not re-register service: {e2}")
                print(f"[mDNS]   서버는 정상 작동하지만 mDNS를 통한 자동 발견이 안 될 수 있습니다.")
                print(f"[mDNS]   IP 주소로 직접 접속하세요: http://{primary_ip}:{SERVER_PORT}/")
                return False
        
    except Exception as e:
        print(f"[mDNS] ✗ Failed to register service: {e}")
        # traceback은 너무 길어서 간단한 메시지만 출력
        primary_ip = get_local_ips()[0] if get_local_ips() else "localhost"
        print(f"[mDNS]   서버는 정상 작동하지만 mDNS를 통한 자동 발견이 안 될 수 있습니다.")
        print(f"[mDNS]   IP 주소로 직접 접속하세요: http://{primary_ip}:{SERVER_PORT}/")
        return False

def unregister_mdns():
    """mDNS 서비스 해제"""
    global zeroconf, service_info
    
    if zeroconf and service_info:
        try:
            zeroconf.unregister_service(service_info)
            zeroconf.close()
            print("[mDNS] Service unregistered")
        except Exception as e:
            print(f"[mDNS] Failed to unregister service: {e}")

if __name__ == "__main__":
    try:
        print(f"[HTTP] Server starting on {SERVER_HOST}:{SERVER_PORT}")
        print(f"[HTTP] Web interface: http://localhost:{SERVER_PORT}/")
        print(f"[UDP] Listening on port {UDP_LISTEN_PORT}")
        # 스케줄 DB 초기화
        init_db()
        # 시계 동기화 루프 시작
        threading.Thread(target=_time_sync_loop, daemon=True).start()
        # 예약 스케줄 루프 시작
        threading.Thread(target=_schedule_loop, daemon=True).start()
        
        # mDNS 서비스 등록
        mdns_success = register_mdns()
        if not mdns_success:
            print("[mDNS] mDNS 등록에 실패했지만 서버는 계속 실행됩니다.")
        
        # 추가 접근 안내: 로컬 IP 및 mDNS 주소 출력
        try:
            local_ips = get_local_ips()
            primary_ip = local_ips[0] if local_ips else "127.0.0.1"
            print("[Access] 다음 주소로 접속 가능합니다:")
            print(f"[Access]   http://{primary_ip}:{SERVER_PORT}/")
            print(f"[Access]   http://{MDNS_HOSTNAME}.local:{SERVER_PORT}/ (mDNS)")
        except Exception as _:
            pass
        
        print("Press Ctrl+C to stop the server")
        
        try:
            uvicorn.run(app, host=SERVER_HOST, port=SERVER_PORT, log_level="info")
        except KeyboardInterrupt:
            print("\n[HTTP] Server stopping...")
        finally:
            unregister_mdns()
            
    except Exception as e:
        print(f"[ERROR] Failed to start server: {e}")
        import traceback
        traceback.print_exc()
        unregister_mdns()
        sys.exit(1)
