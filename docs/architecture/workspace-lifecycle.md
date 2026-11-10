# Workspace lifecycle

Semantics required by the execution plan, implemented by the Coder
`docker-standard` template (`workspace/templates/standard/main.tf`).

## Create

```text
operator/developer -> Coder API -> provisioner (docker provider)
  -> docker volume   coder-<owner>-<ws>-home          (persistent /home/coder)
  -> docker network  ws-<owner>-<ws>                  (peer isolation)
  -> docker container coder-ws-<owner>-<ws>           (non-root, capped)
       PID 1 = coder agent -> startup_script.sh
         -> seeds ~/.config/opencode/opencode.json (once)
         -> starts code-server (127.0.0.1:8080) + opencode (127.0.0.1:4096)
  -> Coder apps register; healthchecks flip to healthy
```

Parameter every workspace gets: `litellm_virtual_key` (per-developer,
operator-issued) — never the master key.

## Stop (manual or autostop)

- Default idle autostop: **45 min** without a connected client (workspace
  TTL set at creation; ADR-0007). No 24/7 workspaces in the POC.
- Container is removed (`start_count = 0`). Volume + network are kept.
- Data preserved: everything under `/home/coder` (projects, opencode state,
  code-server settings, `.ssh`).
- Disposed: the container writable layer (e.g. `/tmp`) — by design.

## Start

- New container from the same pinned image; the SAME volume re-attached.
- Agent reconnects, services restart, health checks green.
- Continuity proven by `tests/integration/test_persistence.sh`.

## Delete (explicit, operator/owner confirmed)

- Workspace delete in Coder destroys container **and volume**.
- Deletion of a workspace with real data: run `scripts/backup.sh` first
  (runbook: `docs/runbooks/workspace-recovery.md`).

## States and who can do what

| Action | Developer (own ws) | Operator (admin) | Other developer |
|---|---|---|---|
| create / start / stop | ✅ | ✅ | ❌ |
| delete own workspace | ✅ (confirm dialog) | ✅ | ❌ |
| access another's workspace | ❌ (404 in UI/API) | ✅ (break-glass, audited) | ❌ |
