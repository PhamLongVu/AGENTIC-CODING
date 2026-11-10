# Architecture — MVP (single-instance, Docker Compose)

Scope: the MVP described in `CONFIGURATION_BASELINE.md`. The original plan's
EKS/Kubernetes architecture remains documented in `PROJECT_EXECUTION_PLAN.md`
as the growth path; it is **not** built here.

## 1. System overview

```text
                          Developer (browser)
                                 |
                    http://<endpoint>:7080   (temporary POC endpoint)
                                 |
                    +------------v------------+
                    |  EC2  (ap-southeast-1)  |     m6a.2xlarge (8 vCPU / 32 GiB)
                    |  Ubuntu 24.04 + Docker  |     200 GiB gp3 root volume
                    |                         |
                    |  Docker Compose stack   |
                    |                         |
                    |  +-------------------+  |
   docker.sock ---->|  | Coder server      |  |     control plane: auth, workspace
   (control plane   |  | :7080 (HTTP)      |  |     provisioning, app proxy
    ONLY, never     |  +---------+---------+  |
    workspaces)     |            |            |
                    |  +---------v---------+  |
                    |  | PostgreSQL 16     |  |     Coder + LiteLLM metadata
                    |  | (container, no    |  |     named volume: pgdata
                    |  |  public port)     |  |
                    |  +-------------------+  |
                    |  +-------------------+  |
                    |  | LiteLLM (DB mode) |  |     AI gateway: virtual keys,
                    |  | :4000             |  |     budgets, usage tracking
                    |  | host net on AWS   |  |     host network ON AWS ONLY
                    |  +---------+---------+  |     (IMDS access for Bedrock)
                    |            ^            |
                    |  (workspace requests)   |
                    |            |            |
                    |  +---------+---------+  |
                    |  | workspace         |  |     1 per developer, docker
                    |  | containers        |  |     container + named volume,
                    |  |  - Coder agent    |  |     per-workspace docker network
                    |  |  - code-server    |  |     :8080 (localhost only)
                    |  |  - OpenCode serve |  |     :4096 (localhost only)
                    |  +-------------------+  |
                    +-------------------------+
                                 |
                    (LiteLLM only, via IAM role)
                                 |
                    +------------v------------+
                    |  AWS Bedrock            |     Claude / Nova models
                    +-------------------------+
```

## 2. Component responsibilities

| Component | Responsibility | Runs as |
|---|---|---|
| Coder server | Developer login, workspace CRUD & lifecycle, idle autostop, app proxy for code-server + OpenCode Web | Docker container; mounts `docker.sock` (control plane only) |
| Coder agent | In-workspace supervisor; starts services, executes lifecycle scripts, tunnels apps through the proxy | Process inside each workspace container |
| PostgreSQL | Single instance, two databases (`coder`, `litellm`), separate low-privilege users | Docker container; published to localhost only |
| LiteLLM | OpenAI-compatible endpoint; per-developer virtual keys, budgets, RPM/TPM limits, usage tracking; Bedrock client (AWS mode) | Docker container; **host network on AWS** (IMDS reach), bridge + published port locally |
| code-server | Browser IDE bound to workspace localhost | Process in workspace container |
| OpenCode (`opencode serve`) | AI coding web UI bound to workspace localhost | Process in workspace container |
| Workspace image | Pinned, non-root (`coder`), dev toolchain (git, Python, Node), code-server, OpenCode | Built locally / on the EC2 host |

## 3. Request flows

### 3.1 Developer session

```text
Browser → Coder :7080 (login, workspace list)
        → Coder app proxy → workspace agent → code-server :8080 (IDE)
                          → workspace agent → OpenCode  :4096 (chat)
        → Coder terminal  → workspace agent (shell)
```

Workspace services bind to the container's loopback only; they are reachable
exclusively through Coder's authenticated proxy. No workspace port is published
to the host or the internet.

### 3.2 AI request

```text
OpenCode (workspace)
   → http://host.docker.internal:4000/v1/... (LiteLLM, per-dev virtual key)
   → LiteLLM auth + budget + rate limit + usage row (PostgreSQL)
   → AWS mode:  Bedrock via instance-profile IAM role (host network)
     mock mode: LiteLLM built-in mock response (no network, no AWS)
   → response streamed back to OpenCode
```

### 3.3 Workspace provisioning

```text
Developer clicks Create → Coder server runs the workspace template (Terraform,
docker provider) → creates per-workspace docker network + named volume
(persistent /home/coder) + workspace container with CPU/memory/pids limits
→ Coder agent boots → runs startup script (code-server + OpenCode) →
apps report healthy in the dashboard.
```

## 4. Workspace topology

```text
workspace container (non-root user "coder", uid 1000)
├── /home/coder                     ← named docker volume "coder-<user>-<ws>-home"
│   ├── projects/                   ← project files (OpenCode + code-server share this)
│   ├── .config/opencode/           ← OpenCode config
│   ├── .local/share/opencode/      ← OpenCode sessions/state
│   └── .ssh/                       ← developer git credentials (their own)
├── code-server   :8080  (127.0.0.1)
├── opencode serve :4096 (127.0.0.1)
└── coder agent   (supervised by Coder, executes startup/lifecycle scripts)
```

Both tools operate on the same `/home/coder` filesystem — the shared-project
requirement from the original plan is satisfied by construction, and verified by
integration tests (`tests/integration/`).

## 5. Networks and ports

| Network | Members | Purpose |
|---|---|---|
| `platform` (compose bridge) | postgres, litellm (local mode), coder | service-to-service; postgres not reachable from anywhere else |
| `coder-<user>-<ws>` (per workspace) | the one workspace container | isolation: workspaces cannot address each other; egress via NAT to registries/git hosts |
| `host` (AWS only) | litellm | IMDS reach for instance-profile Bedrock credentials |

| Port | Binding | Exposure |
|---|---|---|
| 7080 | coder server | Public on AWS via SG (POC endpoint); local `host.docker.internal` |
| 4000 | LiteLLM | Host-internal (SG blocks internet); needed by workspace containers |
| 5432 | postgres | localhost only (admin convenience) |
| 8080/4096 | workspace services | container loopback only, via Coder app proxy |

## 6. Persistence & lifecycle

| State | Where | Survives stop | Backup |
|---|---|---|---|
| Coder metadata (users, workspaces, templates) | `pgdata` volume + `coder` DB | yes | `scripts/backup.sh` (pg_dump + volume tar) |
| LiteLLM metadata (keys, budgets, usage) | `pgdata` volume + `litellm` DB | yes | same |
| Workspace `/home/coder` | per-workspace named volume | **yes** | volume tar snapshot, on demand |
| Container writable layer | — | no (ephemeral by design) | — |

Lifecycle: create → start (agent boots, services start) → idle autostop 45 min
(container stops, volume kept) → start (volume re-attached, services restart) →
delete (explicit confirmation; volume destroyed).

## 7. Capacity model (to be validated by benchmarks)

- Platform overhead (coder, litellm, postgres, dockerd): ~1.5 vCPU / ~3 GiB.
- Remaining budget on `m6a.2xlarge`: ~6 vCPU / ~28 GiB → 5×Small (5 vCPU/10 GiB)
  fits; 2–3×Medium fits; 5×Medium does **not** fit. Profile mix is enforced
  operationally (default profile Small) and measured in Phase 4.
- Cost model and duty-cycle assumptions: `docs/operations/deployment.md` §2.

## 8. What is deliberately NOT here

Kubernetes/EKS/Helm, RDS, ElastiCache, multi-AZ, autoscaling groups, custom
frontend, custom scheduler, service mesh. Growth path triggers are recorded in
`docs/decisions/ADR-0001-single-ec2-docker-compose.md`.
