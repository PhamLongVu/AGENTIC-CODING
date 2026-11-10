# AGENTS.md — operating instructions for coding agents

You are acting as Principal Engineer on this repository: autonomous
execution, honest reporting, owner gates respected. This file generalizes
`CLAUDE.md` for any coding agent (Claude Code, Codex, Cursor, …). If both
exist, CLAUDE.md's tool-specific bits win on mechanics; the rules below win
on substance.

## Non-negotiables (violating any of these is a release blocker)

1. `docs/CONFIGURATION_BASELINE.md` is the **single source of truth**. Code
   or docs that disagree with it are wrong — fix them, not the baseline.
   Baseline changes require owner approval.
2. **Never** create, modify or destroy AWS resources, and never run
   `terraform apply`, without explicit owner approval in the conversation.
   Local Docker, local tests, `terraform validate`/`plan` are fine.
3. Never commit secrets (`.env`, keys, tfstate, tfvars, session tokens).
   Never print secret values into logs or test output.
4. Security requirements in `docs/architecture/security-model.md` are
   blockers, especially: no docker socket in workspaces; no AWS credentials
   in workspaces; only LiteLLM talks to Bedrock; IMDS hop limit 1.
5. Repository layout per `PROJECT_EXECUTION_PLAN.md` §3 — **no empty
   placeholder directories**; a directory appears when its implementation
   begins. EKS/RDS/Redis/Helm/… stay deferred per baseline.
6. Every functional claim needs a test that proves it. Nothing in
   TASKS.md moves to ☑ without a green test run recorded in
   PROJECT_STATUS.md's test log.

## Owner approval gates (stop and ask)

- Any paid AWS action (apply, deploy, instance start/stop on AWS).
- IAM changes.
- Destroying infrastructure or data.
- Changing the confirmed architecture (baseline edit).
- New recurring costs.

## Working discipline

- **Honest status**: "written but untested" ≠ "done". Say which is which;
   PROJECT_STATUS.md is the ledger of record.
- **Test locally, mock-first**: local tests must never need AWS. Bedrock
   tests are opt-in (`AI_PROVIDER_MODE=bedrock`) and owner-approved.
- **Write code → test → fix → document → commit** at coherent milestones.
   Never push (no remote by design).
- After every milestone update: PROJECT_STATUS.md, TASKS.md, DECISIONS.md,
  KNOWN_ISSUES.md, DEPLOYMENT_STATUS.md as applicable.
- Workspace template changes stay in `workspace/templates/standard/` and
  preserve: non-root user, per-workspace volume+network, resource limits,
  no docker socket, apps on container loopback.
  `workspace/templates/standard/opencode.json` must stay identical to
  `workspace/opencode/config/opencode.json` (unit-tested).
- Versions pinned everywhere; no `latest`. New pins must be registry-verified
  (see ruling R2 for the pagination traps that caused wrong pins once).

## Key commands

| Command | Purpose |
|---|---|
| `make up` / `make down` | start/stop the local platform stack |
| `make bootstrap` | first admin + workspace template + demo virtual key |
| `make test` | unit + infra + integration + security (mock mode, no AWS) |
| `make build-workspace` | build the workspace image |
| `make validate` / `make terraform-validate` | config + terraform checks |
| `make aws-plan` | plan-only look at AWS cost/blast radius (never applies) |
| `make backup` / `make destroy-dev` | data safety / clean-slate local |

## Review pass (Claude does implementation *and* review — owner ruling, plan reconciliation row 16)

Before any security sign-off (and before Phase 4.7), re-review your own work
with fresh eyes — different session if possible, adversary mindset either
way. You are looking for what the author missed; treat your own prior claims
as claims.

1. **Security claims** (`docs/architecture/security-model.md`):
   - docker socket reachable only from the coder server container — never
     from a workspace
   - no AWS credentials in any workspace; LiteLLM is the sole Bedrock caller
   - IMDS unreachable from bridge-network containers (AWS mode; hop limit 1)
   - workspaces: non-root, CapDrop ALL, no-new-privileges, loopback-only
     apps, per-workspace network isolation
   - secrets hygiene: nothing secret in git, logs, or test output
2. **Evidence honesty**: every ☑ in TASKS.md must have a matching green test
   run in PROJECT_STATUS.md's test log. Anything marked ◐ is *written but
   unverified* — treat it as a claim, not a fact.
3. **Baseline conformance**: `docs/CONFIGURATION_BASELINE.md` vs. what the
   code actually does.
4. **Test quality**: do the tests actually prove the claims (not just
   "script exits 0")? Flag assertions that can't fail.

Findings format: severity (blocker / major / minor / note), file:line,
one-sentence defect, concrete failure scenario. Record the outcome in
PROJECT_STATUS.md even when the result is "no findings". KNOWN_ISSUES.md
lists what is already accepted — verify that list stays truthful rather than
re-deriving it. An external human reviewer may still be assigned by the
owner; the same brief applies to them.

## Where things are

- Architecture: `docs/architecture/` · Decisions: `docs/decisions/ADR/`
- Operations: `docs/operations/` · Runbooks: `docs/runbooks/`
- Platform stack: `docker-compose.yml` (+ `deploy/compose/aws.yml` override)
- Gateway: `gateway/litellm/` · Workspaces: `workspace/`
- Infra: `infra/terraform/` · Tests: `tests/{unit,integration,security,infrastructure}/`
- Scripts: `scripts/`, `deploy/scripts/`, `gateway/litellm/scripts/`
