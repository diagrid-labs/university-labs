#!/usr/bin/env bash
# Smoke test for workflow Demo 2 (task chaining): run a jump through the four chained
# activities, check the log order and the output, the destination defaults, and what
# happens when a jump ID is reused.
# Usage: smoke-demo2.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 2)/$ENG"

start_demo "$(demo_dir 2)" 5301 3530 50330
wait_for_sidecar 3530

PLOTTED="engineering course plotted to Vesper Reach"
ARRIVED="engineering jump complete, arrived at Vesper Reach"

# Line number of the first line containing $1 in the newest engineering log.
log_line() {
  grep -nF -m1 -- "$1" "$(app_log "$ENG" engineering)" | cut -d: -f1
}

# The explicit destination.
ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 2)\",\"destination\":\"Vesper Reach\"}")" || exit 1
JUMPS="$ID"
wait_for_status "$ID" COMPLETED 60

# The four log lines come in chain order. This is the only jump so far, so each appears once.
L1="$(log_line "$PLOTTED heading=217 distanceLy=4.2")"
L2="$(log_line "engineering warp core charged to warp 6")"
L3="$(log_line "engineering nav array aligned")"
L4="$(log_line "$ARRIVED")"
[ -n "$L1" ] && [ -n "$L2" ] && [ -n "$L3" ] && [ -n "$L4" ] || die "a chain log line is missing ($L1 $L2 $L3 $L4)"
[ "$L1" -lt "$L2" ] && [ "$L2" -lt "$L3" ] && [ "$L3" -lt "$L4" ] || die "chain log lines out of order ($L1 $L2 $L3 $L4)"
echo "PASS: the four chain log lines are in order"

# The stardate is a number with at most one decimal (a whole number prints without ".0" in
# some languages).
OUTPUT="$(jump_output "$ID")"
echo "$OUTPUT" | grep -Eq '^\{"arrivedAt":"Vesper Reach","stardate":[0-9]+(\.[0-9])?\}$' \
  || die "workflow output '$OUTPUT' does not match the expected shape"
echo "PASS: workflow output $OUTPUT"

# Defaults: no body fields, a null destination and an empty destination all fly to Vesper Reach.
RESULT="$(post_json "$APP_URL/jumps" '{}')"
assert_eq "202" "${RESULT%% *}" "POST {} answers 202"
DEFAULT_ID="$(echo "${RESULT#* }" | json_field jumpId)"
JUMPS="$JUMPS $DEFAULT_ID"
echo "$DEFAULT_ID" | grep -Eq '^jump-[0-9a-f]{8}$' || die "generated jumpId '$DEFAULT_ID' is not jump-<8 hex>"
echo "PASS: generated jumpId $DEFAULT_ID"
wait_for_status "$DEFAULT_ID" COMPLETED 60
assert_eq "2" "$(count_log "$ENG" engineering "$PLOTTED")" "default destination plots to Vesper Reach"

NULL_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 2)-null\",\"destination\":null}")" || exit 1
JUMPS="$JUMPS $NULL_ID"
wait_for_status "$NULL_ID" COMPLETED 60
assert_eq "3" "$(count_log "$ENG" engineering "$PLOTTED")" "null destination plots to Vesper Reach"

EMPTY_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 2)-empty\",\"destination\":\"\"}")" || exit 1
JUMPS="$JUMPS $EMPTY_ID"
wait_for_status "$EMPTY_ID" COMPLETED 60
assert_eq "4" "$(count_log "$ENG" engineering "$PLOTTED")" "empty destination plots to Vesper Reach"

# Another destination is used as given.
OTHER_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 2)-other\",\"destination\":\"Calder Station\"}")" || exit 1
JUMPS="$JUMPS $OTHER_ID"
wait_for_status "$OTHER_ID" COMPLETED 60
assert_eq "{\"arrivedAt\":\"Calder Station\"" "$(jump_output "$OTHER_ID" | cut -d, -f1)" "destination is passed down the chain"

# A running jump's ID is taken: the start call fails.
RUNNING_ID="$(start_jump "{\"jumpId\":\"$(new_jump_id 2)-running\"}")" || exit 1
JUMPS="$JUMPS $RUNNING_ID"
RESULT="$(post_json "$APP_URL/jumps" "{\"jumpId\":\"$RUNNING_ID\"}")"
assert_eq '500 {"error":"WORKFLOW_ERROR"}' "$RESULT" "reusing a running jump ID answers 500 WORKFLOW_ERROR"
wait_for_status "$RUNNING_ID" COMPLETED 60

# A finished jump's ID can be reused: the jump starts over and runs the chain again.
BEFORE="$(count_log "$ENG" engineering "$ARRIVED")"
RESULT="$(post_json "$APP_URL/jumps" "{\"jumpId\":\"$ID\"}")"
assert_eq "202 {\"jumpId\":\"$ID\"}" "$RESULT" "reusing a finished jump ID answers 202"
i=0
while [ "$(count_log "$ENG" engineering "$ARRIVED")" -le "$BEFORE" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
[ "$(count_log "$ENG" engineering "$ARRIVED")" -gt "$BEFORE" ] || die "the reused jump ID did not run the chain again"
wait_for_status "$ID" COMPLETED 60
echo "PASS: the finished jump ran again"

echo "Demo 2 ($LANG_ARG) smoke test passed"
