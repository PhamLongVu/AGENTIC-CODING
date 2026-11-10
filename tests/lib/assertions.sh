#!/usr/bin/env bash
# Minimal assertion library for the bash+curl test suites.
# Usage: source tests/lib/assertions.sh ; run asserts ; call finish_suite
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0

_t_ok()   { TESTS_RUN=$((TESTS_RUN+1)); echo "  ok  - $1"; }
_t_fail() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); echo "  FAIL- $1"; }

assert_eq() {  # <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then _t_ok "$3"; else _t_fail "$3 (expected '$2', got '$1')"; fi
}
assert_contains() {  # <haystack> <needle> <label>
  if [[ "$1" == *"$2"* ]]; then _t_ok "$3"; else _t_fail "$3 (missing '$2' in: ${1:0:200})"; fi
}
assert_not_contains() {  # <haystack> <needle> <label>
  if [[ "$1" != *"$2"* ]]; then _t_ok "$3"; else _t_fail "$3 (unexpectedly found '$2')"; fi
}
assert_file_exists() {
  if [[ -f "$1" ]]; then _t_ok "file exists: $1"; else _t_fail "file exists: $1"; fi
}
assert_cmd() {  # <label> <command...>
  local label="$1"; shift
  if out="$("$@" 2>&1)"; then _t_ok "$label"; else _t_fail "$label (output: ${out:0:200})"; fi
}
assert_cmd_fails() {  # <label> <command...>  — succeeds when the command fails
  local label="$1"; shift
  if out="$("$@" 2>&1)"; then _t_fail "$label (unexpectedly succeeded: ${out:0:200})"; else _t_ok "$label"; fi
}

finish_suite() {  # <suite-name>
  echo ""
  echo "$1: $((TESTS_RUN-TESTS_FAILED))/$TESTS_RUN assertions passed"
  if [[ $TESTS_FAILED -gt 0 ]]; then exit 1; fi
  exit 0
}
