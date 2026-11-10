# Local Development Guide

Goal: run and develop the **entire platform on a laptop with no AWS account,
no AWS credentials, and no network access to AWS**.

## 1. Prerequisites

- Docker Engine ≥ 24 with Compose v2.24+ (`docker compose version`; the AWS
  override uses the `!reset` tag — v2.24+)
- 4+ GB free RAM (a workspace container uses ~1 GB idle)
- make, curl, jq, openssl
- Linux note: workspace containers reach the platform through
  `host.docker.internal`. Add it to your hosts file once (one-time, needs sudo):

  ```bash
  make dev-hosts-setup    # adds: 127.0.0.1 host.docker.internal
  ```

## 2. First start (fresh machine — 6 commands)

```bash
cp .env.example .env
make gen-secrets         # fills every CHANGE_ME with strong random values
make dev-hosts-setup     # one-time hosts entry (sudo)
make up                  # postgres + litellm (mock) + coder
make bootstrap           # admin user + workspace template + demo virtual key
make build-workspace     # pinned workspace image (code-server + opencode)
```

Open **http://host.docker.internal:7080**, log in with
`CODER_ADMIN_USER` / `CODER_ADMIN_PASSWORD` from `.env`. Create a workspace
from the `docker-standard` template; the demo key for the
`litellm_virtual_key` parameter is in `.demo-virtual-key`.

Then verify everything: `make test` (unit + infra + integration + security,
all mock-mode, no AWS).

Shortcut: `make deploy-dev` = env check → up → bootstrap.

## 3. Daily workflow

```bash
make up          # start platform
make logs        # follow all service logs (or: make logs s=coder)
make ps          # service status + health
make test        # local test suite (no AWS)
make down        # stop platform (all data kept)
make backup      # dump DBs + workspace volumes to backups/<stamp>/
```

Workspaces are created from the Coder dashboard ("Create workspace" → the
`docker-standard` template). Everything a workspace needs is local.

Destructive teardown (understands what it destroys, asks for confirmation):

```bash
make destroy-dev L=stack       # stop + remove containers/networks (volumes kept)
make destroy-dev L=data        # rm platform volumes (postgres, coder home)
make destroy-dev L=workspaces  # rm workspace volumes (types a confirmation phrase)
```

## 4. AI provider modes

| Mode | Config mounted | Behaviour |
|---|---|---|
| `mock` (default local) | `gateway/litellm/config/config-mock.yaml` | LiteLLM answers every chat request with a deterministic mock response — no AWS, no keys, works offline |
| `bedrock` (AWS only) | `gateway/litellm/config/config-bedrock.yaml` | LiteLLM calls Bedrock models using the EC2 instance profile |

Both configs expose **identical model names**, so only `AI_PROVIDER_MODE`
flips — no workspace or client change. Switch: set
`AI_PROVIDER_MODE=mock|bedrock` in `.env`, then `make up`.

Local tests always run in mock mode. The Bedrock round-trip is an **opt-in**
step of `deploy/scripts/validate-deployment.sh` (runs on the EC2 instance,
owner-approved).

## 5. Testing

| Suite | Command | Needs |
|---|---|---|
| Unit (compose parse, env contract, pins, bash -n, template invariants) | `make test-unit` | nothing (static) |
| Infrastructure (terraform fmt/validate, secret scan) | `make test-infra` | Docker (runs pinned terraform container, no AWS creds) |
| Integration (platform, gateway, workspace image, e2e workspace, persistence, isolation) | `make test-integration` | stack up (`make up`) + workspace image built |
| Security (auth, gateway hardening, container isolation) | `make test-security` | stack up |

`make test` = all four, mock mode. Harness: plain `bash` + `curl` + `docker`
(no language runtime); assertions in `tests/lib/assertions.sh`.

## 6. Project layout

```text
docker-compose.yml           local platform stack (also used on EC2 + override)
deploy/compose/aws.yml       AWS-mode overrides (LiteLLM host network, etc.)
deploy/postgres/init/        DB/user bootstrap SQL run on first postgres start
gateway/litellm/             configs (mock + bedrock) + key tooling + policy
workspace/images/development/  workspace Dockerfile + service startup script
workspace/templates/standard/  the docker-standard Coder workspace template
infra/terraform/             AWS POC infrastructure (never applied without approval)
scripts/                     dev/bootstrap/test/backup helpers
tests/                       lib + unit + integration + security + infrastructure
docs/                        architecture · operations · decisions/ADR · runbooks
```

Full layout and rules: README.md and `PROJECT_EXECUTION_PLAN.md` §3.

## 7. Taking the repo to another machine

What travels with the repo (git): **all code, configs, docs, tests**.
What does **not** (by design, gitignored): `.env` secrets, `.coder-session`,
`.demo-virtual-key`, postgres data, workspace volumes, `backups/`.

Fresh machine = same 6 commands as §2. You get a **fresh platform** (new
secrets, new admin, no workspaces) — not a copy of the old one. To carry
data over too:

1. Old machine: `make backup` → copy `backups/<stamp>/` to the new machine.
2. New machine: `make up` (fresh stack) → `scripts/restore.sh <stamp>`.
3. Full-host disaster rebuild: `docs/runbooks/workspace-recovery.md` §"Host lost".

Note: `.env` secrets differ per machine (master key, DB passwords) —
`scripts/restore.sh` restores DB contents, so restore the matching `.env`
too, or re-point key material deliberately.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `make up` fails: postgres unhealthy | init failed once; `make destroy-dev L=data` then `make up` (fresh platform data) |
| Workspace stuck "connecting" | hosts entry missing (`make dev-hosts-setup`); check `docker compose logs coder` |
| LiteLLM 401 from workspace | virtual key not passed; re-check template parameter value |
| `host.docker.internal` unknown inside containers | template adds `extra_hosts: host-gateway` — verify Docker ≥ 20.10 |
| Port 7080/4000 already in use | change `CODER_HTTP_PORT`/`LITELLM_PORT` in `.env` |
| Postgres "password authentication failed" | stale volume with old secrets; `make destroy-dev L=data` then re-run §2 |
| Mock chat answers with "MOCK RESPONSE" | that's the mock provider working as designed (ADR-0005) |

More: `docs/operations/troubleshooting.md`.
