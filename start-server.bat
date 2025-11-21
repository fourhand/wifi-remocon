@echo off
chcp 65001 >nul
echo ========================================
echo 에어컨 제어 서버 시작
echo ========================================
echo.

REM Python 경로 확인 (여러 방법 시도)
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 (
    set PYTHON_CMD=python
    goto :found_python
)

python3 --version >nul 2>&1
if not errorlevel 1 (
    set PYTHON_CMD=python3
    goto :found_python
)

py --version >nul 2>&1
if not errorlevel 1 (
    set PYTHON_CMD=py
    goto :found_python
)

REM WindowsApps 경로 확인 (Microsoft Store Python)
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe" (
    "%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe" --version >nul 2>&1
    if not errorlevel 1 (
        set PYTHON_CMD=%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe
        goto :found_python
    )
)

if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe" (
    "%LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe" --version >nul 2>&1
    if not errorlevel 1 (
        set PYTHON_CMD=%LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe
        goto :found_python
    )
)

REM 일반적인 Python 설치 경로 확인
if exist "C:\Python3*\python.exe" (
    for /f "delims=" %%i in ('dir /b /ad "C:\Python3*" 2^>nul') do (
        if exist "C:\%%i\python.exe" (
            "C:\%%i\python.exe" --version >nul 2>&1
            if not errorlevel 1 (
                set PYTHON_CMD=C:\%%i\python.exe
                goto :found_python
            )
        )
    )
)

if exist "%LOCALAPPDATA%\Programs\Python\Python3*\python.exe" (
    for /f "delims=" %%i in ('dir /b /ad "%LOCALAPPDATA%\Programs\Python\Python3*" 2^>nul') do (
        if exist "%LOCALAPPDATA%\Programs\Python\%%i\python.exe" (
            "%LOCALAPPDATA%\Programs\Python\%%i\python.exe" --version >nul 2>&1
            if not errorlevel 1 (
                set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\%%i\python.exe
                goto :found_python
            )
        )
    )
)

if exist "%ProgramFiles%\Python3*\python.exe" (
    for /f "delims=" %%i in ('dir /b /ad "%ProgramFiles%\Python3*" 2^>nul') do (
        if exist "%ProgramFiles%\%%i\python.exe" (
            "%ProgramFiles%\%%i\python.exe" --version >nul 2>&1
            if not errorlevel 1 (
                set PYTHON_CMD=%ProgramFiles%\%%i\python.exe
                goto :found_python
            )
        )
    )
)

echo [오류] Python이 설치되어 있지 않거나 PATH에 등록되어 있지 않습니다.
echo.
echo 다음 명령어들을 시도했습니다:
echo   - python
echo   - python3
echo   - py
echo   - WindowsApps 경로
echo   - 일반적인 설치 경로들
echo.
echo Python을 설치해주세요:
echo   1. https://www.python.org/downloads/ 에서 다운로드
echo   2. 설치 시 "Add Python to PATH" 옵션을 반드시 체크하세요
echo.
echo 또는 Python이 이미 설치되어 있다면, 설치 경로를 직접 입력해주세요:
echo.
set /p PYTHON_PATH="Python 실행 파일 경로 (예: C:\Python39\python.exe): "
if exist "%PYTHON_PATH%" (
    "%PYTHON_PATH%" --version >nul 2>&1
    if not errorlevel 1 (
        set PYTHON_CMD=%PYTHON_PATH%
        goto :found_python
    ) else (
        echo [오류] 지정한 경로의 Python이 작동하지 않습니다.
        pause
        exit /b 1
    )
) else (
    echo [오류] 지정한 경로가 존재하지 않습니다.
    pause
    exit /b 1
)

:found_python
echo Python 버전 확인 중...
%PYTHON_CMD% --version
echo 사용할 명령어: %PYTHON_CMD%
echo.

REM 현재 디렉토리로 이동
cd /d "%~dp0"

REM 가상환경 확인 및 활성화
if exist "venv\Scripts\activate.bat" (
    echo 가상환경을 활성화합니다...
    call venv\Scripts\activate.bat
    if errorlevel 1 (
        echo [경고] 가상환경 활성화에 실패했습니다. 시스템 Python을 사용합니다.
        set USE_VENV=0
    ) else (
        echo 가상환경이 활성화되었습니다.
        set USE_VENV=1
    )
    echo.
) else (
    echo [경고] venv 폴더를 찾을 수 없습니다.
    echo install-dependencies.bat을 먼저 실행하여 가상환경을 생성하세요.
    echo 시스템 Python을 사용합니다.
    echo.
    set USE_VENV=0
)

REM Python 명령어 결정
if "%USE_VENV%"=="1" (
    set PYTHON_EXEC=python
) else (
    set PYTHON_EXEC=%PYTHON_CMD%
)

echo 서버 시작 중...
echo 웹 인터페이스: http://localhost:8000
echo 종료하려면 Ctrl+C를 누르세요.
echo.

REM 오류 출력을 확인하기 위해 직접 실행
%PYTHON_EXEC% control-server.py 2>&1

if errorlevel 1 (
    echo.
    echo [오류] 서버 실행 중 오류가 발생했습니다.
    echo.
    echo 필요한 패키지가 설치되어 있는지 확인해주세요:
    echo   pip install fastapi uvicorn requests
    echo.
    echo 또는 install-dependencies.bat을 실행하세요.
    echo.
    pause
)

