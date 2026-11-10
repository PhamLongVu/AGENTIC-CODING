# Decisions

Two kinds of decisions live in this repo:

1. **Architecture decisions** — durable, context+options+consequence records:
   `docs/decisions/ADR/`.
2. **Implementation rulings** — plan-vs-reality calls made while executing:
   the decisions log inside `PROJECT_STATUS.md` (R1, R2, …).

## ADR index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](docs/decisions/ADR/ADR-0001-single-ec2-docker-compose.md) | Single EC2 + Docker Compose (not EKS) | Accepted |
| [ADR-0002](docs/decisions/ADR/ADR-0002-coder-docker-provider.md) | Coder with Docker provider for workspace lifecycle | Accepted |
| [ADR-0003](docs/decisions/ADR/ADR-0003-developer-authentication.md) | Developer authentication: password (POC) → OIDC (later) | Accepted |
| [ADR-0004](docs/decisions/ADR/ADR-0004-ai-gateway-bedrock-isolation.md) | AI gateway (LiteLLM) isolates Bedrock from workspaces | Accepted |
| [ADR-0005](docs/decisions/ADR/ADR-0005-local-dev-mock-provider.md) | Local dev with mock AI provider (no AWS dependency) | Accepted |
| [ADR-0006](docs/decisions/ADR/ADR-0006-workspace-persistence-docker-volumes.md) | Per-workspace Docker volumes for persistence | Accepted |
| [ADR-0007](docs/decisions/ADR/ADR-0007-workspace-profiles-and-capacity.md) | Workspace profiles (S/M/L) and capacity estimates | Accepted |

## Key decisions at a glance

- **One EC2 instance, Docker Compose, no Kubernetes** (ADR-0001) — the
  confirmed baseline; EKS-era artifacts from the original plan are dropped.
- **Coder + kreuzwerker/docker provider** (ADR-0002) — workspace lifecycle,
  autostop, per-workspace volume+network, resource limits via template.
- **LiteLLM is the only Bedrock caller** (ADR-0004) — workspaces hold only a
  virtual key; AWS credentials never enter a workspace; IMDS hop limit 1.
- **Mock provider for local dev** (ADR-0005) — identical model names in mock
  and bedrock configs so only `AI_PROVIDER_MODE` flips.
- **Persistence = named Docker volumes** (ADR-0006) — volume survives
  workspace stop/start; deletion destroys it (backup first).

## Superseded / rejected

- EKS + Helm + RDS + ElastiCache (original plan phases 2–9): **rejected by
  baseline** — see the reconciliation table in `PROJECT_EXECUTION_PLAN.md`.
  Deferred-with-trigger items are tracked in `TASKS.md`.
