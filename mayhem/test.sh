#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

ORACLE="$SRC/build/oracle"
[ -d "$ORACLE" ] || { echo "missing $ORACLE (mayhem/build.sh should have built it)" >&2; emit_ctrf cmake-ctest 0 1 0; exit 1; }

# Known-answer probes: run the built example programs directly and compare their exact output.
probe_fail=0
probe() {  # probe <expected> <cmd...>
  local want="$1" got; shift
  got="$("$@" 2>&1)" || true
  if [ "$got" != "$want" ]; then
    echo "KAT FAIL: $* -> [$got], wanted [$want]" >&2
    probe_fail=$((probe_fail + 1))
  fi
}
probe "My name (spelled backwards) is: ekim" "$ORACLE/examples/test1" -r -n mike
probe "My name is: mike" "$ORACLE/examples/test1" -n mike
probe "My name (spelled backwards) is: cba" "$ORACLE/examples/test1" --reverse --name abc
probe "My name is: a b" "$ORACLE/examples/test1" -n "a b"
probe_total=4

# The project's own suite: unit tests plus the examples' golden-output diffs (tests/*.py vs *.out).
out="$(cd "$ORACLE" && ctest -j"$MAYHEM_JOBS" 2>&1)"
echo "$out" | tail -n 12
summary="$(echo "$out" | grep -E 'tests passed, [0-9]+ tests failed out of [0-9]+' | tail -n1)"
total="$(echo "$summary" | sed -nE 's/.*out of ([0-9]+).*/\1/p')"
failed="$(echo "$summary" | sed -nE 's/.*, ([0-9]+) tests failed out of.*/\1/p')"
if [ -z "$total" ] || [ "$total" -lt 100 ]; then
  echo "ctest ran no/too few tests (got '${total:-none}', expected >=100)" >&2
  emit_ctrf cmake-ctest 0 1 0
  exit 1
fi
passed=$(( total - failed ))
emit_ctrf cmake-ctest $(( passed + probe_total - probe_fail )) $(( failed + probe_fail )) 0
