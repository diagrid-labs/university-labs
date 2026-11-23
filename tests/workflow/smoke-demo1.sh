#!/usr/bin/env bash
# Smoke test for workflow Demo 1 (durable execution): start a jump, stop the app and sidecar
# in the middle of it, start them again and check the jump finishes without redoing the
# stages that had completed.
# Usage: smoke-demo1.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 1)/$ENG"

start_demo "$(demo_dir 1)" 5301 3530 50330
wait_for_sidecar 3530

assert_eq "404" "$(get_json $APP_URL/jumps/does-not-exist | cut -d' ' -f1)" "unknown jump is 404"

ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 1)\"}")" || exit 1
JUMPS="$ID"
wait_for_log "$ENG" engineering "engineering $ID charge sequence started" 120
wait_for_log "$ENG" engineering "engineering charge stage 2/5 complete for $ID" 30

# The crash: stop the app and its sidecar while stage 3 is running.
stop_demo
start_demo "$(demo_dir 1)" 5301 3530 50330
wait_for_sidecar 3530
wait_for_status "$ID" COMPLETED 90

# count_log reads the newest app log, which is the run after the restart.
assert_eq "0" "$(count_log "$ENG" engineering "charge stage 1/5 complete for $ID")" "stage 1 not rerun after restart"
assert_eq "0" "$(count_log "$ENG" engineering "$ID charge sequence started")" "replay-safe log did not repeat"
assert_eq "1" "$(count_log "$ENG" engineering "charge stage 5/5 complete for $ID")" "stage 5 ran once after restart"
assert_eq "{\"jumpId\":\"$ID\",\"coreCharged\":true}" "$(jump_output "$ID")" "workflow output"

echo "Demo 1 ($LANG_ARG) smoke test passed"
