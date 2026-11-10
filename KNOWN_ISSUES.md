# Known issues & limitations

Honest list. Each item says what is true today, why, and what would fix it.
Security-relevant items mirror `docs/architecture/security-model.md`.

## Current limitations (accepted by baseline)

| # | Issue | Severity | Why accepted / fix path |
|---|---|---|---|
| 1 | **POC endpoint is HTTP-only** (no TLS, no domain) — credentials transit in cleartext to Coder/apps | High in prod, accepted for POC | Baseline: temporary endpoint. Fix: custom domain + TLS termination (deferred, TASKS.md). Until then: treat the endpoint as semi-trusted, no production credentials. |
| 2 | **Shared-kernel isolation**: workspaces are containers on one host, not VMs | Medium | Trusted-team POC scope (security-model.md). Escape-to-host = escape to all workspaces. Fix path: Firecracker/gVisor or per-user VMs (out of scope). |
| 3 | **Workspace disk quota is advisory** (Docker volumes have no hard per-volume cap) | Medium | One workspace can fill the host disk. Monitored via Home metadata tile + `docker system df` (cost-management runbook). Fix: XFS project quotas or per-workspace LVs (deferred). |
| 4 | **Backups are on-host** until manually copied off-host | Medium | `make backup` writes to `backups/` on the same EBS volume. Runbook step: copy off-host after every backup (backup-restore.md). Fix: S3 sync (deferred until requirement shown). |
| 5 | **Capacity numbers are modeled, not measured** (5 concurrent workspaces on m6a.2xlarge) | Medium | ADR-0007 requires measured numbers before any capacity claim (Phase 4). |
| 6 | **Mock provider bills USD 0** → per-key budget *exhaustion* cannot be tested locally | Low | Revocation (401) and rpm-burst (429) paths ARE tested; budget field is recorded on the key (verified via `/key/list`). Real exhaustion test = Bedrock mode with real spend (owner-approved session only). |
| 7 | **`litellm_virtual_key` appears in workspace build state** (Terraform rich parameter, marked sensitive → not shown in UI/logs, but stored in Coder DB) | Low | Same class as any agent env var. Mitigations: key is revocable instantly, scoped to model allowlist + budget. Documented in security-model.md. |
| 8 | **Coder template uses `kreuzwerker/docker` provider ~3.0 against Docker Engine API on host** — provider upgrades can shift behavior | Low | Pinned version; template tested in integration suite. |
| 9 | **Single Postgres container** (no HA, no automated failover) | Accepted | Baseline: single host. Backups via `scripts/backup.sh`. |

## Expected first-run issues (verification pass — ruling R3)

Written-not-verified code. These are the places most likely to need fixes
when `make up` / `make test` first run against the full stack:

1. **`scripts/coder/push-template.sh` CLI flags** — `templates push
   --activate --yes` flag set written against Coder v2 docs; exact accepted
   flags may differ in v2.36.3.
2. **Rich parameter shape** in `coder_create_workspace`
   (`tests/lib/coder.sh`) — `rich_parameter_values:[{name,value}]` is the
   documented shape; verify against actual API.
3. **OpenCode serve flags / healthcheck path** — `opencode serve --hostname
   --port` and `GET /` liveness written from docs; may need adjustment.
4. **Compose `!reset` YAML tag** (deploy/compose/aws.yml) requires Docker
   Compose v2.24+ — check host version before AWS mode.
5. **LiteLLM rpm limiter behavior** — burst vs strict enforcement was
   observed burstable locally; security test asserts 429 within a burst
   window (may need count/timeout tuning).
6. **kreuzwerker/docker provider version resolution** — `~3.0` constraint
   must resolve during `terraform init` inside the coder container
   (test-infra runs `init -backend=false` first).

None of these are architecture risks; all are mechanical fixes.

## Fixed (kept for context)

| Was | Fix | Where |
|---|---|---|
| `.env.example` image tags did not exist (guessed) | Registry-verified pins + digests | R2, `.env.example` |
| code-server 4.145.2 postinstall fails on node 22 | Base image → node:24.22.2-bookworm | workspace Dockerfile |
| Postgres init failed: `psql --username` alone connects to DB named after user | `--dbname "$POSTGRES_DB"` | deploy/postgres/init/01-create-app-dbs.sh |
| Unit suite inverted CHANGE_ME check (grepped .env.example) / char-vs-line count bug | Fixed assertions | tests/unit/run.sh |
