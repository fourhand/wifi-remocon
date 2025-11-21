@echo off
chcp 65001 >nul
echo ========================================
echo 필요한 패키지 설치
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
echo Python을 찾았습니다!
%PYTHON_CMD% --version
echo 사용할 명령어: %PYTHON_CMD%
echo.

REM 가상환경 생성
echo 가상환경을 생성합니다...
if exist "venv" (
    echo venv 폴더가 이미 존재합니다. 기존 가상환경을 사용합니다.
) else (
    %PYTHON_CMD% -m venv venv
    if errorlevel 1 (
        echo [오류] 가상환경 생성에 실패했습니다.
        pause
        exit /b 1
    )
    echo 가상환경이 생성되었습니다.
)
echo.

REM 가상환경 활성화
echo 가상환경을 활성화합니다...
call venv\Scripts\activate.bat
if errorlevel 1 (
    echo [오류] 가상환경 활성화에 실패했습니다.
    pause
    exit /b 1
)
echo.

REM pip 업그레이드
echo pip를 최신 버전으로 업그레이드합니다...
python -m pip install --upgrade pip
echo.

echo 필요한 패키지를 설치합니다...
echo.

python -m pip install fastapi uvicorn requests zeroconf

if errorlevel 1 (
    echo.
    echo [오류] 패키지 설치 중 오류가 발생했습니다.
    pause
    exit /b 1
)

echo.
echo ========================================
echo 패키지 설치 완료!
echo ========================================
echo.
echo 가상환경이 준비되었습니다.
echo 이제 start-server.bat을 실행하여 서버를 시작할 수 있습니다.
echo.
echo 참고: 가상환경을 수동으로 활성화하려면:
echo   venv\Scripts\activate.bat
echo.
pause

