#!/bin/sh
# Проверяет свой отдельный проект; пользовательские volumes не затрагивает.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p reports
TMP=$(mktemp -d "${TMPDIR:-/tmp}/docker-hw.XXXXXX")
TOKEN=$(basename "$TMP" | tr '[:upper:].' '[:lower:]-')
PROJECT="hwcheck-$TOKEN"
RESTORE="hwrestore-$TOKEN"
STAGE=initialization
N=5
DOCKER_READY=0

dc() {
    HOST_PORT=0 GREETING="Docker homework check" docker compose \
        --env-file "$ROOT/.env.example" -f "$ROOT/compose.yaml" -p "$PROJECT" "$@"
}
dr() {
    HOST_PORT=0 GREETING="Docker homework check" docker compose \
        --env-file "$ROOT/.env.example" -f "$ROOT/compose.yaml" -p "$RESTORE" "$@"
}
cleanup() {
    code=$?
    trap - EXIT HUP INT TERM
    if [ "$code" -ne 0 ]; then
        printf '\nFAIL stage=%s exit=%s\n' "$STAGE" "$code" >&2
        if [ "$DOCKER_READY" -eq 1 ]; then dc logs --no-color --tail=50 >&2 || true; fi
    fi
    clean_failed=0
    if [ "$DOCKER_READY" -eq 1 ]; then
        dc down -v --remove-orphans --timeout 10 || clean_failed=1
        dr down -v --remove-orphans --timeout 10 || clean_failed=1
    fi
    rm -rf "$TMP"
    if [ "$clean_failed" -ne 0 ]; then
        printf 'FAIL: cleanup of test resources failed\n' >&2
        code=1
    fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

stage() { STAGE=$1; printf '\n=== %s ===\n' "$STAGE"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
get_url() {
    address=$("$1" port app 8000)
    [ -n "$address" ] || fail 'No published app port'
    URL="http://$address"
}
request() {
    curl --silent --show-error --connect-timeout 2 --max-time 5 \
        -X "$1" -o "$TMP/body" -w '%{http_code}' "$URL$2" > "$TMP/status"
    status=$(cat "$TMP/status")
    printf '%s %s -> %s %s\n' "$1" "$2" "$status" "$(cat "$TMP/body")"
    [ "$status" = "$3" ] || fail "Expected HTTP $3, got $status"
}
wait_ready() {
    attempts=0
    until curl -fsS --connect-timeout 2 --max-time 3 "$URL/readyz" > /dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 30 ] || fail 'Readiness timeout'
        sleep 1
    done
}
assert_count() {
    # Парсер JSON выполняется в уже работающем контейнере, Python на хосте не нужен.
    "$1" exec -T app python -c \
        'import json,sys; data=json.load(sys.stdin); assert data["count"] == int(sys.argv[1]), data; assert data["storage"] == "redis", data; assert data["greeting"] == "Docker homework check", data' \
        "$2" < "$TMP/body"
}

stage prerequisites
command -v docker >/dev/null || fail 'Install and start Docker Desktop first'
command -v curl >/dev/null || fail 'curl is required'
docker info >/dev/null
docker compose version
DOCKER_READY=1

stage fresh-project
dc up -d --build --wait --wait-timeout 120
get_url dc
request GET / 200
assert_count dc 0
stage increments
i=0
while [ "$i" -lt "$N" ]; do
    i=$((i + 1))
    request POST /increment 200
    assert_count dc "$i"
done

stage process-restrictions
dc exec -T app python -c 'import os; assert os.getuid() != 0; print("UID:", os.getuid())'
CID=$(dc ps -q app)
limits=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}' "$CID")
printf 'read_only memory_bytes nano_cpus: %s\n' "$limits"
[ "$limits" = 'true 268435456 1000000000' ] || fail 'Incorrect process limits'

stage recreate-app
dc up -d --no-deps --force-recreate --wait --wait-timeout 120 app
get_url dc
request GET / 200
assert_count dc "$N"

stage down-up-persistence
dc down --timeout 10
dc up -d --wait --wait-timeout 120
get_url dc
request GET / 200
assert_count dc "$N"

stage redis-outage
APP_BEFORE=$(dc ps -q app)
dc stop --timeout 10 redis
request GET /healthz 200
request GET /readyz 503
request GET / 503
request POST /increment 503

stage redis-recovery
dc start redis
wait_ready
[ "$APP_BEFORE" = "$(dc ps -q app)" ] || fail 'App was recreated during recovery'
request GET / 200
assert_count dc "$N"
N=$((N + 1))
request POST /increment 200
assert_count dc "$N"
dc logs --no-color --tail=100

stage consistent-backup
# Запись завершена, оба сервиса штатно остановлены. tar сохраняет права и UID/GID.
dc stop --timeout 10 app redis
BACKUP="$ROOT/reports/backup-$PROJECT.tar"
dc run --rm --no-deps -T --user 0 --entrypoint tar redis \
    -C /data -cpf - . > "$BACKUP"
[ -s "$BACKUP" ] || fail 'Empty backup archive'
printf 'Backup: %s\n' "$BACKUP"

stage remove-source-volumes
dc down -v --timeout 10

stage restore-into-new-project
dr run --rm --no-deps -T --user 0 --entrypoint tar redis \
    -C /data -xpf - < "$BACKUP"
dr up -d --wait --wait-timeout 120
get_url dr
request GET / 200
assert_count dr "$N"
N=$((N + 1))
request POST /increment 200
assert_count dr "$N"

stage finished
printf 'PASS: counter, persistence, outage, backup and restore verified\n'
# EXIT trap удаляет только два сгенерированных тестовых проекта.
