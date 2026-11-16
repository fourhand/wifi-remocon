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
set LOG_FILE=%LOG_DIR%\update-check.log
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

echo [%date% %time%] 업데이트 확인 시작 (user=%USERNAME%) >> "%LOG_FILE%"

set PYTHON_EXE=
if exist "%~dp0venv\Scripts\python.exe" (
    set PYTHON_EXE=%~dp0venv\Scripts\python.exe
) else (
    where python >nul 2>&1 && set PYTHON_EXE=python
)

if "%PYTHON_EXE%"=="" (
    echo [%date% %time%] [오류] Python을 찾을 수 없습니다. >> "%LOG_FILE%"
    exit /b 1
)

"%PYTHON_EXE%" "%~dp0github-pull.py" >> "%LOG_FILE%" 2>&1
set EXIT_CODE=%errorlevel%
echo [%date% %time%] 업데이트 확인 종료 (exit=%EXIT_CODE%) >> "%LOG_FILE%"
exit /b %EXIT_CODE%
