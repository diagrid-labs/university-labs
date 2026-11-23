#!/usr/bin/env bash
# Runs every workflow smoke test: demos 1-6 x dotnet, python, java, typescript.
# Usage: run-all.sh [--demo N] [--lang dotnet|python|java|typescript]
# A demo without a smoke script yet is reported as SKIP. Exits non-zero if any FAIL.

DIR="$(cd "$(dirname "$0")" && pwd)"
DEMOS="1 2 3 4 5 6"
LANGS="dotnet python java typescript"

usage() {
  echo "usage: run-all.sh [--demo 1-6] [--lang dotnet|python|java|typescript]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --demo)
      [ $# -ge 2 ] || usage
      case "$2" in [1-6]) DEMOS="$2" ;; *) usage ;; esac
      shift 2 ;;
    --lang)
      [ $# -ge 2 ] || usage
      case "$2" in dotnet|python|java|typescript) LANGS="$2" ;; *) usage ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done

RESULTS=""
FAILED=0
for demo in $DEMOS; do
  for lang in $LANGS; do
    script="$DIR/smoke-demo$demo.sh"
    if [ ! -f "$script" ]; then
      result="SKIP"
    elif bash "$script" "$lang"; then
      result="PASS"
    else
      result="FAIL"
      FAILED=1
    fi
    line="$result  demo$demo  $lang"
    echo "$line"
    RESULTS="$RESULTS$line
"
  done
done

echo
echo "==== Summary ===="
printf '%s' "$RESULTS"
exit "$FAILED"
