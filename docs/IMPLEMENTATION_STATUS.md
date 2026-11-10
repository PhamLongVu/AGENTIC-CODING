# Implementation Status

Living progress ledger. One row per completed unit of work, with evidence.
Anything claimed here must have a test result or artifact behind it.

## Current state

- **Phase**: 1 (local development environment) — in progress
- **AWS resources created**: **none**
- **Local stack status**: see last test run below

## Completed

| Date | Milestone | Evidence |
|---|---|---|
| 2026-11-10 | Repository initialized; original plan preserved in git history | commit 51eabcf |
| 2026-11-10 | Execution plan reconciled with confirmed baseline | `PROJECT_EXECUTION_PLAN.md` header table |
| 2026-11-10 | Phase 0 docs: baseline, architecture, security, ADRs 0001–0007, dev/deploy guides, backlog | `docs/` |
| 2026-11-10 | Platform image pins registry-verified and digest-recorded (postgres 16.4-alpine3.20 `sha256:5660c2cb…`; litellm-database `main-v1.83.14-stable.patch.3` `sha256:ec721a5e…` → `litellm --version` = 1.83.14; `ghcr.io/coder/coder:v2.36.3` `sha256:e71d75fa…` → `coder version` = v2.36.3 full build) | `.env.example` pins; pulls executed locally |

## In progress

- Phase 1: docker-compose platform stack, workspace image, mock gateway, local tests.

## Decisions log

All architecture decisions: `docs/decisions/ADR-*.md`.
Implementation rulings (plan-vs-reality calls) are recorded here:

| # | Ruling | Why | Cost if wrong |
|---|---|---|---|
| R1 | Repository root = this directory; work on `main` (fresh local repo, no remote, no shared history to protect) | executing-plans discipline adapted: nothing to isolate from | none |
| R2 | Platform images sourced from GHCR, not Docker Hub: Coder v2 publishes **only** to `ghcr.io/coder/coder` (Docker Hub `codercom/coder` is the discontinued v1.x product); LiteLLM DB-mode images at `ghcr.io/berriai/litellm-database`. LiteLLM pinned to **stable channel** (`main-v1.83.14-stable.patch.3`), Coder to the stable-channel version the official docs render against (`v2.36.3`). GHCR tag lists paginate at 1000 — enumerate all pages before judging "newest". | `.env.example` originally contained guessed tags that do not exist; verified by registry queries + pulling each image and running its `--version` | image pull failure at first `make up`; or pinning an EOL product — caught before commit |

## Test log (latest first)

| Date | Command | Result |
|---|---|---|
| 2026-11-10 | *(none yet — Phase 1 in progress)* | — |

## Known limitations (current)

1. POC endpoint is HTTP-only (baseline: temporary endpoint, no domain).
2. Single-host container isolation (shared kernel) — trusted-team POC only.
3. Per-workspace disk quota is advisory, not hard-enforced (see ADR-0006).
4. No automated per-workspace backups yet (manual `scripts/backup.sh` planned).
5. Capacity numbers are modeled, not measured (Phase 4).
