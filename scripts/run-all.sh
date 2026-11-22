#!/bin/sh
# Записывает настоящий вывод проверок, сохраняя код ошибки каждой команды.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p reports
run_logged() {
    log=$1
    shift
    if "$@" > "$log" 2>&1; then
        cat "$log"
    else
        code=$?
        cat "$log" >&2
        printf 'FAILED: %s (exit %s)\n' "$log" "$code" >&2
        exit "$code"
    fi
}
run_logged reports/basics.log ./scripts/check-basics.sh
run_logged reports/check-1.log ./scripts/check.sh
run_logged reports/check-2.log ./scripts/check.sh
printf '\nALL CHECKS PASSED. Logs: reports/basics.log, reports/check-1.log, reports/check-2.log\n'
