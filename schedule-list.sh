#!/bin/bash

echo "========================================"
echo "스케줄 목록 조회"
echo "========================================"
echo ""

# 스크립트 위치로 이동
cd "$(dirname "$0")"

echo "[정보] API로 조회합니다."
URL="http://localhost:8000/schedules"
RESP="$(command -v curl >/dev/null 2>&1 && curl -fsS "$URL")"
if [ -z "$RESP" ]; then
  echo "[오류] API 호출에 실패했습니다: $URL"
  echo " - 서버가 실행 중인지 확인하세요 (포트 8000)"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo ""
  echo "id  enabled  power  mode  temp  type    date        요일     start  end    summary"
  echo "==  =======  =====  ====  ====  ======  ==========  ======   =====  =====  ========================================"
  echo "$RESP" | jq -r '
    .[] |
    [
      .id,
      (if .enabled then "Y" else "N" end),
      .power, .mode, .temp, .schedule_type,
      (.date // ""),
      ( if (.weekday // null) == null then ""
        else (["월요일","화요일","수요일","목요일","금요일","토요일","주일"][.weekday])
        end ),
      (.start_time_min // 0 | tostring),
      (.end_time_min // 0 | tostring),
      ((.summary // "") | gsub("일요일";"주일"))
    ] | @tsv
  ' | awk -F'\t' '{ printf "%-3s %-8s %-6s %-5s %-5s %-7s %-11s %-7s %-6s %-6s %s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11 }'
else
  echo ""
  echo "[참고] jq가 없어 원본 JSON을 출력합니다. (설치 권장: sudo apt-get install -y jq)"
  echo "$RESP"
fi


