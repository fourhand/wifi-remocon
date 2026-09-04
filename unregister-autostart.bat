@echo off
chcp 65001 >nul
setlocal enableextensions

set TASK_NAME=WifiRemoconControlServer
set STARTUP_LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WifiRemoconControlServer.lnk

echo ========================================
echo 에어컨 제어 서버 자동 시작 제거
echo ========================================
echo.

set REMOVED=0

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo 작업 스케줄러 작업을 삭제합니다...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    if %errorlevel%==0 set REMOVED=1
)

if exist "%STARTUP_LINK%" (
    echo 시작 프로그램 바로가기를 삭제합니다...
    del "%STARTUP_LINK%" >nul 2>&1
    if %errorlevel%==0 set REMOVED=1
)

if %REMOVED%==0 (
    echo [안내] 등록된 자동 시작 항목이 없습니다.
    exit /b 0
)

echo.
echo [완료] 자동 시작이 제거되었습니다.
echo.
exit /b 0
