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

## Phase 1 — Local development environment  ☑ (verified 2026-11-13)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 1.1 | docker-compose: postgres (2 DBs, 2 users) | ☑ | healthy; test_platform 9/9 (2026-11-13) |
| 1.2 | docker-compose: LiteLLM (DB mode, mock provider) | ☑ | health + mock completion via virtual key — test_gateway 12/12 (2026-11-13) |
| 1.3 | Workspace image (pinned, non-root, code-server + OpenCode) | ☑ | test_workspace_image 15/15 (2026-11-13); setuid stripped |
| 1.4 | LiteLLM virtual key script (budget/rpm) | ☑ | key issues; bad key 401; rpm_limit 429 burst (LiteLLM 1.83 field names) |
| 1.5 | Local integration tests: gateway | ☑ | test_gateway 12/12 (2026-11-13) |
| 1.6 | Local integration tests: workspace image | ☑ | test_workspace_image 15/15 (2026-11-13) |
| 1.7 | Coder server in compose | ☑ | healthy, admin login, template lifecycle — bootstrap green (2026-11-13) |

## Phase 2 — Core platform integration (developer workflow)  ☑ (verified 2026-11-13)

| # | Task | Status | Acceptance criteria |
|---|---|---|---|
| 2.1 | Coder docker template (volume, network, limits, apps) | ☑ | template pushes; 7 workspace builds exercised today (probes + suites) |
| 2.2 | Workspace startup script (agent-supervised services) | ☑ | apps report healthy through Coder (e2e + probes) |
| 2.3 | OpenCode → LiteLLM provider config | ☑ | in-workspace curl → gateway → MOCK RESPONSE (e2e 16/16) |
| 2.4 | E2E: create user → workspace → apps reachable | ☑ | test_e2e_workspace 16/16 (2026-11-13) |
| 2.5 | Persistence test: stop/start keeps /home/coder | ☑ | test_persistence 8/8 (2026-11-13) |
| 2.6 | Isolation test: two workspaces mutually unreachable | ☑ | test_isolation 10/10 (2026-11-13) |
| 2.7 | Lifecycle: idle autostop configuration | ☑ | ttl 45m asserted (e2e); stop/start keeps volume (persistence) |

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
| 4.1 | Multi-user isolation suite (local, real coder workspaces) | ☑ | test_isolation 10/10 (2026-11-13) |
| 4.2 | Resource limit verification (cpu/mem enforcement; pids not supported by provider — KNOWN_ISSUES) | ☑ | NanoCpus/Memory asserted on live workspace (e2e, 2026-11-13) |
| 4.3 | Auth tests (bad login, no self-signup, app proxy auth) | ☑ | test_auth 8/8 (2026-11-13) |
| 4.4 | Gateway hardening (revocation, model allowlist, rpm) | ☑ | test_gateway_hardening 7/7 (2026-11-13) |
| 4.5 | Cost measurement runbook + capacity table | ◐ runbook / ☐ measured numbers | runbook done (`docs/runbooks/cost-management.md`); **measured** table = Phase 4 execution |
| 4.6 | Ops docs: onboarding/offboarding/recovery runbooks | ☑ | `docs/runbooks/` complete |
| 4.7 | Independent security review | ⏸ | owner-assigned: fresh-eyes review pass per AGENTS.md §Review pass (Claude — owner ruling, no Codex) or an external human reviewer |

## Next actions (after the 2026-11-13 verification pass)

1. ~~local verification pass~~ **done 2026-11-13** — all four suites green
   (see PROJECT_STATUS.md test log); Phase 1/2 + 4.1–4.4 flipped ☑.
2. AWS POC: walk `docs/operations/deployment.md` with the owner gate
   (TASKS 3.5) before any `terraform apply`.
3. 4.5 measured capacity numbers + 4.7 review pass remain open.
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
