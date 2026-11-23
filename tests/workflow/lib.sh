#!/usr/bin/env bash
# Shared helpers for the workflow smoke tests. Source it from a smoke script:
#
#   source "$(dirname "$0")/lib.sh" "$@"
#
# Usage: start_demo <demo-dir> [port...] passes the demo's ports (app, Dapr HTTP and Dapr
# gRPC) so stop_demo can verify they are free afterwards and kill leftovers.
#
# Every jump a smoke script starts goes into JUMPS (JUMPS="$JUMPS $ID"). On exit, pass or
# fail, the EXIT trap set by start_demo terminates and purges those jumps while the sidecar
# is still up (the `dapr workflow` CLI needs it), and only then stops the demo. That keeps
# Redis clean for the next test, since every language and demo shares the app ID
# `engineering`.
#
# Works with bash 3.2 (macOS) and Linux. Every helper that fails prints a message to
# stderr and exits non-zero.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

LANG_ARG="${1:-}"
case "$LANG_ARG" in
  dotnet|python|java|typescript) ;;
  *) echo "usage: $(basename "$0") dotnet|python|java|typescript" >&2; exit 2 ;;
esac

APP_URL="http://localhost:5301"

# Folder names differ per language: .NET uses PascalCase (Demo1-DurableExecution/Engineering),
# Python, Java and TypeScript use kebab-case (demo1-durable-execution/engineering).

# demo_dir <N>: prints the absolute path of workflow demo N for $LANG_ARG.
demo_dir() {
  local dotnet kebab
  case "$1" in
    1) dotnet=Demo1-DurableExecution; kebab=demo1-durable-execution ;;
    2) dotnet=Demo2-TaskChaining;     kebab=demo2-task-chaining ;;
    3) dotnet=Demo3-FanOutFanIn;      kebab=demo3-fan-out-fan-in ;;
    4) dotnet=Demo4-Monitor;          kebab=demo4-monitor ;;
    5) dotnet=Demo5-HumanInTheLoop;   kebab=demo5-human-in-the-loop ;;
    6) dotnet=Demo6-Management;       kebab=demo6-management ;;
    *) die "unknown demo $1" ;;
  esac
  if [ "$LANG_ARG" = "dotnet" ]; then
    echo "$ROOT/workflow/dotnet/$dotnet"
  else
    echo "$ROOT/workflow/$LANG_ARG/$kebab"
  fi
}

# app_dir <app-id>: prints the folder name of an app for $LANG_ARG. Python, Java and
# TypeScript folders are named after the app id; .NET folders after the project.
app_dir() {
  [ "$LANG_ARG" = "dotnet" ] || { echo "$1"; return 0; }
  case "$1" in
    engineering) echo Engineering ;;
    *) die "unknown app $1" ;;
  esac
}

# prepare_app <app-dir>: installs dependencies where `dapr run` doesn't. Only TypeScript
# needs it (npm ci); dotnet run, uv run and mvn restore on their own.
prepare_app() {
  [ "$LANG_ARG" = "typescript" ] || return 0
  [ -d "$1" ] || die "app dir $1 does not exist"
  (cd "$1" && npm ci --no-audit --no-fund --loglevel=error >/dev/null) || die "npm ci failed in $1"
}

DEMO_DIR=""
DEMO_PID=""
DEMO_PORTS=""
JUMPS=""

die() {
  echo "FAIL: $*" >&2
  exit 1
}

port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    nc -z localhost "$1" >/dev/null 2>&1
  fi
}

assert_ports_free() {
  local p
  for p in "$@"; do
    if port_in_use "$p"; then
      die "port $p is already in use"
    fi
  done
}

# Resolves an app dir: absolute paths stay as they are, relative ones are relative to
# the demo dir given to start_demo.
resolve_dir() {
  case "$1" in
    /*) echo "$1" ;;
    *) echo "${DEMO_DIR:-.}/$1" ;;
  esac
}

# start_demo <demo-dir> [port...]
# The optional ports are remembered so stop_demo can wait for them to close and kill
# whatever still holds them.
start_demo() {
  [ -d "$1" ] || die "demo dir $1 does not exist"
  DEMO_DIR="$(cd "$1" && pwd)"
  shift
  DEMO_PORTS="$*"
  mkdir -p "$DEMO_DIR/.dapr"
  cd "$DEMO_DIR" || die "cannot cd to $DEMO_DIR"
  dapr run -f . >"$DEMO_DIR/.dapr/smoke-run.log" 2>&1 &
  DEMO_PID=$!
  trap finish EXIT
}

# EXIT trap: clean up the test's jumps first (needs the sidecar), then stop the demo.
finish() {
  local id
  trap - EXIT
  for id in $JUMPS; do
    cleanup_jump "$id"
  done
  stop_demo
}

# Kills a process and all its descendants.
kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    kill_tree "$child"
  done
  kill "$1" >/dev/null 2>&1
}

ports_busy() {
  local p busy=""
  for p in $DEMO_PORTS; do
    port_in_use "$p" && busy="$busy $p"
  done
  echo "${busy# }"
}

# Stops the demo and makes sure its ports are free: dapr stop, then wait up to 15 s,
# then kill the process tree and whatever still listens on the demo's ports.
# Smoke scripts also call it on its own to simulate a crash.
stop_demo() {
  local dir="${1:-$DEMO_DIR}" i=0 busy p pid
  trap - EXIT
  [ -n "$dir" ] && (cd "$dir" && dapr stop -f . >/dev/null 2>&1)
  if [ -n "$DEMO_PID" ]; then
    kill_tree "$DEMO_PID"
    wait "$DEMO_PID" >/dev/null 2>&1
    DEMO_PID=""
  fi
  while [ "$i" -lt 15 ] && [ -n "$(ports_busy)" ]; do
    sleep 1
    i=$((i + 1))
  done
  busy="$(ports_busy)"
  if [ -n "$busy" ]; then
    for p in $busy; do
      for pid in $(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null); do
        kill_tree "$pid"
      done
    done
    sleep 2
    busy="$(ports_busy)"
    for p in $busy; do
      for pid in $(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null); do
        kill -9 "$pid" >/dev/null 2>&1
      done
    done
    sleep 1
    busy="$(ports_busy)"
    [ -n "$busy" ] && echo "WARNING: port(s) $busy still in use after stop_demo; kill the leaked process manually" >&2
  fi
  return 0
}

demo_log_tail() {
  if [ -n "$DEMO_DIR" ] && [ -f "$DEMO_DIR/.dapr/smoke-run.log" ]; then
    echo "---- last 40 lines of $DEMO_DIR/.dapr/smoke-run.log ----" >&2
    tail -n 40 "$DEMO_DIR/.dapr/smoke-run.log" >&2
  fi
}

# Fails fast if `dapr run` dies; on any failure shows the tail of smoke-run.log.
wait_for_sidecar() {
  local port="$1" timeout="${2:-180}" i=0 status
  while [ "$i" -lt "$timeout" ]; do
    status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/v1.0/healthz" 2>/dev/null)"
    [ "$status" = "204" ] && return 0
    if [ -n "$DEMO_PID" ] && ! kill -0 "$DEMO_PID" 2>/dev/null; then
      demo_log_tail
      die "dapr run exited before the sidecar on port $port became healthy"
    fi
    # `dapr run` stays alive when only the app fails to start, so also look for its message.
    if grep -q "The App process exited" "$DEMO_DIR/.dapr/smoke-run.log" 2>/dev/null; then
      demo_log_tail
      die "the app process exited before the sidecar on port $port became healthy"
    fi
    sleep 1
    i=$((i + 1))
  done
  demo_log_tail
  die "Dapr sidecar on port $port not healthy after ${timeout}s"
}

# Prints the newest app log (not the daprd log) of an app.
app_log() {
  local dir
  dir="$(resolve_dir "$1")"
  # shellcheck disable=SC2012
  ls -t "$dir"/.dapr/logs/"$2"_app_*.log 2>/dev/null | head -n 1
}

wait_for_log() {
  local dir="$1" app="$2" needle="$3" timeout="${4:-60}" i=0 log
  while [ "$i" -lt "$timeout" ]; do
    log="$(app_log "$dir" "$app")"
    if [ -n "$log" ] && grep -qF -- "$needle" "$log"; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  die "'$needle' not found in $app log after ${timeout}s"
}

count_log() {
  local log
  log="$(app_log "$1" "$2")"
  if [ -z "$log" ]; then
    echo 0
    return 0
  fi
  grep -cF -- "$3" "$log"
  return 0
}

# assert_last_log_is_warning <app-dir> <app> <needle> <message>
# Checks the log level of the newest line containing <needle>. Each language prints the level
# its own way: Python "WARNING:<logger>:", Spring Boot " WARN ", the .NET console logger
# "warn: <category>" on the line before the message, and Node's console.warn nothing at all
# (so TypeScript is not checked).
assert_last_log_is_warning() {
  local log level
  [ "$LANG_ARG" = "typescript" ] && { echo "PASS: $4 (level not checked for typescript)"; return 0; }
  log="$(app_log "$1" "$2")"
  [ -n "$log" ] || die "$4 (no $2 log)"
  level="$(awk -v needle="$3" '
    index($0, needle) { line = $0; before = prev }
    { prev = $0 }
    END {
      if (line ~ /WARNING:/ || line ~ / WARN / || before ~ /warn: /) print "WARNING"
      else print "NOT WARNING"
    }' "$log")"
  assert_eq "WARNING" "$level" "$4"
}

# Prints "<status> <body>".
post_json() {
  local out status body
  out="$(curl -s --max-time 30 -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d "$2" "$1")" \
    || die "POST $1 failed"
  status="$(echo "$out" | tail -n 1)"
  body="$(echo "$out" | sed '$d')"
  echo "$status $body"
}

assert_eq() {
  [ "$1" = "$2" ] || die "$3 (expected '$1', got '$2')"
  echo "PASS: $3"
}

# Prints "<status> <body>".
get_json() {
  local out status body
  out="$(curl -s --max-time 30 -w '\n%{http_code}' "$1")" || die "GET $1 failed"
  status="$(echo "$out" | tail -n 1)"
  body="$(echo "$out" | sed '$d')"
  echo "$status $body"
}

# json_field <field>: reads a JSON object on stdin and prints one field as compact JSON
# (strings without quotes). Keeps the key order of nested objects.
json_field() {
  python3 -c '
import json, sys
value = json.load(sys.stdin)[sys.argv[1]]
print(value if isinstance(value, str) else json.dumps(value, separators=(",", ":")))
' "$1"
}

# new_jump_id <demo>: a jump ID no earlier run has used.
new_jump_id() {
  echo "smoke-d$1-$LANG_ARG-$(date +%s)"
}

# start_jump <json-body>: POST /jumps, expects 202, prints the jumpId.
start_jump() {
  local result
  result="$(post_json "$APP_URL/jumps" "$1")"
  [ "${result%% *}" = "202" ] || die "POST /jumps $1 answered '$result', expected 202"
  echo "${result#* }" | json_field jumpId
}

# jump_status <jumpId>: prints the status field of GET /jumps/{jumpId}, or the HTTP status
# code when it isn't 200.
jump_status() {
  local result
  result="$(get_json "$APP_URL/jumps/$1")"
  if [ "${result%% *}" = "200" ]; then
    echo "${result#* }" | json_field status
  else
    echo "HTTP ${result%% *}"
  fi
}

# wait_for_status <jumpId> <STATUS> [timeout=60]
wait_for_status() {
  local id="$1" want="$2" timeout="${3:-60}" i=0 status=""
  while [ "$i" -lt "$timeout" ]; do
    status="$(jump_status "$id")"
    [ "$status" = "$want" ] && { echo "PASS: $id is $want"; return 0; }
    sleep 1
    i=$((i + 1))
  done
  die "$id not $want after ${timeout}s (last status: $status)"
}

# jump_output <jumpId>: prints the output field of GET /jumps/{jumpId} as compact JSON.
jump_output() {
  local result
  result="$(get_json "$APP_URL/jumps/$1")"
  [ "${result%% *}" = "200" ] || die "GET /jumps/$1 answered '$result'"
  echo "${result#* }" | json_field output
}

# cli_status <jumpId>: the runtime status the Dapr CLI reports, empty if the jump is unknown.
# (`dapr workflow list` can't combine a status filter with `-o ids`, so read the JSON.)
cli_status() {
  dapr workflow list -a engineering -o json 2>/dev/null | python3 -c '
import json, sys
try:
    rows = json.load(sys.stdin)
except ValueError:
    rows = []
print(next((r["runtimeStatus"] for r in rows if r["instanceID"] == sys.argv[1]), ""))
' "$1"
}

# with_timeout <seconds> <command...>: runs a command and kills it if it hasn't finished in
# time (macOS has no `timeout`). Returns the command's exit code, or 1 if it was killed.
with_timeout() {
  local secs="$1" pid i=0
  shift
  "$@" >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$secs" ]; then
      kill "$pid" >/dev/null 2>&1
      wait "$pid" >/dev/null 2>&1
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  wait "$pid"
}

# cleanup_jump <jumpId>: removes the jump from the state store. Uses the Dapr CLI, which talks
# to the running sidecar. A running or suspended jump is terminated first, then purged. A
# PENDING jump (scheduled, never started) can hang a terminate, so it is force-purged. A
# finished jump is never terminated: a control call on a finished workflow stalls it (Dapr
# 1.19.1), and a stalled instance can only be purged with --force.
cleanup_jump() {
  local id="$1" i=0
  case "$(cli_status "$id")" in
    "") return 0 ;;
    PENDING)
      with_timeout 15 dapr workflow purge "$id" --force -a engineering \
        || echo "WARNING: could not purge $id; run: dapr workflow purge $id --force -a engineering" >&2
      return 0
      ;;
    RUNNING|SUSPENDED)
      with_timeout 15 dapr workflow terminate "$id" -a engineering
      # Terminate is asynchronous; purge only works once the jump is TERMINATED.
      while [ "$i" -lt 15 ] && [ "$(cli_status "$id")" != "TERMINATED" ]; do
        sleep 1
        i=$((i + 1))
      done
      ;;
  esac
  with_timeout 15 dapr workflow purge "$id" -a engineering \
    || echo "WARNING: could not purge $id; run: dapr workflow purge $id --force -a engineering" >&2
  return 0
}
