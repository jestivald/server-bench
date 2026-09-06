#!/usr/bin/env bash
# Linux integration checks against real fio/iperf3/jq/GNU timeout.
# All traffic stays on loopback; fio writes only a temporary test file.
# shellcheck disable=SC1091

source "$(dirname "${BASH_SOURCE[0]}")/../server-bench.sh"
export LC_ALL=C
for tool in fio iperf3 jq timeout; do
    command_exists "$tool" || { printf 'Missing integration dependency: %s\n' "$tool" >&2; exit 1; }
done

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/server-bench-integration.XXXXXXXX") || exit 1
BENCH_SERVER_PID=""
integration_cleanup() {
    if [[ -n "$BENCH_SERVER_PID" ]]; then
        kill "$BENCH_SERVER_PID" 2>/dev/null || true
        wait "$BENCH_SERVER_PID" 2>/dev/null || true
    fi
    cleanup
}
trap integration_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

iperf3 -s -B 127.0.0.1 -p 52019 >"$WORK_DIR/iperf-server.log" 2>&1 &
BENCH_SERVER_PID=$!
sleep 0.3
kill -0 "$BENCH_SERVER_PID" 2>/dev/null || { cat "$WORK_DIR/iperf-server.log"; exit 1; }
for direction in upload download; do
    iperf_sample 127.0.0.1 52019 "$direction" "$WORK_DIR/iperf-$direction.json" || exit 1
    awk -v speed="$IPERF_MBPS" 'BEGIN {exit !(speed > 0)}' || exit 1
done
printf 'PASS: real iPerf3 upload and reverse download with jq parsing\n'

# Shared with fio_job/cleanup from server-bench.sh.
# shellcheck disable=SC2034
DISK_FILE=$(mktemp "$PWD/.server-bench-fio.XXXXXXXX") || exit 1
# shellcheck disable=SC2034
FIO_ENG=psync
for direction in write read; do
    fio_job "fio $direction" "$WORK_DIR/fio-$direction.log" \
        --rw="$direction" --bs=1M --size=8M --iodepth=1 || exit 1
    field=7
    [[ "$direction" == write ]] && field=48
    speed=$(terse_field "$field" "$WORK_DIR/fio-$direction.log")
    awk -v speed="$speed" 'BEGIN {exit !(speed > 0)}' || exit 1
done
printf 'PASS: real fio direct I/O and terse fields\n'

# A fake fetch isolates timeout/process-group handling from public upstreams.
export BENCH_CHILD_FILE="$WORK_DIR/child.pid"
curl() {
    cat >"${@: -1}" <<'UPSTREAM'
#!/usr/bin/env bash
sleep 30 &
child=$!
printf '%s' "$child" > "$BENCH_CHILD_FILE"
wait "$child"
UPSTREAM
}
run_external timeout-fixture 1 https://example.invalid/fixture.sh
[[ $FAILS -eq 1 && -s "$BENCH_CHILD_FILE" ]] || exit 1
child=$(cat "$BENCH_CHILD_FILE")
for (( attempt=0; attempt<30; attempt++ )); do
    state=$(ps -o stat= -p "$child" 2>/dev/null) || state=""
    [[ -z "$state" || "$state" == *Z* ]] && break
    sleep 0.1
done
[[ -z "$state" || "$state" == *Z* ]] || { printf 'Timeout left a live child process\n' >&2; exit 1; }
printf 'PASS: external timeout also terminates child processes\n'
