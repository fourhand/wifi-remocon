@echo off
chcp 65001 >nul
echo ========================================
echo hosts 파일에 aircon-controller 추가
echo ========================================
echo.

REM 관리자 권한 확인
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [오류] 이 스크립트는 관리자 권한으로 실행해야 합니다.
    echo.
    echo 해결 방법:
    echo   1. 이 파일을 우클릭
    echo   2. "관리자 권한으로 실행" 선택
    echo.
    pause
    exit /b 1
)

REM 현재 IP 주소 가져오기
echo IP 주소를 감지하는 중...
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set IP=%%a
    set IP=!IP: =!
    goto :found_ip
)

:found_ip
if "%IP%"=="" (
    echo [오류] IP 주소를 찾을 수 없습니다.
    pause
    exit /b 1
)

echo 감지된 IP 주소: %IP%
echo.

REM hosts 파일 경로
set HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts

REM 이미 등록되어 있는지 확인
findstr /c:"aircon-controller.local" "%HOSTS_FILE%" >nul 2>&1
if %errorlevel% equ 0 (
    echo [정보] hosts 파일에 이미 aircon-controller.local이 등록되어 있습니다.
    echo.
    echo 기존 항목을 제거하고 새로 추가하시겠습니까? (Y/N)
    set /p CONFIRM=
    if /i not "%CONFIRM%"=="Y" (
        echo 취소되었습니다.
        pause
        exit /b 0
    )
    
    REM 기존 항목 제거 (임시 파일 사용)
    findstr /v /c:"aircon-controller.local" "%HOSTS_FILE%" > "%HOSTS_FILE%.tmp"
    move /y "%HOSTS_FILE%.tmp" "%HOSTS_FILE%" >nul
)

REM hosts 파일에 추가
echo %IP%  aircon-controller.local >> "%HOSTS_FILE%"

if %errorlevel% equ 0 (
    echo.
    echo [성공] hosts 파일에 추가되었습니다!
    echo.
    echo 이제 http://aircon-controller.local:8000/ 으로 접속할 수 있습니다.
    echo.
) else (
    echo.
    echo [오류] hosts 파일에 추가하는데 실패했습니다.
    echo.
)

pause



