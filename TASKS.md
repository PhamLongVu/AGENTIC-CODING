# Tasks

Re-scoped from the original 10-phase plan to the confirmed baseline.
Status legend: ☐ todo · ◐ written, pending verification · ☑ done (with
evidence) · ⏸ deferred/blocked.

Per ruling R3 (PROJECT_STATUS.md): everything marked ◐ is **code-complete
but unverified** — it becomes ☑ only after its suite runs green in the
verification pass. No ☑ without a green test run recorded in
PROJECT_STATUS.md.

## Phase 0 — Repository & architecture  ☑

| # | Task | Status | Evidence |
|---|---|---|---|
| 0.1 | Repository init, .gitignore, .env.example | ☑ | git history |
| 0.2 | Reconcile execution plan with baseline | ☑ | `PROJECT_EXECUTION_PLAN.md` reconciliation table |
| 0.3 | CONFIGURATION_BASELINE.md (source of truth) | ☑ | file |
| 0.4 | ARCHITECTURE.md | ☑ | `docs/architecture/overview.md` |
| 0.5 | SECURITY.md incl. threat model + known limits | ☑ | `docs/architecture/security-model.md` |
| 0.6 | ADRs 0001–0007 | ☑ | `docs/decisions/ADR/` |
| 0.7 | DEVELOPMENT.md, DEPLOYMENT.md (no deploy) | ☑ | `docs/operations/` |
| 0.8 | Tasks + status ledger | ☑ | this file, PROJECT_STATUS.md |

## Phase 1 — Local development environment  ◐ (verification pass pending)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 1.1 | docker-compose: postgres (2 DBs, 2 users) | ◐ → ☑ * | healthy; coder+litellm schemas created — **verified manually 2026-11-10**; re-prove in suite |
| 1.2 | docker-compose: LiteLLM (DB mode, mock provider) | ◐ → ☑ * | `/health/liveliness` OK; mock completion via virtual key — **verified manually 2026-11-10**; suite green |
| 1.3 | Workspace image (pinned, non-root, code-server + OpenCode) | ◐ → ☑ * | builds (exit 0 **2026-11-10**); suite asserts non-root, no docker CLI, services healthy |
| 1.4 | LiteLLM virtual key script (budget/rpm) | ◐ → ☑ * | key issues, bad key 401, rpm 429 — **paths verified manually 2026-11-10**; budget exhaustion untestable in mock (KNOWN_ISSUES) |
| 1.5 | Local integration tests: gateway | ◐ | `make test-integration` green |
| 1.6 | Local integration tests: workspace image | ◐ | shared-file, non-root, no-docker-cli tests green |
| 1.7 | Coder server in compose | ◐ → ☑ * | healthy + admin login — **verified manually 2026-11-10**; suite green |

\* manually verified before ruling R3 paused testing; the ☑-worthy evidence
is the *suite* run, so these stay ◐ until `make test` is green.

## Phase 2 — Core platform integration (developer workflow)  ◐

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 2.1 | Coder docker template (volume, network, limits, apps) | ◐ | template uploads; workspace builds |
| 2.2 | Workspace startup script (agent-supervised services) | ◐ | code-server + OpenCode apps report healthy |
| 2.3 | OpenCode → LiteLLM provider config | ◐ | OpenCode in workspace completes a chat via mock model |
| 2.4 | E2E: create user → workspace → apps reachable | ◐ | scripted test green |
| 2.5 | Persistence test: stop/start keeps /home/coder | ◐ | scripted test green |
| 2.6 | Isolation test: two workspaces mutually unreachable | ◐ | scripted test green |
| 2.7 | Lifecycle: idle autostop configuration | ◐ | autostop visible on workspace (ttl 45m); manual stop keeps data |

## Phase 3 — AWS POC deployment (PREPARE ONLY — approval gate before apply)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 3.1 | Terraform: VPC/SG/EC2/IAM role/IMDS options | ◐ | `terraform validate` + `plan` clean (`make test-infra`, `make aws-plan`) |
| 3.2 | Cost + security disclosure document | ☑ | `docs/operations/deployment.md` §2–§4 (estimates marked) |
| 3.3 | Host bootstrap + AWS compose override | ◐ | `deploy/scripts/bootstrap-host.sh`, `deploy/compose/aws.yml` exist; reviewed |
| 3.4 | Post-deploy validation script (incl. IMDS block test) | ◐ | `deploy/scripts/validate-deployment.sh` exists; opt-in |
| 3.5 | **Owner approval gate** | ⏸ | requires human sign-off in-conversation; nothing applies before it |

## Phase 4 — Validation & hardening

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 4.1 | Multi-user isolation suite (local, real coder workspaces) | ◐ | A/B cross-access attempts all fail |
| 4.2 | Resource limit verification (cpu/mem/pids enforcement) | ◐ | observed limits match profile |
| 4.3 | Auth tests (bad login, no self-signup, app proxy auth) | ◐ | all rejected |
| 4.4 | Gateway hardening (revocation, model allowlist, rpm) | ◐ | enforced in mock mode |
| 4.5 | Cost measurement runbook + capacity table | ◐ runbook / ☐ measured numbers | runbook done (`docs/runbooks/cost-management.md`); **measured** table = Phase 4 execution |
| 4.6 | Ops docs: onboarding/offboarding/recovery runbooks | ☑ | `docs/runbooks/` complete |
| 4.7 | Independent security review | ⏸ | owner-assigned: fresh-eyes review pass per AGENTS.md §Review pass (Claude — owner ruling, no Codex) or an external human reviewer |

## Next actions (verification pass — tomorrow, per R3)

1. `make up` → all healthy; `make bootstrap` → admin + template + demo key.
2. `make build-workspace` (rebuild after any Dockerfile fix).
3. `make test` (unit + infra + integration + security), fix bugs, re-run.
4. Record results in PROJECT_STATUS.md test log; flip ◐ → ☑.
5. Only then: discuss Phase 3 approval gate with owner (still no apply).

## Deferred (from original plan, with triggers)

| Item | Original phase | Trigger to un-defer |
|---|---|---|
| EKS + Helm deployment path | 2–4 | ADR-0001 growth triggers |
| RDS PostgreSQL | 2 | >1 platform host or managed-backup requirement |
| ElastiCache Redis for LiteLLM | 5 | >1 LiteLLM replica |
| OIDC developer login | 3 | custom domain + IdP tenant available (ADR-0003) |
| TLS termination, custom domain | 3 | domain availability |
| CloudWatch/Prometheus/Grafana | 7 | beyond POC lifespan |
| EBS snapshot/DR automation | 8 | real user data + retention policy decision |
| Load tests to 30/50 workspaces | 9 | capacity expansion decision |
| ECR, S3 artifact/backups | 2 | demonstrated requirement |
| platform-api implementation | 3 | plan §3 marks optional; Coder API serves current needs |
