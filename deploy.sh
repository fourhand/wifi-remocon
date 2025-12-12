#!/bin/bash

echo "========================================"
echo "배포 시작 (git pull + 서버 재시작)"
echo "========================================"
echo ""

# 스크립트 위치로 이동
cd "$(dirname "$0")"

# Git 업데이트
if command -v git >/dev/null 2>&1; then
  echo "[배포] Git 업데이트 중..."
  git fetch --all || true
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  echo "[배포] 현재 브랜치: $BRANCH"
  # origin/$BRANCH 기준으로 강제 동기화 시도, 실패 시 pull --rebase
  git reset --hard "origin/$BRANCH" || git pull --rebase || true
  echo "[배포] Git 업데이트 완료"
else
  echo "[배포] git 명령을 찾을 수 없습니다. Git 업데이트를 건너뜁니다."
fi

# 서버 재시작
echo ""
echo "[배포] 기존 서버 프로세스 종료 시도..."
pkill -f "control-server.py" >/dev/null 2>&1 || true
sleep 1

echo "[배포] 서버 재시작..."
nohup ./start-server.sh >/tmp/wifi-remocon.log 2>&1 &
disown

echo ""
echo "========================================"
echo "배포 완료 - 서버가 백그라운드에서 재시작되었습니다."
echo "로그: /tmp/wifi-remocon.log"
echo "========================================"


