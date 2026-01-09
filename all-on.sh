#!/bin/bash

echo "========================================"
echo "모든 에어컨 켜기 (모드/설정온도 선택)"
echo "========================================"
echo ""

# API 기본 URL (환경변수로 변경 가능)
API_URL="${API_URL:-http://localhost:8000}"
ENDPOINT="$API_URL/all/on"

usage() {
  echo "사용: $0 [--mode <mode>] [--temp <int>]"
  echo "예시:"
  echo "  $0 --mode cool --temp 24"
  echo "  $0 --temp 26            # 모드 생략 시 서버 기본값 사용"
  echo "  $0                      # 서버 기본값(mode=cool,temp=24) 사용"
}

MODE=""
TEMP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)
      MODE="${2:-}"
      shift 2
      ;;
    -t|--temp)
      TEMP="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[경고] 알 수 없는 인자: $1"
      usage
      exit 1
      ;;
  esac
done

# 모드/온도 입력이 없을 경우 인터랙티브로 입력 받기
if [[ -z "$MODE" ]]; then
  read -r -p "운전 모드 선택 [cool/hot] (기본: cool): " MODE
  MODE="${MODE:-cool}"
fi
LOWER_MODE="$(echo "$MODE" | tr '[:upper:]' '[:lower:]')"
if [[ "$LOWER_MODE" != "cool" && "$LOWER_MODE" != "hot" ]]; then
  echo "[오류] 모드는 'cool' 또는 'hot' 중 하나여야 합니다."
  exit 1
fi
MODE="$LOWER_MODE"

if [[ -z "$TEMP" ]]; then
  read -r -p "설정 온도 입력 (16~30, 기본: 24): " TEMP
  TEMP="${TEMP:-24}"
fi

# temp 유효성
if [[ -n "$TEMP" ]]; then
  if ! echo "$TEMP" | grep -Eq '^-?[0-9]+$'; then
    echo "[오류] --temp 는 정수여야 합니다."
    exit 1
  fi
  if [ "$TEMP" -lt 16 ] || [ "$TEMP" -gt 30 ]; then
    echo "[경고] 일반적인 설정 온도 범위(16~30)를 벗어났습니다."
  fi
fi

# JSON 페이로드 구성 (입력된 항목만 전송)
PAYLOAD="{"
COMMA=""
add_field() {
  local key="$1"
  local val="$2"
  local is_string="$3"
  if [ -n "$val" ]; then
    if [ -n "$COMMA" ]; then
      PAYLOAD="${PAYLOAD}, "
    fi
    if [ "$is_string" = "1" ]; then
      PAYLOAD="${PAYLOAD}\"${key}\": \"${val}\""
    else
      PAYLOAD="${PAYLOAD}\"${key}\": ${val}"
    fi
    COMMA="1"
  fi
}

add_field "mode" "$MODE" 1
add_field "temp" "$TEMP" 0
PAYLOAD="${PAYLOAD}}"

echo "[정보] 호출: POST $ENDPOINT"
if [ "$PAYLOAD" = "{}" ]; then
  # 서버 기본값 사용 (바디 없이 호출)
  RESP="$(curl -fsS -X POST "$ENDPOINT" 2>/dev/null)"
else
  echo "Payload: $PAYLOAD"
  RESP="$(curl -fsS -X POST "$ENDPOINT" -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null)"
fi

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


