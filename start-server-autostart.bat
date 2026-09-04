@echo off
chcp 65001 >nul
setlocal enableextensions

cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

whoami | findstr /I "NT AUTHORITY\SYSTEM" >nul 2>&1
if %errorlevel%==0 (
    set LOG_DIR=%ProgramData%\WifiRemocon
) else (
    set LOG_DIR=%~dp0logs
)
set LOG_FILE=%LOG_DIR%\autostart.log
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

echo [%date% %time%] 서버 자동 시작 (user=%USERNAME%) >> "%LOG_FILE%"

if not exist "%~dp0venv\Scripts\python.exe" (
    echo [%date% %time%] [오류] venv\Scripts\python.exe 없음 >> "%LOG_FILE%"
    exit /b 1
)

"%~dp0venv\Scripts\python.exe" "%~dp0control-server.py" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] [오류] 서버 종료 (exit code %errorlevel%) >> "%LOG_FILE%"
    exit /b 1
)
