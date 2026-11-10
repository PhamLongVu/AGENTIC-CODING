# Runbook: workspace recovery

## "My workspace won't start / agent never connects"

1. `docker ps -a | grep coder-ws-<owner>-<ws>` — does the container exist?
   - No container, build stuck: Coder UI → Builds → check the latest build
     log (usually template/image issue; see troubleshooting.md).
   - Container restarting/crashed: `docker logs <container>`; the two most
     common are image missing on the host (`make build-workspace`) and
     OOM (profile too small).
2. Container up, agent down: workspace → `coder-agent` log (UI) — network
   reachability to CODER_ACCESS_URL (extra_hosts / port publish).
3. Nuclear-but-safe: **Stop, then Start** the workspace. Rebuilds the
   container against the same volume; data survives (tested in
   `tests/integration/test_persistence.sh`).

## "I deleted a file / my project is broken"

- Code files: git is the recovery path (workspace has git; the volume has
  no snapshots).
- Volume-level recovery only from the latest backup:
  `scripts/restore.sh <stamp>` — **restores ALL volumes**; coordinate with
  other users before running. Single-volume surgical restore:
  extract one `coder-*-home.tar.gz` over that volume manually.

## "Workspace deleted by accident"

If deletion just happened and the volume is still present (docker keeps
volumes until removed — deletion removes them, but check):
`docker volume ls | grep coder-`. If gone: restore from backup (all
volumes), or accept the loss. Prevention: `make backup` before any
workspace deletion (offboarding.md step 3).

## "Host lost / rebuild everything"

1. Fresh instance (terraform apply after owner approval).
2. `deploy/scripts/bootstrap-host.sh`.
3. Copy the last off-host backup to `backups/<stamp>/` and
   `scripts/restore.sh <stamp>`.
4. Users re-create workspaces (volumes restored first ⇒ data reappears).
