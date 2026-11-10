# Incident response (POC)

Small blast radius by design: one host, one platform. Sequence for the
common classes:

## 1. Suspected compromised workspace

1. Stop it: Coder UI → workspace → Stop (or `coder stop <ws>`).
2. Revoke its AI key: `POST /key/delete` (gateway) — see offboarding.md §2.
3. Capture evidence: `docker logs coder-ws-<owner>-<ws>`, volume tar via
   `scripts/backup.sh` (single volume: `docker run --rm -v <vol>:/src ...`).
4. Delete the workspace only after evidence capture.
5. Rotate `LITELLM_MASTER_KEY` if the gateway itself is implicated
   (re-issue virtual keys to all users — offboarding.md §4).

## 2. Leaked master key / .env exposure

1. `docker compose down` (stop the blast radius).
2. Rotate every secret in `.env` (`make gen-secrets` after clearing, or
   edit in place) — postgres passwords, master key, salt, admin password.
3. Postgres passwords changed ⇒ `ALTER USER` inside the DB to match, or
   rebuild from dump if locked out.
4. Restart, re-bootstrap, re-issue virtual keys.

## 3. Gateway abuse (runaway spend)

1. Identify the key: gateway UI/`/key/list` → spend per alias.
2. Revoke it (§1 step 2). Budgets default-cap at USD 20/month/key.
3. Tighten rpm/tpm on the policy (`gateway/litellm/policies/README.md`).

## 4. Host compromise

1. `deploy/scripts/instance-stop.sh stop`.
2. Owner decides: forensic snapshot (EBS snapshot of the root volume) vs
   immediate destroy. IAM role is Bedrock-invoke-only — credential blast
   radius is spend, not account takeover.
3. Rebuild path: terraform apply on a fresh instance + restore backup.

## Always

- Log the incident + actions in `KNOWN_ISSUES.md`.
- Anything security-relevant also goes to the owner immediately — the
  security review gate (TASKS.md 4.7) is the follow-up.
