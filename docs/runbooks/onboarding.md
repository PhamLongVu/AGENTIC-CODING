# Runbook: onboarding a developer

~5 minutes, operator-driven (no self-registration by design — ADR-0003).

## 1. Create the Coder account

```bash
source tests/lib/env.sh
source tests/lib/coder.sh
coder_api POST /api/v2/users "$(jq -n --arg u "$1" --arg e "$2@example.invalid" \
  '{username:$u, email:$e, password:"CHANGE-on-first-login", login_type:"password"}')"
```

(Or UI → Users → New user.) Share the temp password over a secure channel;
the developer changes it on first login.

## 2. Issue their AI gateway key

```bash
gateway/litellm/scripts/create-virtual-key.sh <username> \
  "$LITELLM_DEFAULT_USER_BUDGET" "$LITELLM_DEFAULT_RPM" "$LITELLM_DEFAULT_TPM"
```

Record ONLY the key alias mapping (username ↔ alias). The key value goes to
the developer in the same secure channel — it is their personal credential.
Policy: `gateway/litellm/policies/README.md`.

## 3. First workspace

Developer (or operator) creates a workspace from **docker-standard**:

- parameter `litellm_virtual_key` = the developer's key (sensitive field —
  not displayed afterwards)
- profile default **Small**; autostop default **45 min**

Apps appear as `code-server` and `OpenCode` once the agent connects.

## 4. Verify (operator)

- workspace agents/apps healthy in the UI
- gateway spend row exists for the alias (`/key/list`)
- terminal + git clone works inside the workspace (developer's own test)

## Notes

- OIDC login replaces steps 1 (deferred — TASKS.md).
- Developers never receive: master key, AWS credentials, docker access —
  by architecture, not by policy.
