# Rollback

## Application level (compose stack)

Symptom-driven, fastest first:

| Situation | Action |
|---|---|
| bad template push | `scripts/coder/push-template.sh` again from a fixed checkout — pushes a new version and activates it; existing workspaces keep their build until restarted |
| gateway misbehaving | fix `gateway/litellm/config/config-*.yaml`, `docker compose restart litellm` |
| coder upgrade gone wrong | set previous pin in `.env` (`CODER_IMAGE`), `docker compose up -d coder` — postgres schema is forward-migrated; downgrades are NOT guaranteed, prefer restore-from-backup |
| whole stack wedged | `make restart` (data kept) |
| corrupted platform data | `scripts/restore.sh <stamp>` (destructive; see backup-restore.md) |

## Infrastructure level (AWS — after deployment is approved)

Rollback granularity is intentionally coarse (single instance):

1. **Stop the bleeding, keep the data**: `deploy/scripts/instance-stop.sh stop`
   — compute charges stop, EBS + EIP remain.
2. **Revert infra**: fix terraform, `terraform plan`, review, apply — with
   owner approval, same as any apply.
3. **Full teardown**: `cd infra/terraform/environments/dev && terraform destroy`
   — **DESTROYS ALL WORKSPACE DATA** (root volume). Only after owner
   approval AND a taken-off-instance backup. Never automated.

## What has no rollback

- Workspace volume deletion (`docker volume rm` / workspace delete) — final.
  Backup first (runbook: workspace-recovery.md).
- Postgres downgrade after coder migrated its schema — restore instead.
