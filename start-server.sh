#!/bin/bash

echo "========================================"
echo "에어컨 제어 서버 시작"
echo "========================================"
echo ""

# Python 확인
if ! command -v python3 &> /dev/null; then
    echo "[오류] Python3가 설치되어 있지 않습니다."
    echo ""
    echo "Python을 설치해주세요:"
    echo "  1. Homebrew 사용: brew install python3"
    echo "  2. 또는 https://www.python.org/downloads/ 에서 다운로드"
    echo ""
    exit 1
fi

echo "Python 버전 확인 중..."
python3 --version
echo ""

# 현재 디렉토리로 이동
cd "$(dirname "$0")"

# 가상환경 확인 및 활성화
if [ -f "venv/bin/activate" ]; then
    echo "가상환경을 활성화합니다..."
    source venv/bin/activate
    if [ $? -ne 0 ]; then
        echo "[경고] 가상환경 활성화에 실패했습니다. 시스템 Python을 사용합니다."
        USE_VENV=0
    else
        echo "가상환경이 활성화되었습니다."
        USE_VENV=1
    fi
    echo ""
else
    echo "[경고] venv 폴더를 찾을 수 없습니다."
    echo "install-dependencies.sh을 먼저 실행하여 가상환경을 생성하세요."
    echo "시스템 Python을 사용합니다."
    echo ""
    USE_VENV=0
fi

# Python 명령어 결정
if [ "$USE_VENV" = "1" ]; then
    PYTHON_EXEC=python
else
    PYTHON_EXEC=python3
fi

echo "서버 시작 중..."
echo "웹 인터페이스: http://localhost:8000"
echo "종료하려면 Ctrl+C를 누르세요."
echo ""

# 서버 실행
$PYTHON_EXEC control-server.py

if [ $? -ne 0 ]; then
    echo ""
    echo "[오류] 서버 실행 중 오류가 발생했습니다."
    echo ""
    echo "필요한 패키지가 설치되어 있는지 확인해주세요:"
    echo "  pip install -r requirements.txt"
    echo ""
    echo "또는 install-dependencies.sh을 실행하세요."
    echo ""
fi

