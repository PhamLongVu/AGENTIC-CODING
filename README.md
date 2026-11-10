# Cloud Coding Platform (MVP)

Self-hosted, multi-user cloud coding platform: every developer gets an
**isolated, persistent workspace** in the browser with two experiences on the
**same filesystem**:

- **Chat-first AI coding** with OpenCode Web
- **IDE-first coding** with code-server (VS Code in the browser)

AI requests flow through a **central gateway (LiteLLM)** with per-developer
keys, budgets and usage tracking. Model provider: **AWS Bedrock** (AWS
deployment) or a **built-in mock** (local development — no AWS needed).

Single EC2 + Docker Compose, no Kubernetes — see the baseline for why.

```text
Browser ──► Coder (auth, workspace lifecycle, app proxy)
              ├─► workspace: code-server :8080 ─┐
              ├─► workspace: OpenCode   :4096 ─┼── same /home/coder (persistent volume)
              └─► workspace: terminal          ┘
workspace ──► LiteLLM gateway :4000 ──► AWS Bedrock (aws mode) / mock (local)
```

## Quickstart (local, no AWS account required)

Prerequisites: Docker ≥ 24 with Compose v2.24+ (the AWS override uses
`!reset`), make, curl, jq, openssl.

```bash
cp .env.example .env
make gen-secrets          # random secrets for every CHANGE_ME
make dev-hosts-setup      # one-time: 127.0.0.1 host.docker.internal (sudo)
make up                   # postgres + litellm(mock) + coder
make bootstrap            # admin user + workspace template + demo virtual key
make build-workspace      # pinned workspace image (code-server + OpenCode)
make test                 # unit + infra + integration + security (mock, no AWS)
```

Then open **http://host.docker.internal:7080**, log in with
`CODER_ADMIN_USER` / `CODER_ADMIN_PASSWORD` from `.env`, and create a
workspace from the `docker-standard` template (parameter
`litellm_virtual_key` = the demo key printed by bootstrap into
`.demo-virtual-key`).

## Documentation

| Doc | Purpose |
|---|---|
| [docs/CONFIGURATION_BASELINE.md](docs/CONFIGURATION_BASELINE.md) | **Single source of truth** — scope, budget, fixed decisions |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Progress ledger, rulings R1–R5, test log |
| [TASKS.md](TASKS.md) | Task backlog + acceptance criteria |
| [DECISIONS.md](DECISIONS.md) | ADR index + decisions at a glance |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Honest limitations + expected first-run issues |
| [DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md) | **NOT DEPLOYED** — gate to any deployment |
| [docs/architecture/overview.md](docs/architecture/overview.md) | MVP system design, flows, networks |
| [docs/architecture/security-model.md](docs/architecture/security-model.md) | Threat model, controls, known limitations |
| [docs/architecture/workspace-lifecycle.md](docs/architecture/workspace-lifecycle.md) | Create → run → autostop → start → delete |
| [docs/architecture/aws-network.md](docs/architecture/aws-network.md) | VPC/SG/IMDS layout (AWS mode) |
| [docs/architecture/data-persistence.md](docs/architecture/data-persistence.md) | What persists, what doesn't, backups |
| [docs/operations/development.md](docs/operations/development.md) | Local dev guide, modes, testing |
| [docs/operations/deployment.md](docs/operations/deployment.md) | AWS POC runbook (approval-gated) |
| [docs/operations/backup-restore.md](docs/operations/backup-restore.md) · [rollback.md](docs/operations/rollback.md) · [incident-response.md](docs/operations/incident-response.md) · [troubleshooting.md](docs/operations/troubleshooting.md) | Ops guides |
| [docs/runbooks/](docs/runbooks/) | Onboarding, offboarding, workspace recovery, cost management |
| [docs/decisions/ADR/](docs/decisions/ADR/) | Architecture decision records 0001–0007 |
| [PROJECT_EXECUTION_PLAN.md](PROJECT_EXECUTION_PLAN.md) | Original plan (reconciled — see header) |
| [AGENTS.md](AGENTS.md) | Operating rules for coding agents (Claude does implementation **and** review — see its Review pass section) |

## Repository layout

Follows `PROJECT_EXECUTION_PLAN.md` §3 — but **no empty placeholder
directories**: deferred components (EKS, RDS, Redis, Helm, load tests,
platform-api source) have no directories until their implementation begins.

```text
docker-compose.yml           local platform stack (dev == prod shape)
deploy/                      compose override (aws) · host bootstrap · postgres init · deployment validation
gateway/litellm/             gateway configs (mock + bedrock) · key tooling · key policy
workspace/                   images/development (pinned Dockerfile) · templates/standard · opencode/ code-server/ config
infra/terraform/             modules (vpc, iam, ec2) + environments/dev — never auto-applied
platform-api/                deferred (README explains trigger)
scripts/                     bootstrap · validate · deploy-dev · backup · restore · destroy-dev · env/secrets/hosts
tests/                       unit · integration · security · infrastructure (+ lib/)
docs/                        architecture · operations · decisions/ADR · runbooks
.github/workflows/           lint · test · build-images · terraform-plan · deploy (owner-gated)
```

Root tracking files: `PROJECT_STATUS.md` `TASKS.md` `DECISIONS.md`
`KNOWN_ISSUES.md` `DEPLOYMENT_STATUS.md`.

## Status

Code complete through Phase 3 prep; verification pass pending — see
[PROJECT_STATUS.md](PROJECT_STATUS.md) (ruling R3: write-code-first,
verify-next-session). **No AWS resources have been created.** Deployment is
approval-gated ([DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md)).
