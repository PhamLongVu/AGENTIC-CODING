# Project status

Living progress ledger. One row per completed unit of work, with evidence.
Anything claimed here must have a test result or artifact behind it.

## Current state

- **Phase**: 1–3 code **complete, written-not-yet-verified** (see rulings R3/R5)
- **AWS resources created**: **none** (deployment is owner-gated)
- **Local stack status**: last verified green run 2026-11-10 (see test log);
  everything written after that run is pending tomorrow's build/test pass
- **Deployment status**: see `DEPLOYMENT_STATUS.md` (short version: NOT DEPLOYED)

## Completed

| Date | Milestone | Evidence |
|---|---|---|
| 2026-11-10 | Repository initialized; original plan preserved in git history | commit 51eabcf |
| 2026-11-10 | Execution plan reconciled with confirmed baseline | `PROJECT_EXECUTION_PLAN.md` header table |
| 2026-11-10 | Phase 0 docs: baseline, architecture, security, ADRs 0001–0007, dev/deploy guides, backlog | `docs/` (commit 018f03d) |
| 2026-11-10 | Platform image pins registry-verified and digest-recorded (postgres 16.4-alpine3.20 `sha256:5660c2cb…`; litellm-database `main-v1.83.14-stable.patch.3` `sha256:ec721a5e…` → `litellm --version` = 1.83.14; `ghcr.io/coder/coder:v2.36.3` `sha256:e71d75fa…` → `coder version` = v2.36.3 full build) | `.env.example` pins; pulls executed locally |
| 2026-11-10 | Platform stack runs locally: postgres + LiteLLM (DB mode) + Coder healthy; init script creates both DBs; first-admin bootstrap via `POST /api/v2/users/first` verified empirically | `docker compose ps` output (session log); `make bootstrap` flow |
| 2026-11-10 | Mock gateway verified end-to-end: virtual-key issue → completion with mock provider → 401 on bad key → 429 on rpm burst | curl transcripts (session log) |
| 2026-11-10 | Workspace image builds: node:24.22.2-bookworm base + code-server 4.145.2 + opencode-ai 1.19.5 (code-server ≥4.100 requires node ≥24) | `docker build` exit 0 |
| 2026-11-10 | Unit suite green (11 assertions) incl. compose parse, pin policy, template invariants, opencode.json sync rule | `make test-unit` |
| 2026-11-10 | **Full codebase written** — repo restructured to plan §3 layout; compose stack, workspace image + template, gateway configs + key scripts, all scripts, infra modules, AWS compose override + host bootstrap + deployment validation, 4 test suites, 5 CI workflows, full docs set, root tracking files | this commit (everything below is in it) |
| 2026-11-10 | **Static review pass** (independent code-review agent, static analysis only — no commands run): 10 defects found and fixed pre-first-run, incl. two suites that could structurally never pass (empty-needle assertions; template push aborting before its create fallback), a dead-on-arrival AWS bootstrap (IMDSv1 under IMDSv2-required), workspace config seeding via `dirname $0` (file never staged), a vacuous port-4000 exposure check, a restore race, IAM lockout (no SSH key, no SSM). Full list: KNOWN_ISSUES.md §"Fixed by the static review pass" | commit after d869012 |

## In progress

- **Verification pass** (scheduled next session, per owner ruling R3): build +
  run everything (`make up`, `make bootstrap`, `make build-workspace`,
  `make test`), fix bugs found. Expected fix points are listed in
  `KNOWN_ISSUES.md` §"expected first-run issues".

## Decisions log

Architecture decisions: `docs/decisions/ADR/ADR-0001…0007.md` (indexed in
`DECISIONS.md`). Implementation rulings (plan-vs-reality calls) are recorded
here:

| # | Ruling | Why | Cost if wrong |
|---|---|---|---|
| R1 | Repository root = this directory; work on `main` (fresh local repo, no remote, no shared history to protect) | executing-plans discipline adapted: nothing to isolate from | none |
| R2 | Platform images sourced from GHCR, not Docker Hub: Coder v2 publishes **only** to `ghcr.io/coder/coder` (Docker Hub `codercom/coder` is the discontinued v1.x product); LiteLLM DB-mode images at `ghcr.io/berriai/litellm-database`. LiteLLM pinned to **stable channel** (`main-v1.83.14-stable.patch.3`), Coder to `v2.36.3`. GHCR tag lists paginate at 1000 — enumerate all pages before judging "newest"; npm `versions` is string-sorted — use the `latest` dist-tag. | `.env.example` originally contained guessed tags that do not exist; verified by registry queries + pulling each image and running its `--version` | image pull failure at first `make up`; or pinning an EOL product — caught before commit |
| R3 | **Write-code-first, verify-later** (owner directive): the full codebase was written in one pass; builds/tests/deploys deferred to the next session. Everything not covered by the 2026-11-10 green runs above is *written but unverified* and must not be treated as done until its suite runs green. | owner: "code full đi đã … xong rồi build rồi fix bug sau" | first-run bugs (listed in KNOWN_ISSUES.md) surface in a batch instead of incrementally — accepted for schedule |
| R4 | Repo follows plan §3 layout, but deferred components' directories (eks/, rds/, redis/, ecr/, helm/, kubernetes/, prod/, load tests, platform-api source) are **not created** — the plan's own rule ("create each directory when its implementation begins") + baseline kills those components. `platform-api/` exists as README-only (plan §3 marks it optional/deferred). | plan §3 + baseline reconciliation | none — directories appear when implementation begins |
| R5 | No AWS resource is created, changed or destroyed at any point in this pass; `terraform apply` never executed; CI deploy workflow is owner-gated and intentionally stops before deployment (operator executes per runbook). | baseline rule #2 + owner gate | none |

## Test log (latest first)

| Date | Command | Result |
|---|---|---|
| 2026-11-10 | `make test-unit` (11 assertions: compose config parse, 19 interpolated vars, no-latest pins, bash -n all scripts, template invariants, opencode.json sync, CHANGE_ME policy, .env untracked) | ✅ 11/11 pass |
| 2026-11-10 | manual: `docker compose up -d` → all 3 services healthy; `scripts/bootstrap.sh` → first admin + session + demo virtual key; mock completion round-trip via virtual key; 401 revoked-key path; 429 rpm-burst path | ✅ all observed (session log) |
| 2026-11-10 | manual: `docker build` workspace image (node 24 base, code-server 4.145.2, opencode 1.19.5) | ✅ exit 0 |
| — | `make test` full suite (unit+infra+integration+security), `make test-infra` (terraform fmt/validate), integration e2e workspace tests, security suites | ⏳ pending verification pass (R3) |

## Known limitations (current)

See `KNOWN_ISSUES.md` for the full list with severity. Highlights:

1. POC endpoint is HTTP-only (baseline: temporary endpoint, no domain).
2. Single-host container isolation (shared kernel) — trusted-team POC only.
3. Per-workspace disk quota is advisory, not hard-enforced (ADR-0006).
4. Backups are on-host only until copied off-host (backup-restore.md).
5. Capacity numbers are modeled, not measured (Phase 4).
6. Mock provider bills USD 0 → per-key budget *exhaustion* is untestable
   locally (revocation and rpm-limit paths are tested).
