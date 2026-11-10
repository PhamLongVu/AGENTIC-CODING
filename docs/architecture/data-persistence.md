# Data persistence

ADR-0006 is the decision record; this is the operational view.

## What persists, where

| Data | Location | Lifetime |
|---|---|---|
| Project files | `/home/coder/projects` (volume) | workspace lifetime |
| OpenCode config/state | `/home/coder/.config/opencode`, `/home/coder/.local/share/opencode` | workspace lifetime |
| code-server settings/extensions | `/home/coder/.local/share/code-server` | workspace lifetime |
| Developer git/ssh credentials | `/home/coder/.ssh` | workspace lifetime |
| Coder + LiteLLM metadata | postgres volumes (`platform_pgdata`) | until `destroy-dev data` |
| Everything else in the container | writable layer | **destroyed on stop** (intended) |

Volume naming: `coder-<owner>-<workspace>-home`, created by the Coder
template, labelled `managed-by=coder`.

## Quota reality (known limitation)

Docker local volumes cannot hard-enforce a size. Profile sizes
(20/30/50 GiB) are therefore **monitored, not enforced**:

- the workspace agent exposes a Home-volume metadata tile (df of /home/coder)
- 5 Small workspaces = 100 GiB on a 200 GiB root disk leaves host headroom;
  the honest risk is Medium/Large workspaces hoarding disk — watched via the
  tile and `docker system df` (runbook: cost-management).

## Backups

- `make backup` → `backups/<stamp>/`: pg_dump of both DBs + tar of every
  `coder-*-home` volume; keeps newest 7.
- `scripts/restore.sh <stamp>` restores (interactive confirm).
- POC-grade only: on-host copies, no off-instance upload (S3 deferred —
  TASKS.md). Host loss = data loss without a copied-off backup.
- Cadence expectation: before workspace deletions and weekly; see
  `docs/runbooks/workspace-recovery.md`.
