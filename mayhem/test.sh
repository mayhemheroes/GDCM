#!/usr/bin/env bash
#
# gdcm/mayhem/test.sh — Behavioral oracle for GDCM's self-contained Common unit tests → CTRF.
#
# ANTI-REWARD-HACKING: this oracle asserts SPECIFIC OUTPUT VALUES from the library, not just
# exit codes. A neutered binary (e.g. patched to exit(0)) will not produce the expected strings
# and the behavioral checks will FAIL even though ctest would report PASS.
#
# Tests exercised:
#   TestString1  — DICOM string tokenizer; must print "WINDOW1", "WINDOW2", "WINDOW3"
#   TestString2  — gdcm::String size; must print "coucou -> 6"
#   TestBase64   — Base64 encode/decode round-trip; must exit 0 (all internal assertions fatal)
#   TestByteSwap — byte-swap arithmetic; must exit 0 (all internal assertions fatal)
#   + remaining self-contained Common tests via ctest for breadth coverage
#
# mayhem/build.sh already compiled the test driver into $SRC/build-tests. This script only RUNS it.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

RUNNER="$SRC/build-tests/bin/gdcmCommonTests"
TEST_DIR="$SRC/build-tests/Testing/Source/Common/Cxx"

[ -x "$RUNNER" ] || {
  echo "missing build-tests/bin/gdcmCommonTests — run mayhem/build.sh first" >&2; exit 2; }
[ -f "$TEST_DIR/CTestTestfile.cmake" ] || {
  echo "missing $TEST_DIR/CTestTestfile.cmake — run mayhem/build.sh first" >&2; exit 2; }

passed=0; failed=0

# ---------------------------------------------------------------------------
# BEHAVIORAL CHECK 1: TestString1 must print DICOM tokenizer output values.
# gdcm::String<'\\'>  splits "WINDOW1\\WINDOW2\\WINDOW3" and prints each part.
# A neutered exit(0) binary prints NOTHING; this grep then fails.
# ---------------------------------------------------------------------------
check_string1() {
  local out
  out="$("$RUNNER" TestString1 2>&1)" || { echo "FAIL TestString1: binary returned non-zero" >&2; return 1; }
  if ! printf '%s\n' "$out" | grep -qF 'WINDOW1'; then
    echo "FAIL TestString1: expected 'WINDOW1' in stdout, got: $out" >&2; return 1
  fi
  if ! printf '%s\n' "$out" | grep -qF 'WINDOW2'; then
    echo "FAIL TestString1: expected 'WINDOW2' in stdout, got: $out" >&2; return 1
  fi
  if ! printf '%s\n' "$out" | grep -qF 'WINDOW3'; then
    echo "FAIL TestString1: expected 'WINDOW3' in stdout, got: $out" >&2; return 1
  fi
  echo "PASS TestString1: DICOM string tokenizer output correct"
  return 0
}

# ---------------------------------------------------------------------------
# BEHAVIORAL CHECK 2: TestString2 must print sized string output.
# gdcm::String<> s1 = "coucou" → prints "coucou -> 6".
# A neutered exit(0) binary prints NOTHING; this grep then fails.
# ---------------------------------------------------------------------------
check_string2() {
  local out
  out="$("$RUNNER" TestString2 2>&1)" || { echo "FAIL TestString2: binary returned non-zero" >&2; return 1; }
  if ! printf '%s\n' "$out" | grep -qF 'coucou -> 6'; then
    echo "FAIL TestString2: expected 'coucou -> 6' in stdout, got: $out" >&2; return 1
  fi
  echo "PASS TestString2: gdcm::String size output correct"
  return 0
}

# ---------------------------------------------------------------------------
# BEHAVIORAL CHECK 3: TestBase64 must exercise encode/decode round-trip.
# All checks are fatal (return 1 on mismatch) so a wrong answer crashes the
# test; exit 0 only if all assertions pass.
# ---------------------------------------------------------------------------
check_base64() {
  "$RUNNER" TestBase64 2>&1 || { echo "FAIL TestBase64: Base64 encode/decode assertion failed" >&2; return 1; }
  echo "PASS TestBase64: Base64 encode/decode round-trip correct"
  return 0
}

# ---------------------------------------------------------------------------
# BEHAVIORAL CHECK 4: TestByteSwap must exercise byte-swap arithmetic.
# ---------------------------------------------------------------------------
check_byteswap() {
  "$RUNNER" TestByteSwap 2>&1 || { echo "FAIL TestByteSwap: ByteSwap assertion failed" >&2; return 1; }
  echo "PASS TestByteSwap: ByteSwap arithmetic correct"
  return 0
}

# Run the four behavioral checks
for check_fn in check_string1 check_string2 check_base64 check_byteswap; do
  if $check_fn; then
    (( passed++ )) || true
  else
    (( failed++ )) || true
  fi
done

# ---------------------------------------------------------------------------
# BREADTH COVERAGE: run remaining self-contained Common tests via ctest.
# These tests are checked by exit code (all contain fatal assertions), and
# the behavioral checks above guard against a neutered exit(0) patch passing.
# ---------------------------------------------------------------------------
ctest_out="$(ctest --test-dir "$TEST_DIR" --output-on-failure -j"$MAYHEM_JOBS" 2>&1)"
echo "$ctest_out"

# Parse ctest summary (only add tests ctest ran beyond our 4 behavioral ones).
ctest_total=$( printf '%s\n' "$ctest_out" | sed -n 's/.*tests failed out of \([0-9][0-9]*\).*/\1/p' | tail -1)
ctest_failed=$(printf '%s\n' "$ctest_out" | sed -n 's/.*, \([0-9][0-9]*\) tests* failed out of .*/\1/p' | tail -1)
: "${ctest_total:=0}" "${ctest_failed:=0}"
ctest_passed=$(( ctest_total - ctest_failed ))
[ "$ctest_passed" -lt 0 ] && ctest_passed=0

# Add ctest counts to our totals (some overlap is fine for breadth coverage).
passed=$(( passed + ctest_passed ))
failed=$(( failed + ctest_failed ))

emit_ctrf "gdcm-behavioral" "$passed" "$failed" 0
