#!/bin/bash

echo "========================================"
echo "예약 설정 (API 통해 서버에 반영)"
echo "========================================"
echo ""

# 설정: API 엔드포인트 (필요시 환경변수로 덮어쓰기 가능)
API_URL="${API_URL:-http://localhost:8000}"

# 스크립트 위치로 이동
cd "$(dirname "$0")"

# 도우미: 문자열 트림
trim() {
  local var="$*"
  # shellcheck disable=SC2001
  echo "$(echo "$var" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
}

# 도우미: HH:MM -> 분 변환 (유효성 검사 포함)
to_minutes() {
  local hm="$1"
  if ! echo "$hm" | grep -Eq '^[0-2]?[0-9]:[0-5][0-9]$'; then
    echo "INVALID"
    return
  fi
  local h="${hm%%:*}"
  local m="${hm##*:}"
  if [ "$h" -gt 23 ] || [ "$m" -gt 59 ]; then
    echo "INVALID"
    return
  fi
  echo $((10#$h * 60 + 10#$m))
}

# 현재 스케줄 목록 간단 조회 (API만 사용)
echo "[정보] 현재 스케줄 목록을 불러옵니다..."
RESP="$(curl -fsS "$API_URL/schedules" 2>/dev/null)"
if [ -z "$RESP" ]; then
  echo "[오류] 스케줄 목록을 가져오지 못했습니다: $API_URL/schedules"
  echo " - 서버가 실행 중인지, 방화벽/포트 8000 접근 가능한지 확인하세요."
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo ""
  echo "id  enabled  power  mode  temp  type    date        weekday  start  end    summary"
  echo "==  =======  =====  ====  ====  ======  ==========  =======  =====  =====  ========================================"
  echo "$RESP" | jq -r '
    .[] |
    [
      .id,
      (if .enabled then "Y" else "N" end),
      .power, .mode, .temp, .schedule_type,
      (.date // ""),
      (.weekday // ""),
      (.start_time_min // 0 | tostring),
      (.end_time_min // 0 | tostring),
      (.summary // "")
    ] | @tsv
  ' | awk -F'\t' '{ printf "%-3s %-8s %-6s %-5s %-5s %-7s %-11s %-8s %-6s %-6s %s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11 }'
else
  echo ""
  echo "[참고] jq가 없어 원본 JSON을 출력합니다. (설치 권장: sudo apt-get install -y jq)"
  echo "$RESP"
fi
echo ""

# 1) 스케줄 번호 선택 (1..7)
while true; do
  read -r -p "수정할 스케줄 번호(1-7): " SID
  SID="$(trim "$SID")"
  if echo "$SID" | grep -Eq '^[1-7]$'; then
    break
  fi
  echo " - 1에서 7 사이 숫자를 입력하세요."
done

# 2) 활성화 여부
while true; do
  read -r -p "활성화 할까요? (y/n, 기본: 현재 유지): " ENA
  ENA="$(echo "$ENA" | tr '[:upper:]' '[:lower:]')"
  if [ -z "$ENA" ] || [ "$ENA" = "y" ] || [ "$ENA" = "n" ]; then
    break
  fi
  echo " - y 또는 n 로 입력하세요. 비워두면 기존 유지."
done

# 3) 스케줄 타입 선택
echo ""
echo "스케줄 타입 선택:"
echo "  1) once  (1회)"
echo "  2) daily (매일)"
echo "  3) weekly(매주)"
read -r -p "선택(1-3, 비우면 기존 유지): " TYPE_SEL
TYPE_SEL="$(trim "$TYPE_SEL")"
SCH_TYPE=""
case "$TYPE_SEL" in
  1) SCH_TYPE="once" ;;
  2) SCH_TYPE="daily" ;;
  3) SCH_TYPE="weekly" ;;
  *) SCH_TYPE="" ;;
esac

# 4) 타입별 추가 입력
DATE_VAL=""
WEEKDAY_VAL=""
START_HM=""
END_HM=""
if [ "$SCH_TYPE" = "once" ]; then
  read -r -p "날짜(YYYY-MM-DD): " DATE_VAL
  DATE_VAL="$(trim "$DATE_VAL")"
  if ! echo "$DATE_VAL" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo " - 날짜 형식이 올바르지 않아 비워둡니다(기존 유지)."
    DATE_VAL=""
  fi
  read -r -p "시작 시간(HH:MM): " START_HM
  START_HM="$(trim "$START_HM")"
  read -r -p "종료 시간(HH:MM): " END_HM
  END_HM="$(trim "$END_HM")"
elif [ "$SCH_TYPE" = "daily" ]; then
  read -r -p "시작 시간(HH:MM): " START_HM
  START_HM="$(trim "$START_HM")"
  read -r -p "종료 시간(HH:MM): " END_HM
  END_HM="$(trim "$END_HM")"
elif [ "$SCH_TYPE" = "weekly" ]; then
  echo "요일(0=월, 1=화, 2=수, 3=목, 4=금, 5=토, 6=일)"
  read -r -p "요일(0-6): " WEEKDAY_VAL
  WEEKDAY_VAL="$(trim "$WEEKDAY_VAL")"
  if ! echo "$WEEKDAY_VAL" | grep -Eq '^[0-6]$'; then
    echo " - 요일 입력이 올바르지 않아 비워둡니다(기존 유지)."
    WEEKDAY_VAL=""
  fi
  read -r -p "시작 시간(HH:MM): " START_HM
  START_HM="$(trim "$START_HM")"
  read -r -p "종료 시간(HH:MM): " END_HM
  END_HM="$(trim "$END_HM")"
fi

# 5) 전원/모드/온도 (선택 입력, 비우면 기존 유지)
echo ""
read -r -p "전원(power) [on/off] (비우면 기존 유지): " POWER_VAL
POWER_VAL="$(trim "$POWER_VAL")"
if [ -n "$POWER_VAL" ] && [ "$POWER_VAL" != "on" ] && [ "$POWER_VAL" != "off" ]; then
  echo " - power 값이 on/off가 아니어서 무시합니다."
  POWER_VAL=""
fi
read -r -p "모드(mode) [cool/hot 등] (비우면 기존 유지): " MODE_VAL
MODE_VAL="$(trim "$MODE_VAL")"
read -r -p "온도(temp, 정수) (비우면 기존 유지): " TEMP_VAL
TEMP_VAL="$(trim "$TEMP_VAL")"
if [ -n "$TEMP_VAL" ] && ! echo "$TEMP_VAL" | grep -Eq '^-?[0-9]+$'; then
  echo " - temp 값이 정수가 아니어서 무시합니다."
  TEMP_VAL=""
fi

# 시간 변환
START_MIN=""
END_MIN=""
if [ -n "$START_HM" ]; then
  START_MIN="$(to_minutes "$START_HM")"
  if [ "$START_MIN" = "INVALID" ]; then
    echo " - 시작 시간이 올바르지 않아 무시합니다."
    START_MIN=""
  fi
fi
if [ -n "$END_HM" ]; then
  END_MIN="$(to_minutes "$END_HM")"
  if [ "$END_MIN" = "INVALID" ]; then
    echo " - 종료 시간이 올바르지 않아 무시합니다."
    END_MIN=""
  fi
fi

# JSON 페이로드 구성 (입력된 항목만 반영)
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

if [ "$ENA" = "y" ]; then add_field "enabled" "true" 0; fi
if [ "$ENA" = "n" ]; then add_field "enabled" "false" 0; fi
add_field "schedule_type" "$SCH_TYPE" 1
add_field "date" "$DATE_VAL" 1
add_field "weekday" "$WEEKDAY_VAL" 0
add_field "start_time_min" "$START_MIN" 0
add_field "end_time_min" "$END_MIN" 0
add_field "power" "$POWER_VAL" 1
add_field "mode" "$MODE_VAL" 1
add_field "temp" "$TEMP_VAL" 0
PAYLOAD="${PAYLOAD}}"

# 빈 업데이트 방지
if [ "$PAYLOAD" = "{}" ]; then
  echo ""
  echo "[안내] 변경할 항목이 없습니다. 종료합니다."
  exit 0
fi

echo ""
echo "다음 내용으로 적용합니다:"
echo "PUT $API_URL/schedules/$SID"
echo "Payload: $PAYLOAD"
read -r -p "진행할까요? (Y/n): " CONFIRM
CONFIRM="$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')"
if [ -n "$CONFIRM" ] && [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

echo ""
RESULT="$(curl -fsS -X PUT "$API_URL/schedules/$SID" -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null)"
if [ -z "$RESULT" ]; then
  echo "[오류] 서버 응답이 없습니다."
  exit 1
fi

echo "[결과] 서버 응답:"
if command -v jq >/dev/null 2>&1; then
  echo "$RESULT" | jq .
else
  echo "$RESULT"
fi

echo ""
echo "[완료] 최신 스케줄 목록:"
curl -fsS "$API_URL/schedules" 2>/dev/null | (jq . 2>/dev/null || cat)


