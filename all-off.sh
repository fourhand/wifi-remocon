#!/bin/bash

echo "========================================"
echo "모든 에어컨 끄기 (power만 OFF)"
echo "========================================"
echo ""

# API 기본 URL (환경변수로 변경 가능)
API_URL="${API_URL:-http://localhost:8000}"
ENDPOINT="$API_URL/all/off"

echo "[정보] 호출: POST $ENDPOINT"
# 서버 쪽에서 power=off만 전송하도록 구현되어 있으므로 바디 없이 호출
RESP="$(curl -fsS -X POST "$ENDPOINT" 2>/dev/null)"

if [ -z "$RESP" ]; then
  echo "[오류] 서버 응답이 없습니다. 서버가 실행 중인지 확인하세요."
  exit 1
fi

echo ""
echo "[결과]"
if command -v jq >/dev/null 2>&1; then
  echo "$RESP" | jq .
else
  echo "$RESP"
fi


