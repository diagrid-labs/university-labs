#!/usr/bin/env bash
# Smoke test for workflow Demo 3 (fan-out/fan-in): run one jump, check that all five sensor
# arrays logged their scan, that the fan-in output is right, and that the five 2-second scans
# ran in parallel (POST to COMPLETED in well under the 10 s a sequential run would take).
# Usage: smoke-demo3.sh dotnet|python|java|typescript
source "$(dirname "$0")/lib.sh" "$@"

assert_ports_free 5301 3530 50330

ENG="$(app_dir engineering)"
prepare_app "$(demo_dir 3)/$ENG"

start_demo "$(demo_dir 3)" 5301 3530 50330
wait_for_sidecar 3530

ID="$(new_jump_id 3)"
JUMPS="$ID"
START="$(python3 -c 'import time; print(time.time())')"
ID="$(start_jump "{\"jumpId\":\"$ID\"}")" || exit 1

# Poll every 0.2 s so the measured time is not rounded up to whole seconds.
i=0
while [ "$i" -lt 150 ]; do
  [ "$(jump_status "$ID")" = "COMPLETED" ] && break
  sleep 0.2
  i=$((i + 1))
done
ELAPSED="$(python3 -c "import time; print(round(time.time() - $START, 2))")"
[ "$(jump_status "$ID")" = "COMPLETED" ] || die "$ID not COMPLETED after 30s"
echo "PASS: $ID is COMPLETED"

# Parallelism: five sequential 2 s scans would take 10 s or more.
python3 -c "import sys; sys.exit(0 if $ELAPSED < 6 else 1)" || die "POST to COMPLETED took ${ELAPSED}s, expected under 6s (scans not parallel?)"
echo "PASS: POST to COMPLETED took ${ELAPSED}s (under 6s, the scans ran in parallel)"

# Every array logged its fixed hazard score, once.
for scan in alpha=12 beta=7 gamma=31 delta=4 epsilon=18; do
  assert_eq "1" "$(count_log "$ENG" engineering "engineering sensor array ${scan%=*} scanned hazard=${scan#*=}")" \
    "sensor array ${scan%=*} logged hazard=${scan#*=}"
done

# Fan-in: the highest score, and CLEAR below 50.
assert_eq '{"routeRisk":31,"verdict":"CLEAR"}' "$(jump_output "$ID")" "workflow output"

echo "Demo 3 ($LANG_ARG) smoke test passed"
