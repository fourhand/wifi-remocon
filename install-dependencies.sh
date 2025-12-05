#!/bin/bash

echo "========================================"
echo "필요한 패키지 설치"
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

# 가상환경 생성
echo "가상환경을 생성합니다..."
if [ -d "venv" ]; then
    echo "venv 폴더가 이미 존재합니다. 기존 가상환경을 사용합니다."
else
    python3 -m venv venv
    if [ $? -ne 0 ]; then
        echo "[오류] 가상환경 생성에 실패했습니다."
        exit 1
    fi
    echo "가상환경이 생성되었습니다."
fi
echo ""

# 가상환경 활성화
echo "가상환경을 활성화합니다..."
source venv/bin/activate
if [ $? -ne 0 ]; then
    echo "[오류] 가상환경 활성화에 실패했습니다."
    exit 1
fi
echo ""

# pip 업그레이드
echo "pip를 최신 버전으로 업그레이드합니다..."
python -m pip install --upgrade pip
echo ""

# 패키지 설치
echo "필요한 패키지를 설치합니다..."
echo ""

python -m pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo ""
    echo "[오류] 패키지 설치 중 오류가 발생했습니다."
    exit 1
fi

echo ""
echo "========================================"
echo "패키지 설치 완료!"
echo "========================================"
echo ""
echo "가상환경이 준비되었습니다."
echo "이제 ./start-server.sh을 실행하여 서버를 시작할 수 있습니다."
echo ""
echo "참고: 가상환경을 수동으로 활성화하려면:"
echo "  source venv/bin/activate"
echo ""

