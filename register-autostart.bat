@echo off
chcp 65001 >nul
setlocal enableextensions

set TASK_NAME=WifiRemoconControlServer
set SCRIPT_DIR=%~dp0
set STARTUP_LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WifiRemoconControlServer.lnk

echo ========================================
echo 에어컨 제어 서버 자동 시작 등록
echo ========================================
echo.
echo ※ 관리자 권한 PowerShell/명령 프롬프트에서 실행해야 합니다.
echo.

if not exist "%SCRIPT_DIR%start-server-autostart.bat" (
    echo [오류] start-server-autostart.bat을 찾을 수 없습니다.
    exit /b 1
)

if not exist "%SCRIPT_DIR%venv\Scripts\python.exe" (
    echo [오류] 가상환경이 없습니다. 먼저 setup.bat을 실행하세요.
    exit /b 1
)

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo 기존 작업을 삭제합니다...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul
)
if exist "%STARTUP_LINK%" del "%STARTUP_LINK%" >nul 2>&1

echo 작업 스케줄러에 등록합니다 (부팅 후 60초, SYSTEM 계정)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$taskName='%TASK_NAME%';" ^
  "$scriptDir='%SCRIPT_DIR%';" ^
  "$scriptDir=$scriptDir.TrimEnd('\');" ^
  "$action=New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c \"' + $scriptDir + '\start-server-autostart.bat\"') -WorkingDirectory $scriptDir;" ^
  "$trigger=New-ScheduledTaskTrigger -AtStartup;" ^
  "$trigger.Delay='PT60S';" ^
  "$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest;" ^
  "$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew;" ^
  "Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null;" ^
  "Write-Host '[완료] 작업 스케줄러에 등록되었습니다.';" ^
  "Write-Host '  - 부팅 후 60초 뒤 자동 시작 (로그인 불필요)';" ^
  "Write-Host '  - 실행 계정: SYSTEM';" ^
  "Write-Host '  - 작업 이름:' $taskName"

if errorlevel 1 (
    echo.
    echo [오류] 작업 등록에 실패했습니다. 관리자 권한으로 실행했는지 확인하세요.
    exit /b 1
)

echo.
echo 로그 파일:
echo   - %SCRIPT_DIR%logs\autostart.log
echo   - %ProgramData%\WifiRemocon\autostart.log  (SYSTEM 실행 시)
echo.
echo 작업 상태 확인: schtasks /Query /TN %TASK_NAME% /V /FO LIST
echo 작업 제거: unregister-autostart.bat
echo.
exit /b 0
