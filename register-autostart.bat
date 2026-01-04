@echo off
chcp 65001 >nul
setlocal enableextensions

set TASK_NAME=WifiRemoconControlServer
set SCRIPT_DIR=%~dp0
set TARGET_SCRIPT=%SCRIPT_DIR%start-server.bat

echo ========================================
echo 에어컨 제어 서버 자동 시작 등록
echo ========================================
echo.
echo ※ 관리자 권한 PowerShell/명령 프롬프트에서 실행해야 합니다.
echo.

if not exist "%TARGET_SCRIPT%" (
    echo [오류] start-server.bat을 찾을 수 없습니다.
    echo 위치: %TARGET_SCRIPT%
    exit /b 1
)

REM 기존 작업이 있으면 삭제
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo 기존 작업을 삭제합니다...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul
) else (
    set TARGET_SCRIPT="%TARGET_SCRIPT%"
)

echo 작업을 생성합니다...
schtasks /Create ^
    /TN "%TASK_NAME%" ^
    /SC ONSTART ^
    /RL HIGHEST ^
    /DELAY 0000:30 ^
    /RU SYSTEM ^
    /TR "\"%TARGET_SCRIPT%\"" ^
    /F

if errorlevel 1 (
    echo.
    echo [오류] 작업 생성에 실패했습니다.
    exit /b 1
)

echo.
echo [완료] Windows 부팅 시 제어 서버가 자동으로 시작됩니다.
echo 작업 이름: %TASK_NAME%
echo 지연 시간: 부팅 후 30초
echo.
echo 작업 상태 확인: schtasks /Query /TN "%TASK_NAME%"
echo 작업 제거: unregister-autostart.bat
echo.
exit /b 0


