# ADR-0002: Coder as workspace control plane using its Docker provider

- Status: CONFIRMED (owner baseline selects Coder; provider choice is ours)

## Context

We need workspace lifecycle (create/start/stop/delete), per-user auth, idle
autostop, browser access to code-server and OpenCode, and persistence across
stop/start — without Kubernetes.

## Decision

Run the **Coder server** as a container with access to the host Docker socket,
and provision workspaces with a Coder template based on Coder's **Docker
provider** (`docker_container`, `docker_volume`, `docker_network` resources).
The template:

- creates one container per workspace (non-root `coder` user),
- creates one named volume per workspace mounted at `/home/coder` (persists
  across stop/start; destroyed only on workspace delete),
- creates one bridge network per workspace (peer isolation),
- enforces CPU / memory / pids limits by profile parameter,
- drops all Linux capabilities, sets `no-new-privileges`, disables privileged,
- exposes code-server (:8080) and OpenCode (:4096) as Coder workspace apps
  reachable only through the authenticated Coder proxy,
- sets idle autostop (default 45 min, user-adjustable).

The Coder server container is the **only** container allowed to touch
`/var/run/docker.sock`. Workspace containers never see it.

## Alternatives considered

- **Raw docker compose per user** (no Coder): fails auth, proxying, lifecycle
  UI, autostop — we would rebuild Coder.
- **Devcontainers/Codespaces-style CLI**: no multi-user web experience.
- **Kubernetes Coder templates**: out of scope (ADR-0001).

## Consequences

- ✅ Least custom code; Coder is not forked, only configured (original plan
  rule: do not fork Coder).
- ⚠️ Coder server compromise = host compromise via the socket; mitigated by
  pinning the image, HTTP-only POC endpoint being SG-restricted, and no
  untrusted signups (see docs/architecture/security-model.md §5).
