# Backup & restore

## Backup

```bash
make backup            # or: scripts/backup.sh
# -> backups/<UTC-stamp>/
#     coder.sql.gz, litellm.sql.gz        (platform metadata)
#     coder-<owner>-<ws>-home.tar.gz      (every workspace volume)
# keeps the newest 7 stamps on the host
```

Run it:

- before deleting any workspace that ever held real work,
- before `terraform destroy` / platform-data restores,
- weekly as the baseline cadence (calendar the operator owns).

Honest limits: copies live **on the same host**. For real resilience,
rsync the latest `backups/<stamp>/` off the instance after taking it
(S3 upload is deferred — TASKS.md). A backup that never left the host
protects only against app-level corruption, not host loss.

## Restore

```bash
scripts/restore.sh <stamp>     # interactive double-confirm
make restart
```

- Databases are dropped and recreated from the dump (connections killed).
- Workspace volumes are **replaced** by the archive's contents — anything
  written after that backup is lost.
- Coder workspace *records* come from the coder DB dump; workspaces whose
  volumes were created after the dump will exist as records without volume
  content (delete/recreate those).

## Verify a backup is usable

```bash
gunzip -t backups/<stamp>/coder.sql.gz          # archive integrity
tar -tzf backups/<stamp>/coder-*-home.tar.gz | head
```

Restore drills belong in `docs/runbooks/workspace-recovery.md`.
