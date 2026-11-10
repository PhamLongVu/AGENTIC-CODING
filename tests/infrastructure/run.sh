#!/usr/bin/env bash
# Infrastructure checks (NO cloud credentials, NO apply):
#   terraform fmt + validate for the POC environment, run inside a pinned
#   hashicorp/terraform container so no host install is needed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/assertions.sh

TF_IMAGE="hashicorp/terraform:1.9.8"
ENV_DIR="infra/terraform/environments/dev"

echo "== infra: terraform image present =="
if ! docker image inspect "$TF_IMAGE" >/dev/null 2>&1; then
  assert_cmd "pull $TF_IMAGE" docker pull -q "$TF_IMAGE"
else
  _t_ok "terraform image cached"
fi

echo "== infra: terraform fmt =="
OUT="$(docker run --rm -v "$ROOT:/repo" -w /repo/$ENV_DIR --entrypoint sh "$TF_IMAGE" \
  -c 'terraform fmt -check -recursive -diff' 2>&1 || true)"
assert_eq "$OUT" "" "all .tf files formatted"

echo "== infra: terraform validate =="
OUT="$(docker run --rm -v "$ROOT:/repo" -w /repo/$ENV_DIR --entrypoint sh "$TF_IMAGE" \
  -c 'terraform init -backend=false -input=false >/dev/null 2>&1 && terraform validate' 2>&1 || true)"
assert_contains "$OUT" "Success" "validate passes"

echo "== infra: coder workspace template formatted =="
OUT="$(docker run --rm -v "$ROOT:/repo" -w /repo/workspace/templates/standard --entrypoint sh "$TF_IMAGE" \
  -c 'terraform fmt -check -recursive' 2>&1 || true)"
assert_eq "$OUT" "" "template .tf files formatted"

echo "== infra: no hardcoded secrets in terraform =="
LEAKS="$(grep -rniE '(aws_secret_access_key|access_key\s*=|password\s*=\s*"[^"]+"|CHANGE_ME")' \
  infra/terraform --include='*.tf' --include='*.tfvars.example' | grep -v 'CHANGE_ME' | grep -viE 'var\.|description|db_password' || true)"
assert_eq "$LEAKS" "" "no credentials in .tf files"

finish_suite "infrastructure"
