#!/bin/bash

echo "========================================"
echo "에어컨 제어 시스템 초기 설정"
echo "========================================"
echo ""
echo "이 스크립트는 다음을 수행합니다:"
echo "  1. Python 확인"
echo "  2. 가상환경(venv) 생성"
echo "  3. 필요한 패키지 설치"
echo ""

# install-dependencies.sh 실행
./install-dependencies.sh

if [ $? -ne 0 ]; then
    echo ""
    echo "[오류] 초기 설정에 실패했습니다."
    exit 1
fi

echo ""
echo "========================================"
echo "초기 설정 완료!"
echo "========================================"
echo ""
echo "이제 ./start-server.sh을 실행하여 서버를 시작할 수 있습니다."
echo ""

