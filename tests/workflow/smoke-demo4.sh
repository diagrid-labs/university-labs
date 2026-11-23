#!/usr/bin/env bash
# Smoke test for workflow Demo 4 (monitor): a workflow that checks the core temperature, waits on
# a durable timer and continues as new. The app is stopped during a timer wait, and the monitor
# must pick up after the restart and still run each check once.
# Usage: smoke-demo4.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 4)/$ENG"

# The check log lines don't carry the jump ID, and logs of earlier runs stay in .dapr/logs.
# Remove them so the counts below only see this run (.dapr is git-ignored).
rm -f "$(demo_dir 4)/$ENG"/.dapr/logs/engineering_app_*.log

start_demo "$(demo_dir 4)" 5301 3530 50330
wait_for_sidecar 3530

ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 4)\"}")" || exit 1
JUMPS="$ID"

# poll_until_done <jumpId> <deadline-epoch>: the status is RUNNING for the whole monitor run, also between runs
# (continue-as-new) and while a run is scheduled. Anything else but COMPLETED fails.
# Prints the last status it saw.
poll_until_done() {
  local id="$1" deadline="$2" now status=""
  while true; do
    status="$(jump_status "$id")"
    case "$status" in
      RUNNING|COMPLETED) ;;
      *) die "status of $id was '$status' during the monitor run, expected RUNNING" ;;
    esac
    [ "$status" = "COMPLETED" ] && { echo COMPLETED; return 0; }
    now="$(date +%s)"
    [ "$now" -lt "$deadline" ] || { echo "$status"; return 0; }
    sleep 0.5
  done
}

# Poll the status until check 2 has been logged (first check ran, timer started, continue-as-new).
i=0
while ! grep -qF "engineering core temperature check 2: 1180K" "$(app_log "$ENG" engineering)" 2>/dev/null; do
  [ "$i" -lt 120 ] || die "check 2 not logged after 60s"
  status="$(jump_status "$ID")"
  [ "$status" = "RUNNING" ] || die "status of $ID was '$status' before check 2, expected RUNNING"
  sleep 0.5
  i=$((i + 1))
done
echo "PASS: status stays RUNNING while the monitor waits"

# The crash: stop the app and its sidecar while the durable timer after check 2 is waiting.
stop_demo
start_demo "$(demo_dir 4)" 5301 3530 50330
wait_for_sidecar 3530

done_status="$(poll_until_done "$ID" "$(( $(date +%s) + 90 ))")"
assert_eq "COMPLETED" "$done_status" "monitor completes after the restart, status RUNNING until then"

# The restart splits the logs over two files, so count over all of them.
all_logs="$(ls "$(demo_dir 4)/$ENG"/.dapr/logs/engineering_app_*.log)"
for line in "1:1240" "2:1180" "3:1120" "4:1060" "5:1000"; do
  count="$(cat $all_logs | grep -cF "engineering core temperature check ${line%%:*}: ${line##*:}K")"
  assert_eq "1" "$count" "check ${line%%:*} (${line##*:}K) logged once across the restart"
done
assert_eq "0" "$(cat $all_logs | grep -cF "engineering core temperature check 6:")" "no check after the core is stable"
assert_eq '{"stable":true,"checks":5,"coreTempK":1000}' "$(jump_output "$ID")" "workflow output"

echo "Demo 4 ($LANG_ARG) smoke test passed"
