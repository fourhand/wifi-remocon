#!/bin/bash

echo "========================================"
echo "모듈 상태 조회 (/devices/status)"
echo "========================================"
echo ""

# API 기본 URL (필요 시 환경변수로 오버라이드)
API_URL="${API_URL:-http://localhost:8000}"
URL="$API_URL/devices/status"

echo "[정보] API 호출: $URL"
RESP="$(curl -fsS "$URL" 2>/dev/null)"
if [ -z "$RESP" ]; then
  echo "[오류] API 호출 실패. 서버가 실행 중인지와 포트 접근 가능 여부를 확인하세요."
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo ""
  echo "id           addr         health     power  mode  setTemp  roomTemp  fan   swing"
  echo "============ ===========  =========  =====  ====  =======  ========  ====  ====="
  echo "$RESP" | jq -r '
    sort_by(.id)[] as $d |
    (
      ( ($d.state // {}) | .power ) as $pw
      |
      [
        ($d.id // ""),
        ((($d.ip // "") + ":" + (($d.port // 0) | tostring))),
        (if ($d.health // {}) | .ok then "OK"
         else (if ($d.health // {}) | has("status_code") then "ERR " + ((($d.health.status_code // "") | tostring)) else "N/A" end)
         end),
        ( if $pw == true then "ON"
          elif $pw == false then "OFF"
          elif ($pw|type) == "string" then
             ( if ($pw|ascii_downcase) == "true" or ($pw|ascii_downcase) == "on" then "ON"
               elif ($pw|ascii_downcase) == "false" or ($pw|ascii_downcase) == "off" then "OFF"
               else $pw end )
          else "--" end ),
        ((($d.state // {}) | .mode) // ""),
        (((($d.state // {}) | .temp) // "" ) | tostring),
        (((($d.state // {}) | .room_temp) // "" ) | tostring),
        ((($d.state // {}) | .fan) // ""),
        ((($d.state // {}) | .swing) // "")
      ]
    ) | @tsv
  ' | awk -F'\t' '{ printf "%-12s %-11s %-10s %-6s %-5s %-7s %-8s %-5s %-5s\n", $1,$2,$3,$4,$5,(length($6)?$6:"--"),(length($7)?$7:"--"),$8,$9 }'
else
  echo ""
  echo "[참고] jq가 없어 원본 JSON을 출력합니다. (설치 권장: sudo apt-get install -y jq)"
  echo "$RESP"
fi


