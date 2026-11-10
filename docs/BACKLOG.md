# Implementation Backlog

Re-scoped from the original 10-phase plan to the confirmed baseline.
Status legend: ☐ todo · ◐ in progress · ☑ done (with evidence) · ⏸ deferred.

## Phase 0 — Repository & architecture  ☑

| # | Task | Status | Evidence |
|---|---|---|---|
| 0.1 | Repository init, .gitignore, .env.example | ☑ | git history |
| 0.2 | Reconcile execution plan with baseline | ☑ | `PROJECT_EXECUTION_PLAN.md` reconciliation table |
| 0.3 | CONFIGURATION_BASELINE.md (source of truth) | ☑ | file |
| 0.4 | ARCHITECTURE.md | ☑ | file |
| 0.5 | SECURITY.md incl. threat model + known limits | ☑ | file |
| 0.6 | ADRs 0001–0007 | ☑ | `docs/decisions/` |
| 0.7 | DEVELOPMENT.md, DEPLOYMENT.md (no deploy) | ☑ | files |
| 0.8 | Backlog + status ledger | ☑ | this file, IMPLEMENTATION_STATUS.md |

## Phase 1 — Local development environment  ◐

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 1.1 | docker-compose: postgres (2 DBs, 2 users) | ☐ | healthy; coder+litellm schemas created |
| 1.2 | docker-compose: LiteLLM (DB mode, mock provider) | ☐ | `/health/liveliness` OK; mock chat completion works via virtual key |
| 1.3 | Workspace image (pinned, non-root, code-server + OpenCode + toolchain) | ☐ | builds; starts; both services healthy in-container |
| 1.4 | LiteLLM virtual key script (budget/rpm) | ☐ | key issues; bad key rejected; budget enforced (mock) |
| 1.5 | Local integration tests: gateway | ☐ | `make test` green |
| 1.6 | Local integration tests: workspace image | ☐ | shared-file test, non-root test, no-docker-cli test |
| 1.7 | Coder server in compose | ☐ | healthy; admin login works |

## Phase 2 — Core platform integration (developer workflow)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 2.1 | Coder docker template (volume, network, limits, apps) | ☐ | template uploads; workspace builds |
| 2.2 | Workspace startup script (agent-supervised services) | ☐ | code-server + OpenCode apps report healthy |
| 2.3 | OpenCode → LiteLLM provider config | ☐ | OpenCode in workspace completes a chat via mock model |
| 2.4 | E2E: create user → workspace → apps reachable | ☐ | scripted test green |
| 2.5 | Persistence test: stop/start keeps /home/coder | ☐ | scripted test green |
| 2.6 | Isolation test: two workspaces mutually unreachable | ☐ | scripted test green |
| 2.7 | Lifecycle: idle autostop configuration | ☐ | autostop visible on workspace; manual stop keeps data |

## Phase 3 — AWS POC deployment (PREPARE ONLY — approval gate before apply)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 3.1 | Terraform: VPC/SG/EC2/IAM role/IMDS options | ☐ | `terraform validate` + `plan` clean |
| 3.2 | Cost + security disclosure document | ☑ | `DEPLOYMENT.md` §2–§4 (estimates marked) |
| 3.3 | Host bootstrap + AWS compose override | ☐ | scripts exist; reviewed |
| 3.4 | Post-deploy validation script (incl. IMDS block test) | ☐ | script exists; opt-in |
| 3.5 | **Owner approval gate** | ⏸ | requires human sign-off |

## Phase 4 — Validation & hardening

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 4.1 | Multi-user isolation suite (local, real coder workspaces) | ☐ | A/B cross-access attempts all fail |
| 4.2 | Resource limit verification (cpu/mem/pids enforcement) | ☐ | observed limits match profile |
| 4.3 | Auth tests (bad login, no self-signup, app proxy auth) | ☐ | all rejected |
| 4.4 | Gateway hardening (budget exhaustion, key revocation) | ☐ | enforced in mock mode |
| 4.5 | Cost measurement runbook + capacity table | ☐ | measured numbers published |
| 4.6 | Ops docs: onboarding/offboarding/recovery runbooks | ☐ | docs complete |
| 4.7 | Independent security review | ⏸ | owner-assigned reviewer |

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
