@echo off
chcp 65001 >nul
echo ========================================
echo 에어컨 제어 시스템 초기 설정
echo ========================================
echo.
echo 이 스크립트는 다음을 수행합니다:
echo   1. Python 확인
echo   2. 가상환경(venv) 생성
echo   3. 필요한 패키지 설치
echo.
pause

REM install-dependencies.bat 실행
call install-dependencies.bat

if errorlevel 1 (
    echo.
    echo [오류] 초기 설정에 실패했습니다.
    pause
    exit /b 1
)

echo.
echo ========================================
echo 초기 설정 완료!
echo ========================================
echo.
echo 이제 start-server.bat을 실행하여 서버를 시작할 수 있습니다.
echo.
pause

