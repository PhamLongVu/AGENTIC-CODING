# Cloud Coding Platform (MVP)

Self-hosted, multi-user cloud coding platform: every developer gets an
**isolated, persistent workspace** in the browser with two experiences on the
**same filesystem**:

- **Chat-first AI coding** with OpenCode Web
- **IDE-first coding** with code-server (VS Code in the browser)

AI requests flow through a **central gateway (LiteLLM)** with per-developer
keys, budgets and usage tracking. Model provider: **AWS Bedrock** (AWS
deployment) or a **built-in mock** (local development — no AWS needed).

```text
Browser ──► Coder (auth, workspace lifecycle, app proxy)
              ├─► workspace: code-server :8080 ─┐
              ├─► workspace: OpenCode   :4096 ─┼── same /home/coder (persistent volume)
              └─► workspace: terminal          ┘
workspace ──► LiteLLM gateway :4000 ──► AWS Bedrock (prod) / mock (local)
```

## Quickstart (local, no AWS account required)

Prerequisites: Docker ≥ 24 with Compose v2, make, curl, jq, openssl.

```bash
cp .env.example .env
make gen-secrets          # random secrets for every CHANGE_ME
make dev-hosts-setup      # one-time: 127.0.0.1 host.docker.internal (sudo)
make up                   # postgres + litellm(mock) + coder
make bootstrap            # admin user + workspace template + demo virtual key
make test                 # local integration suite
```

Then open **http://host.docker.internal:7080**, log in with
`CODER_ADMIN_USER` / `CODER_ADMIN_PASSWORD` from `.env`, and create a
workspace from the `docker-standard` template.

## Documentation

| Doc | Purpose |
|---|---|
| [docs/CONFIGURATION_BASELINE.md](docs/CONFIGURATION_BASELINE.md) | **Single source of truth** — scope, budget, fixed decisions |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | MVP system design, flows, networks |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model, controls, known limitations |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Local dev guide, modes, testing |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | AWS POC runbook (**not deployed**; approval-gated) |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Implementation backlog + acceptance criteria |
| [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) | Progress ledger, rulings, test log |
| [docs/decisions/](docs/decisions/) | Architecture decision records |
| [PROJECT_EXECUTION_PLAN.md](PROJECT_EXECUTION_PLAN.md) | Original plan (reconciled — see header) |

## Repository layout

```text
docker-compose.yml          local platform stack (dev == prod shape)
deploy/                     AWS-mode compose override + host bootstrap
services/workspace-image/   pinned workspace Dockerfile (code-server+OpenCode)
services/litellm/           gateway configs (mock + bedrock) + key tooling
services/coder/template/    Coder workspace template (docker provider)
infra/terraform/            AWS POC infrastructure (never auto-applied)
scripts/                    make targets' implementations
tests/                      lib + local suite + opt-in aws suite
docs/                       documentation set (see table above)
```

## Status

Phase 1 (local environment) — see [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).
**No AWS resources have been created.** Deployment is approval-gated.
