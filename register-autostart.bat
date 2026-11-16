@echo off
chcp 65001 >nul
setlocal enableextensions

set TASK_NAME=WifiRemoconControlServer
set UPDATE_TASK_NAME=WifiRemoconAutoUpdate
set SCRIPT_DIR=%~dp0
set STARTUP_LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WifiRemoconControlServer.lnk

echo ========================================
echo 에어컨 제어 서버 자동 시작/업데이트 등록
echo ========================================
echo.
echo ※ 관리자 권한 PowerShell/명령 프롬프트에서 실행해야 합니다.
echo.

if not exist "%SCRIPT_DIR%start-server-autostart.bat" (
    echo [오류] start-server-autostart.bat을 찾을 수 없습니다.
    exit /b 1
)

if not exist "%SCRIPT_DIR%update-check.bat" (
    echo [오류] update-check.bat을 찾을 수 없습니다.
    exit /b 1
)

if not exist "%SCRIPT_DIR%venv\Scripts\python.exe" (
    echo [오류] 가상환경이 없습니다. 먼저 setup.bat을 실행하세요.
    exit /b 1
)

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo 기존 서버 작업을 삭제합니다...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul
)
schtasks /Query /TN "%UPDATE_TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo 기존 업데이트 작업을 삭제합니다...
    schtasks /Delete /TN "%UPDATE_TASK_NAME%" /F >nul
)
if exist "%STARTUP_LINK%" del "%STARTUP_LINK%" >nul 2>&1

echo 작업 스케줄러에 등록합니다...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$scriptDir='%SCRIPT_DIR%';" ^
  "$scriptDir=$scriptDir.TrimEnd('\');" ^
  "$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest;" ^
  "$serverAction=New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c \"' + $scriptDir + '\start-server-autostart.bat\"') -WorkingDirectory $scriptDir;" ^
  "$serverTrigger=New-ScheduledTaskTrigger -AtStartup;" ^
  "$serverTrigger.Delay='PT60S';" ^
  "$serverSettings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew;" ^
  "Register-ScheduledTask -TaskName '%TASK_NAME%' -Action $serverAction -Trigger $serverTrigger -Principal $principal -Settings $serverSettings -Force | Out-Null;" ^
  "$updateAction=New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c \"' + $scriptDir + '\update-check.bat\"') -WorkingDirectory $scriptDir;" ^
  "$updateTrigger=New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2)) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration ([TimeSpan]::MaxValue);" ^
  "$updateSettings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew;" ^
  "Register-ScheduledTask -TaskName '%UPDATE_TASK_NAME%' -Action $updateAction -Trigger $updateTrigger -Principal $principal -Settings $updateSettings -Force | Out-Null;" ^
  "Write-Host '[완료] 작업 스케줄러에 등록되었습니다.';" ^
  "Write-Host '  - 서버: 부팅 후 60초 뒤 자동 시작 (로그인 불필요)';" ^
  "Write-Host '  - 업데이트: 10분마다 GitHub 확인, 변경 시에만 재시작';" ^
  "Write-Host '  - 실행 계정: SYSTEM';" ^
  "Write-Host '  - 작업 이름: %TASK_NAME%, %UPDATE_TASK_NAME%'"

if errorlevel 1 (
    echo.
    echo [오류] 작업 등록에 실패했습니다. 관리자 권한으로 실행했는지 확인하세요.
    exit /b 1
)

echo.
echo 로그 파일:
echo   - %SCRIPT_DIR%logs\autostart.log
echo   - %SCRIPT_DIR%logs\update-check.log
echo   - %ProgramData%\WifiRemocon\  (SYSTEM 실행 시)
echo.
echo 작업 상태 확인:
echo   schtasks /Query /TN %TASK_NAME% /V /FO LIST
echo   schtasks /Query /TN %UPDATE_TASK_NAME% /V /FO LIST
echo 작업 제거: unregister-autostart.bat
echo.
exit /b 0
