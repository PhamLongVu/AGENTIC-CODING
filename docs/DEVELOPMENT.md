# Local Development Guide

Goal: run and develop the **entire platform on a laptop with no AWS account,
no AWS credentials, and no network access to AWS**.

## 1. Prerequisites

- Docker Engine ≥ 24 with Compose v2 (`docker compose version`)
- 4+ GB free RAM (a workspace container uses ~1 GB idle)
- make, curl, jq, openssl
- Linux note: workspace containers reach the platform through
  `host.docker.internal`. Add it to your hosts file once (one-time, needs sudo):

  ```bash
  make dev-hosts-setup    # adds: 127.0.0.1 host.docker.internal
  ```

## 2. First start

```bash
cp .env.example .env
make gen-secrets         # fills every CHANGE_ME with strong random values
make up                  # postgres + litellm (mock) + coder
make bootstrap-coder     # creates the admin user and pushes the workspace template
```

Open the URL printed at the end (`http://host.docker.internal:7080` by default),
log in with the bootstrap admin credentials from `.env`.

## 3. Daily workflow

```bash
make up          # start platform
make logs        # follow all service logs
make ps          # service status + health
make test        # run the local test suite (no AWS)
make down        # stop platform (keeps data)
make clean       # stop and delete platform state AND workspace volumes (destructive)
```

Workspaces are created from the Coder dashboard ("Create workspace" → the
`docker-standard` template). Everything a workspace needs is local.

## 4. AI provider modes

| Mode | Config mounted | Behaviour |
|---|---|---|
| `mock` (default local) | `services/litellm/config.mock.yaml` | LiteLLM answers every chat request with a deterministic mock response — no AWS, no keys, works offline |
| `bedrock` (AWS only) | `services/litellm/config.bedrock.yaml` | LiteLLM calls Bedrock models using the EC2 instance profile |

Switch: set `AI_PROVIDER_MODE=mock|bedrock` in `.env`, then `make up`.
Local tests always run in mock mode; Bedrock tests live in `tests/aws/` and are
opt-in (they require a deployed POC instance).

## 5. Testing

- `make test` — local integration suite against the running compose stack:
  service health, LiteLLM virtual-key auth/budget behavior, workspace image
  build/start/health, shared filesystem between code-server and OpenCode,
  stop/start persistence, cross-workspace isolation.
- `make test-unit` — fast static checks (compose config validation, env
  completeness, script lint) that do not need Docker.
- Test harness: plain `bash` + `curl` + `docker` (no language runtime needed);
  assertions in `tests/lib/assertions.sh`.

## 6. Project layout

```text
docker-compose.yml         local platform stack (also used on EC2 + override)
deploy/docker-compose.aws.yml   AWS-mode overrides (LiteLLM host network, etc.)
services/workspace-image/  workspace Dockerfile + entrypoint
services/litellm/          LiteLLM configs (mock + bedrock) + key scripts
services/coder/template/   the docker-standard Coder workspace template
infra/terraform/           AWS POC infrastructure (never applied without approval)
scripts/                   dev/bootstrap/test/backup helpers
tests/lib tests/local tests/aws
docs/                      this documentation set
```

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| Workspace stuck "connecting" | hosts entry missing (`make dev-hosts-setup`); check `docker logs` of coder |
| LiteLLM 401 from workspace | virtual key not passed; re-check template parameter value |
| `host.docker.internal` unknown inside containers | template adds `extra_hosts: host-gateway` — verify Docker ≥ 20.10 |
| Port 7080/4000 already in use | change `CODER_HTTP_PORT`/`LITELLM_PORT` in `.env` |
| Postgres "password authentication failed" | stale volume; `make down` then remove `data/pgdata`, re-run `make bootstrap-db` |
