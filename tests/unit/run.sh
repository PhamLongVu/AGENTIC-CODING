#!/usr/bin/env bash
# Static/unit checks that need no running stack:
#   compose file parses; env contract complete; versions pinned; scripts
#   syntactically valid; no secrets in tracked files.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/assertions.sh

echo "== unit: compose config parse =="
# .env may not exist in CI contexts: synthesize one from the template.
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT
sed -e 's/=CHANGE_ME.*/=dummy-value-not-a-secret/' .env.example > "$TMP_ENV"
echo "DOCKER_GID=0" >> "$TMP_ENV"

out="$(docker compose --env-file "$TMP_ENV" -f docker-compose.yml config -q 2>&1 && echo OK)"
assert_contains "$out" "OK" "docker-compose.yml parses with .env.example values"

echo "== unit: every compose-interpolated variable is declared in .env.example =="
used_vars="$(grep -oE '\$\{[A-Z_][A-Z0-9_]*' docker-compose.yml | sed 's/^\${//' | sort -u)"
n_vars="$(echo "$used_vars" | wc -l)"
missing=0
for v in $used_vars; do
  if ! grep -qE "^${v}=" .env.example && ! grep -qE "^${v}=" "$TMP_ENV"; then
    _t_fail ".env.example missing variable $v"
    missing=1
  fi
done
[[ $missing -eq 0 ]] && _t_ok "all $n_vars interpolated variables declared"

echo "== unit: image versions pinned (no latest) =="
for img_var in POSTGRES_IMAGE LITELLM_IMAGE CODER_IMAGE; do
  val="$(grep -E "^${img_var}=" .env.example | cut -d= -f2-)"
  assert_not_contains "$val" ":latest" "$img_var is not ':latest'"
  assert_contains "$val" ":" "$img_var has an explicit tag ($val)"
done

echo "== unit: bash syntax of all scripts and tests =="
fail=0
while IFS= read -r -d '' f; do
  if ! err="$(bash -n "$f" 2>&1)"; then
    _t_fail "bash -n $f"
    echo "    $err"
    fail=1
  fi
done < <(find scripts tests gateway deploy workspace -name '*.sh' -print0 2>/dev/null)
[[ $fail -eq 0 ]] && _t_ok "all shell scripts pass bash -n"

echo "== unit: workspace template invariants =="
assert_file_exists workspace/templates/standard/main.tf
assert_file_exists workspace/templates/standard/startup_script.sh
assert_file_exists workspace/templates/standard/opencode.json
cmp -s workspace/templates/standard/opencode.json workspace/opencode/config/opencode.json \
  && _t_ok "template opencode.json matches canonical copy" \
  || _t_fail "template opencode.json DIVERGED from workspace/opencode/config/opencode.json"

echo "== unit: no secret-looking material in tracked files =="
# CHANGE_ME markers may exist ONLY in the .env.example template itself
leakers="$(git grep -lE '(PASSWORD|KEY)=CHANGE_ME' -- . ':(exclude).env.example' 2>/dev/null)"
assert_eq "$leakers" "" "no CHANGE_ME placeholders outside .env.example"
tracked_env="$(git ls-files .env | wc -l)"
assert_eq "$tracked_env" "0" ".env is not tracked by git"

finish_suite "unit"
