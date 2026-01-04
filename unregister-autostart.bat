@echo off
chcp 65001 >nul
setlocal enableextensions

set TASK_NAME=WifiRemoconControlServer

echo ========================================
echo 에어컨 제어 서버 자동 시작 제거
echo ========================================
echo.
echo ※ 관리자 권한 PowerShell/명령 프롬프트에서 실행해야 합니다.
echo.

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [안내] 등록된 작업이 없습니다: %TASK_NAME%
    exit /b 0
)

echo 작업을 삭제합니다...
schtasks /Delete /TN "%TASK_NAME%" /F
if errorlevel 1 (
    echo [오류] 작업 삭제에 실패했습니다.
    exit /b 1
)

echo.
echo [완료] 자동 시작 작업이 제거되었습니다.
echo.
exit /b 0


