#!/bin/bash

echo "========================================"
echo "업데이트 실행 (git pull + 서비스 재시작)"
echo "========================================"
echo ""

# 스크립트 위치로 이동
cd "$(dirname "$0")"

# Git 업데이트
if command -v git >/dev/null 2>&1; then
  echo "[업데이트] Git 업데이트 중..."
  git fetch --all || true
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  echo "[업데이트] 현재 브랜치: $BRANCH"
  git reset --hard "origin/$BRANCH" || git pull --rebase || true
  echo "[업데이트] Git 업데이트 완료"
else
  echo "[업데이트] git 명령을 찾을 수 없습니다. Git 업데이트를 건너뜁니다."
fi

echo ""
# systemd 재시작 우선
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files --type=service | grep -q "^wifi-remocon.service"; then
  echo "[업데이트] systemd로 서비스 재시작 시도..."
  if systemctl restart wifi-remocon.service >/dev/null 2>&1; then
    echo "[업데이트] ✓ systemd 서비스 재시작 성공"
    echo "[업데이트] 상태: $(systemctl is-active wifi-remocon.service 2>/dev/null) / 부팅연결: $(systemctl is-enabled wifi-remocon.service 2>/dev/null)"
    echo "[업데이트] 최근 로그:"
    journalctl -u wifi-remocon.service -n 20 --no-pager 2>/dev/null || true
    echo ""
    echo "========================================"
    echo "업데이트 완료 - systemd 서비스가 재시작되었습니다."
    echo "========================================"
    exit 0
  else
    echo "[업데이트] ⚠ systemd 재시작 실패, 스크립트 방식으로 시도"
  fi
fi

# 폴백: 기존 프로세스 종료 후 nohup 실행
echo "[업데이트] 기존 서버 프로세스 종료 시도..."
pkill -f "control-server.py" >/dev/null 2>&1 || true
sleep 1
echo "[업데이트] 서버 재시작 (nohup)..."
nohup ./start-server.sh >/tmp/wifi-remocon.log 2>&1 &
disown
echo ""
echo "========================================"
echo "업데이트 완료 - 서버가 백그라운드에서 재시작되었습니다."
echo "로그: /tmp/wifi-remocon.log"
echo "========================================"


