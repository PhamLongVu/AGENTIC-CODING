# ADR-0006: Workspace persistence via per-workspace Docker volumes

- Status: CONFIRMED (baseline: persistent storage per developer; runtime stops
  when idle)

## Context

The original plan persisted workspaces on EBS PVCs. On a single Docker host,
the equivalent must survive container stop/start (and container recreation)
without paying for one EBS volume per workspace.

## Decision

Each workspace gets a named Docker volume (`coder-<owner>-<ws>-home`) mounted
at `/home/coder`. All persistent state lives under that path by convention:

```text
/home/coder/projects/                    # project files
/home/coder/.config/opencode/            # OpenCode config
/home/coder/.local/share/opencode/       # OpenCode sessions/state
/home/coder/.local/share/code-server/    # IDE settings/extensions
/home/coder/.ssh/                        # developer git credentials
```

- The Coder template parameterizes the volume size by profile (20/30/50 GiB).
- Stop ⇒ container stopped/removed, volume kept. Start ⇒ new container, same
  volume. Delete (explicit user confirmation in UI) ⇒ volume destroyed.
- Container writable layer is treated as disposable; nothing required for
  continuity is written outside `/home/coder`.
- Backups: `scripts/backup.sh` (volume tarball + pg_dump) — POC-grade, on-host.

## Consequences

- ✅ Zero extra AWS cost; fast start (no volume detach/attach dance).
- ✅ Same-home-directory guarantee makes "OpenCode and code-server share the
  project directory" true by construction (verified by tests).
- ⚠️ All workspaces share the 200 GiB root EBS volume; enforcement of
  per-workspace quota is Docker volume size awareness (warn at 80% via
  health script) rather than hard block — documented limitation.
- ⚠️ Volume data lives only on this host. Host loss = data loss unless
  `scripts/backup.sh` is run on schedule (ops runbook).
