#!/bin/sh
# Последовательно выполняет уровни 4 и 6 в отдельных тестовых ресурсах.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
command -v docker >/dev/null || { echo 'Install and start Docker Desktop first' >&2; exit 1; }
docker info >/dev/null
docker compose version
TMP=$(mktemp -d "${TMPDIR:-/tmp}/docker-basics.XXXXXX")
TOKEN=$(basename "$TMP" | tr '[:upper:].' '[:lower:]-')
NAME="hwbasics-$TOKEN"
STAGE=initialization
dc() {
    HOST_PORT=0 GREETING="Basics check" docker compose --env-file .env.example \
        -f compose.sqlite.yaml -p "$NAME" "$@"
}
cleanup() {
    code=$?
    trap - EXIT HUP INT TERM
    if [ "$code" -ne 0 ]; then printf 'FAIL stage=%s\n' "$STAGE" >&2; fi
    # Все имена ниже уникальны для этого запуска.
    if docker container inspect "$NAME" >/dev/null 2>&1; then
        docker rm -f "$NAME" >/dev/null || code=1
    fi
    dc down -v --remove-orphans --timeout 10 || code=1
    if docker image inspect "$NAME" >/dev/null 2>&1; then
        docker image rm "$NAME" >/dev/null || code=1
    fi
    rm -rf "$TMP"
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
wait_ready() {
    i=0
    until curl -fsS --connect-timeout 2 --max-time 3 "$URL/readyz" >/dev/null 2>&1; do
        i=$((i + 1)); [ "$i" -lt 30 ] || { echo 'Readiness timeout' >&2; exit 1; }
        sleep 1
    done
}
get() { curl -fsS --connect-timeout 2 --max-time 5 "$URL/" > "$TMP/body"; cat "$TMP/body"; printf '\n'; }
post() { curl -fsS --connect-timeout 2 --max-time 5 -X POST "$URL/increment" > "$TMP/body"; cat "$TMP/body"; printf '\n'; }
STAGE=level-4
printf '\n=== 4 points: single container ===\n'
docker build -t "$NAME" .
docker run -d --name "$NAME" -e GREETING='Basics check' \
    -p 127.0.0.1::8000 --tmpfs /data:uid=10001,gid=10001,mode=0700 "$NAME"
URL="http://$(docker port "$NAME" 8000/tcp)"
wait_ready
get
docker exec -i "$NAME" python -c 'import json,sys; d=json.load(sys.stdin); assert d["count"]==0; assert d["greeting"]=="Basics check"' < "$TMP/body"
post
docker exec -i "$NAME" python -c 'import json,sys; d=json.load(sys.stdin); assert d["count"]==1; assert d["storage"]=="sqlite"' < "$TMP/body"
docker logs "$NAME"
docker rm -f "$NAME"
STAGE=level-6
printf '\n=== 6 points: Compose and named volume ===\n'
dc up -d --build --wait --wait-timeout 120
URL="http://$(dc port app 8000)"
post
dc exec -T app python -c 'import json,sys; d=json.load(sys.stdin); assert d["count"]==1; assert d["greeting"]=="Basics check"' < "$TMP/body"
dc down --timeout 10
dc up -d --wait --wait-timeout 120
URL="http://$(dc port app 8000)"
get
dc exec -T app python -c 'import json,sys; d=json.load(sys.stdin); assert d["count"]==1; assert d["storage"]=="sqlite"' < "$TMP/body"
dc logs --no-color
printf '\nPASS: levels 4 and 6\n'
