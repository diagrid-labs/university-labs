#!/usr/bin/env bash
# Smoke test for workflow Demo 5 (human in the loop): three jumps wait for the captain. One is
# approved, one is denied and one times out. Then a late authorize on the timed-out jump and
# an authorize on an unknown jump are rejected.
# Usage: smoke-demo5.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 5)/$ENG"

start_demo "$(demo_dir 5)" 5301 3530 50330
wait_for_sidecar 3530

CAPTAIN="Captain Ilsa Varn"

# The timeout jump goes first, so its 60 s wait runs while the other two are tested.
TIMEOUT_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 5)-timeout\"}")" || exit 1
JUMPS="$TIMEOUT_ID"

# Approved: the jump waits, the captain approves, the jump engages.
APPROVED_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 5)-approved\"}")" || exit 1
JUMPS="$JUMPS $APPROVED_ID"
wait_for_log "$ENG" engineering "engineering $APPROVED_ID awaiting captain's authorization" 30
assert_eq "RUNNING" "$(jump_status "$APPROVED_ID")" "the jump waits for the captain"
RESULT="$(post_json "$APP_URL/jumps/$APPROVED_ID/authorize" "{\"approved\":true,\"officer\":\"$CAPTAIN\"}")"
assert_eq "202 " "$RESULT" "authorize answers 202"
wait_for_status "$APPROVED_ID" COMPLETED 30
assert_eq "{\"status\":\"JUMPED\",\"authorizedBy\":\"$CAPTAIN\"}" "$(jump_output "$APPROVED_ID")" "approved jump output"
assert_eq "1" "$(count_log "$ENG" engineering "engineering jump complete, arrived at Vesper Reach")" "the approved jump engaged"

# Denied: no engage.
DENIED_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 5)-denied\"}")" || exit 1
JUMPS="$JUMPS $DENIED_ID"
wait_for_log "$ENG" engineering "engineering $DENIED_ID awaiting captain's authorization" 30
RESULT="$(post_json "$APP_URL/jumps/$DENIED_ID/authorize" "{\"approved\":false,\"officer\":\"$CAPTAIN\"}")"
assert_eq "202 " "$RESULT" "authorize (denied) answers 202"
wait_for_status "$DENIED_ID" COMPLETED 30
assert_eq "{\"status\":\"DENIED\",\"authorizedBy\":\"$CAPTAIN\"}" "$(jump_output "$DENIED_ID")" "denied jump output"
assert_eq "1" "$(count_log "$ENG" engineering "engineering jump complete, arrived at Vesper Reach")" "the denied jump did not engage"

# Unknown jump.
RESULT="$(post_json "$APP_URL/jumps/smoke-d5-unknown/authorize" "{\"approved\":true,\"officer\":\"$CAPTAIN\"}")"
assert_eq '404 {"error":"JUMP_NOT_FOUND"}' "$RESULT" "authorize on an unknown jump answers 404"

# Timeout: nobody answers within 60 s.
wait_for_log "$ENG" engineering "engineering $TIMEOUT_ID awaiting captain's authorization" 30
wait_for_status "$TIMEOUT_ID" COMPLETED 90
assert_eq '{"status":"ABORTED_NO_AUTHORIZATION"}' "$(jump_output "$TIMEOUT_ID")" "timed-out jump output"

# Late authorize: the jump is finished. A raised event would stall the instance (Dapr 1.19.1),
# so the app answers 409 and raises nothing.
RESULT="$(post_json "$APP_URL/jumps/$TIMEOUT_ID/authorize" "{\"approved\":true,\"officer\":\"$CAPTAIN\"}")"
assert_eq '409 {"error":"JUMP_FINISHED"}' "$RESULT" "late authorize answers 409"
assert_eq '{"status":"ABORTED_NO_AUTHORIZATION"}' "$(jump_output "$TIMEOUT_ID")" "the late authorize did not change the output"
assert_eq "COMPLETED" "$(jump_status "$TIMEOUT_ID")" "the timed-out jump is still COMPLETED"
assert_eq "COMPLETED" "$(cli_status "$TIMEOUT_ID")" "the timed-out jump is not stalled"

# The awaiting line is replay-safe: once per jump, also after the jump replayed.
for id in "$APPROVED_ID" "$DENIED_ID" "$TIMEOUT_ID"; do
  assert_eq "1" "$(count_log "$ENG" engineering "engineering $id awaiting captain's authorization")" "$id logged the awaiting line once"
done

echo "Demo 5 ($LANG_ARG) smoke test passed"
