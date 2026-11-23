#!/usr/bin/env bash
# Smoke test for workflow Demo 6 (management): pause, resume, terminate and purge a 10-leg jump.
# Usage: smoke-demo6.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 6)/$ENG"

# Prints "<status> <body>".
delete_json() {
  local out status body
  out="$(curl -s --max-time 30 -w '\n%{http_code}' -X DELETE "$1")" || die "DELETE $1 failed"
  status="$(echo "$out" | tail -n 1)"
  body="$(echo "$out" | sed '$d')"
  echo "$status $body"
}

legs() { count_log "$ENG" engineering "engineering $1 leg "; }

# settled_legs <jumpId>: the leg count once it has stopped changing for 2 s. A leg activity that
# was already running when the jump was paused or terminated may still log after that.
settled_legs() {
  local before after i=0
  after="$(legs "$1")"
  while [ "$i" -lt 10 ]; do
    sleep 2
    before="$after"
    after="$(legs "$1")"
    [ "$before" = "$after" ] && { echo "$after"; return 0; }
    i=$((i + 1))
  done
  die "the leg count of $1 kept changing"
}

start_demo "$(demo_dir 6)" 5301 3530 50330
wait_for_sidecar 3530

# Jump A: pause and resume.
A="$(start_jump "{\"jumpId\":\"$(new_jump_id 6)-a\"}")" || exit 1
JUMPS="$A"
wait_for_log "$ENG" engineering "engineering $A leg 2/10 complete" 30
assert_eq "RUNNING" "$(jump_status "$A")" "the jump is RUNNING"

RESULT="$(post_json "$APP_URL/jumps/$A/pause" "")"
assert_eq "202 " "$RESULT" "pause answers 202"
wait_for_status "$A" SUSPENDED 15
BEFORE="$(settled_legs "$A")" || exit 1
sleep 12
assert_eq "$BEFORE" "$(legs "$A")" "no legs while the jump is paused"

RESULT="$(post_json "$APP_URL/jumps/$A/resume" "")"
assert_eq "202 " "$RESULT" "resume answers 202"
wait_for_status "$A" RUNNING 15
wait_for_log "$ENG" engineering "engineering $A leg $((BEFORE + 1))/10 complete" 15
echo "PASS: the jump continued with leg $((BEFORE + 1))"

# Purge on a running jump fails: the history of a running workflow can't be removed.
RESULT="$(delete_json "$APP_URL/jumps/$A")"
assert_eq '500 {"error":"WORKFLOW_ERROR"}' "$RESULT" "purge of a running jump answers 500"
assert_eq "RUNNING" "$(jump_status "$A")" "the jump is still RUNNING after the purge attempt"

# Jump B: terminate.
B="$(start_jump "{\"jumpId\":\"$(new_jump_id 6)-b\"}")" || exit 1
JUMPS="$JUMPS $B"
wait_for_log "$ENG" engineering "engineering $B leg 1/10 complete" 30
RESULT="$(post_json "$APP_URL/jumps/$B/terminate" "")"
assert_eq "202 " "$RESULT" "terminate answers 202"
wait_for_status "$B" TERMINATED 15
BEFORE="$(settled_legs "$B")" || exit 1
sleep 10
assert_eq "$BEFORE" "$(legs "$B")" "no legs after terminate"

# Pause on a finished jump: 409, and the app still answers GET.
RESULT="$(post_json "$APP_URL/jumps/$B/pause" "")"
assert_eq '409 {"error":"JUMP_FINISHED"}' "$RESULT" "pause on a terminated jump answers 409"
assert_eq "TERMINATED" "$(jump_status "$B")" "the app still answers GET for the terminated jump"

# Unknown jump.
for action in pause resume terminate; do
  RESULT="$(post_json "$APP_URL/jumps/smoke-d6-unknown/$action" "")"
  assert_eq '404 {"error":"JUMP_NOT_FOUND"}' "$RESULT" "$action on an unknown jump answers 404"
done
RESULT="$(delete_json "$APP_URL/jumps/smoke-d6-unknown")"
assert_eq '404 {"error":"JUMP_NOT_FOUND"}' "$RESULT" "purge of an unknown jump answers 404"

# Purge the terminated jump: 204, then the history is gone.
RESULT="$(delete_json "$APP_URL/jumps/$B")"
assert_eq "204 " "$RESULT" "purge answers 204"
RESULT="$(get_json "$APP_URL/jumps/$B")"
assert_eq '404 {"error":"JUMP_NOT_FOUND"}' "$RESULT" "GET after purge answers 404"

# Clean up A through the endpoints. On a slow run A may have completed by now; then terminate
# answers 409 and A can be purged straight away.
RESULT="$(post_json "$APP_URL/jumps/$A/terminate" "")"
case "$RESULT" in
  "202 ") echo "PASS: terminate (cleanup) answers 202"; wait_for_status "$A" TERMINATED 15 ;;
  '409 {"error":"JUMP_FINISHED"}') echo "PASS: terminate (cleanup) answers 409, $A already completed" ;;
  *) die "terminate (cleanup) answered '$RESULT', expected 202 or 409" ;;
esac
RESULT="$(delete_json "$APP_URL/jumps/$A")"
assert_eq "204 " "$RESULT" "purge (cleanup) answers 204"

echo "Demo 6 ($LANG_ARG) smoke test passed"
