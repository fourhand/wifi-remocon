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

- `GET /devices` - 장치 목록 조회
- `GET /devices/status` - 모든 장치 상태 조회
- `GET /devices/{device_id}/ac/state` - 특정 장치 상태 조회
- `POST /devices/{device_id}/ac/set` - 특정 장치 제어
- `POST /all/on` - 모든 장치 켜기
- `POST /all/off` - 모든 장치 끄기
