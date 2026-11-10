# CLAUDE.md — repository instructions for coding agents

## Non-negotiable context

1. `docs/CONFIGURATION_BASELINE.md` is the **single source of truth**. If any
   file or code disagrees with it, fix that thing — not the baseline. Changing
   the baseline requires owner approval.
2. **Never** create, modify or destroy AWS resources, and never run
   `terraform apply`, without explicit owner approval in the conversation.
   Local Docker, local tests, `terraform validate/plan` (no creds needed for
   validate) are always allowed.
3. Never commit secrets (`.env`, keys, tfstate, tfvars). `.gitignore` already
   blocks them — do not bypass it.
4. Never print secret values into logs or test output.
5. Security requirements in `docs/architecture/security-model.md` are release
   blockers, not suggestions. Especially: no docker socket in workspaces; no
   AWS credentials in workspaces; only LiteLLM talks to Bedrock; IMDS hop
   limit 1.
6. Repository layout follows `PROJECT_EXECUTION_PLAN.md` §3. Do NOT create
   empty placeholder directories for deferred components (EKS, Helm, RDS,
   …); a directory appears when its implementation begins.

## Commands

| Command | Purpose |
|---|---|
| `make up` / `make down` | start/stop the local platform stack |
| `make bootstrap` | seed admin, template, demo virtual key |
| `make test` | everything local (unit + infra + integration + security, mock mode) |
| `make test-unit` / `test-infra` / `test-integration` / `test-security` | individual suites |
| `make build-workspace` | build the workspace image |
| `make gen-secrets` / `make dev-hosts-setup` | first-time env setup |
| `make backup` | dump DBs + workspace volumes to `backups/` |

## Conventions

- Versions are **pinned** in `.env` / Dockerfiles. No `latest` tags.
- The same `docker-compose.yml` serves local and AWS; environment differences
  live only in the `deploy/compose/aws.yml` override.
- Tests are plain `bash` + `curl` + `docker` under `tests/`, using
  `tests/lib/assertions.sh`. Every functional claim needs a test that proves
  it — do not mark TASKS.md items done without a green test run recorded in
  `PROJECT_STATUS.md`.
- Workspace template changes go in `workspace/templates/standard/` and must
  keep: non-root user, per-workspace volume+network, resource limits, no
  socket, apps bound to container loopback. `workspace/templates/standard/
  opencode.json` must stay identical to `workspace/opencode/config/
  opencode.json` (unit-tested).
- Docs live in `docs/{architecture,operations,decisions/ADR,runbooks}/`.
  Update `PROJECT_STATUS.md` (ledger), `TASKS.md`, `DECISIONS.md`,
  `KNOWN_ISSUES.md`, `DEPLOYMENT_STATUS.md` after every milestone; rulings
  go in the ledger's decisions log.
- Commit at coherent milestones with meaningful messages; never push.

## Definition of "done" for a task (from the execution plan)

Implemented + tested (test output captured) + documented (status/backlog
updated) + known limitations noted. Anything less is not done.
