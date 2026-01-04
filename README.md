# 에어컨 제어 시스템

## 설치 및 실행

### 1. Python 설치 (필수)

Python이 설치되어 있지 않은 경우:

1. [Python 공식 사이트](https://www.python.org/downloads/)에서 다운로드
2. 설치 시 **"Add Python to PATH"** 옵션을 **반드시 체크**하세요
3. 설치 완료 후 명령 프롬프트를 다시 시작하세요

### 2. 초기 설정 (권장)

가상환경을 생성하고 필요한 패키지를 설치합니다:

```bash
setup.bat
```

또는 단계별로:

```bash
# 가상환경 생성 및 패키지 설치
install-dependencies.bat
```

### 3. 서버 실행

```bash
start-server.bat
```

서버는 자동으로 가상환경을 활성화하고 실행됩니다.

### 가상환경 수동 사용

가상환경을 수동으로 활성화하려면:

```bash
venv\Scripts\activate.bat
```

비활성화하려면:

```bash
deactivate
```

### 4. 웹 브라우저에서 접속

- http://localhost:8000
- http://aircon-controller.local:8000 (mDNS 사용 시)

### 5. Windows 자동 시작 설정 (선택)

부팅할 때 자동으로 서버를 구동하려면 **관리자 권한** PowerShell(또는 명령 프롬프트)에서 아래 스크립트를 실행하세요.

```powershell
cd C:\Users\k\Documents\wifi-remocon
.\register-autostart.bat
```

- Windows 작업 스케줄러에 `WifiRemoconControlServer` 작업이 생성되며, 부팅 후 30초 뒤 `start-server.bat`을 SYSTEM 권한으로 실행합니다.
- 자동 시작을 해제하려면:

```powershell
cd C:\Users\k\Documents\wifi-remocon
.\unregister-autostart.bat
```

작업 상태 확인: `schtasks /Query /TN WifiRemoconControlServer`

## 문제 해결

### Python을 찾을 수 없는 경우

1. Python이 설치되어 있는지 확인: `python --version`
2. Python이 설치되어 있지만 PATH에 없는 경우:
   - `install-dependencies.bat` 또는 `start-server.bat` 실행 시
   - Python 실행 파일 경로를 직접 입력하라는 메시지가 나타납니다
   - 예: `C:\Python39\python.exe` 또는 `C:\Users\사용자명\AppData\Local\Programs\Python\Python39\python.exe`

### 서버가 실행되지 않는 경우

1. 필요한 패키지가 설치되어 있는지 확인: `pip list | findstr fastapi`
2. 포트 8000이 사용 중인지 확인: `netstat -ano | findstr :8000`
3. `start-server.bat`을 실행하여 오류 메시지 확인

### 브라우저에서 접근이 안되는 경우

1. 서버가 실행 중인지 확인
2. 방화벽 설정 확인
3. `http://127.0.0.1:8000`으로 접속 시도
4. 다른 브라우저로 시도

## API 엔드포인트

### 공통
- **Base URL**: `http://localhost:8000`
- **Content-Type**: `application/json`

### 요청 바디 스키마: AcCommand
- **power**: `"on"` | `"off"` (예: `"on"`)
- **mode**: 냉방/난방/제습/송풍/자동 등 장치가 이해하는 문자열 (예: `"cool"`)
- **temp**: 정수 온도 (예: `24`)
- **fan**: 풍량 (예: `"low"`, `"mid"`, `"high"`)
- **swing**: 풍향 (예: `"on"`, `"off"` 등)

필드는 모두 선택이며, 전달된 필드만 장치에 반영됩니다.

---

### GET /devices
- **설명**: 현재 발견된 장치 목록 조회
- **응답 예시**
```json
[
  {
    "id": "ac-01",
    "ip": "192.168.0.12",
    "port": 80,
    "last_seen": 1733980000.123
  }
]
```

### GET /devices/{device_id}/health
- **설명**: 특정 장치 Health 체크
- **응답 예시**
```json
{
  "device": "ac-01",
  "health": { "ok": true, "status_code": 200 }
}
```

### GET /devices/{device_id}/ac/state
- **설명**: 특정 장치의 현재 상태 조회
- **응답 예시**
```json
{
  "device": "ac-01",
  "ok": true,
  "state": {
    "power": "on",
    "mode": "cool",
    "temp": 24,
    "fan": "mid",
    "swing": "off"
  }
}
```

### GET /devices/status
- **설명**: 모든 장치의 상태를 한 번에 조회
- **응답 예시**
```json
[
  {
    "id": "ac-01",
    "ip": "192.168.0.12",
    "port": 80,
    "health": { "ok": true, "status_code": 200 },
    "state": {
      "power": "on",
      "mode": "cool",
      "temp": 24,
      "fan": "mid",
      "swing": "off"
    }
  }
]
```

### POST /devices/{device_id}/ac/set
- **설명**: 특정 장치 제어
- **바디**: `AcCommand`
- **응답 예시**
```json
{
  "device": "ac-01",
  "ip": "192.168.0.12",
  "params": { "power": "on", "mode": "cool", "temp": 24 },
  "result": {
    "ok": true,
    "status_code": 200,
    "attempts": 7,
    "all_results": [
      { "ok": true, "status_code": 200, "attempt": 1 }
      // ... 반복 전송 결과
    ]
  }
}
```

### POST /devices/control
- **설명**: 여러 장치를 한 번에 제어. 서버에서 병렬 처리 후 장치별 결과와 요약을 반환
- **바디**
```json
{
  "device_ids": ["ac-01", "ac-02"],
  "command": { "power": "on", "mode": "hot", "temp": 30 }
}
```
- **응답 예시**
```json
{
  "command": { "power": "on", "mode": "hot", "temp": 30 },
  "requested_ids": ["ac-01", "ac-02"],
  "target_ids": ["ac-01"],
  "missing": ["ac-02"],
  "summary": {
    "requested": 2,
    "attempted": 1,
    "succeeded": 1,
    "failed": 0,
    "missing": 1
  },
  "results": {
    "ac-01": { "ok": true, "status_code": 200, "attempts": 7, "all_results": [/* ... */] }
  }
}
```

### POST /all/on
- **설명**: 모든 장치를 켬. 기본값은 `{"power":"on","mode":"cool","temp":24}` 이며, 바디로 전달한 필드로 덮어쓸 수 있음
- **바디(선택)**: `AcCommand`
- **응답**: 각 장치별 결과 맵
```json
{
  "command": { "power": "on", "mode": "cool", "temp": 24 },
  "results": {
    "ac-01": { "ok": true, "status_code": 200, "attempts": 7, "all_results": [/*...*/] }
  }
}
```

### POST /all/off
- **설명**: 모든 장치를 끔
- **바디**: 없음
- **응답**: `/all/on`과 동일 형태로 각 장치별 결과 반환

### POST /webhook
- **설명**: 배포 스크립트(`deploy.sh`) 실행 트리거. 비동기로 실행되며, 서버는 즉시 응답.
- **응답 예시**
```json
{ "ok": true, "message": "Deployment started" }
```

---

### cURL 예시
```bash
# 장치 목록
curl -s http://localhost:8000/devices

# 특정 장치 상태
curl -s http://localhost:8000/devices/ac-01/ac/state

# 특정 장치 제어 (켜기)
curl -s -X POST http://localhost:8000/devices/ac-01/ac/set \
  -H "Content-Type: application/json" \
  -d '{"power":"on","mode":"cool","temp":24}'

# 모두 끄기
curl -s -X POST http://localhost:8000/all/off
```
