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
5. Security requirements in `docs/SECURITY.md` are release blockers, not
   suggestions. Especially: no docker socket in workspaces; no AWS credentials
   in workspaces; only LiteLLM talks to Bedrock; IMDS hop limit 1.

## Commands

| Command | Purpose |
|---|---|
| `make up` / `make down` | start/stop the local platform stack |
| `make bootstrap` | seed admin, template, demo virtual key |
| `make test` | full local integration suite (mock AI mode) |
| `make test-unit` | static checks (compose config, env completeness) |
| `make build-workspace` | build the workspace image |
| `make gen-secrets` | fill `.env` placeholders with random secrets |

## Conventions

- Versions are **pinned** in `.env` / Dockerfiles. No `latest` tags.
- The same `docker-compose.yml` serves local and AWS; environment differences
  live in `deploy/docker-compose.aws.yml` overrides only.
- Tests are plain `bash` + `curl` + `docker` under `tests/`, using
  `tests/lib/assertions.sh`. Every functional claim needs a test that proves
  it — do not mark backlog items done without a green test run recorded in
  `docs/IMPLEMENTATION_STATUS.md`.
- Workspace template changes go in `services/coder/template/` and must keep:
  non-root user, per-workspace volume+network, resource limits, no socket,
  apps bound to container loopback.
- Docs live in `docs/`. Update `IMPLEMENTATION_STATUS.md` (ledger) and
  `BACKLOG.md` statuses whenever work completes; rulings go in the ledger's
  decisions log.
- Commit at coherent milestones with meaningful messages; never push.

## Definition of "done" for a task (from the execution plan)

Implemented + tested (test output captured) + documented (status/backlog
updated) + known limitations noted. Anything less is not done.
