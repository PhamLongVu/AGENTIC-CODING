# Runbook: offboarding a developer

Order matters: cut AI access first, then data export, then accounts.

## 1. Stop their workspaces

Coder UI/API: stop (not delete yet) every workspace they own — preserves
data for the retention window while removing compute.

## 2. Revoke their gateway key (immediate)

```bash
KEY_HASH=<from gateway /key/list, alias = username>
curl -X POST http://127.0.0.1:4000/key/delete \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" -d '{"keys":["'"$KEY_HASH"'"]}'
```

Effect is instant (tested: revoked key → 401). Their workspaces' env still
holds the old key value — harmless once revoked.

## 3. Export / retain workspace data

```bash
make backup          # captures all volumes incl. theirs
docker run --rm -v coder-<user>-<ws>-home:/src:ro -v $PWD:/out alpine:3.20 \
  tar czf /out/<user>-home-$(date +%F).tar.gz -C /src .
```

Copy off-host if retention matters (backup-restore.md honest limits).

## 4. Delete coder account + workspaces

After the retention window (owner's call; default: at the end of the last
day): delete workspaces (volumes destroyed — step 3 already exported), then
the user. Suspend-first alternative: set user status `suspended` instead of
deleting, if a same-name rehire is plausible.

## 5. Checklist

- [ ] workspaces stopped
- [ ] gateway key revoked (401 verified)
- [ ] data exported off-host (if retention)
- [ ] workspaces deleted (volumes gone)
- [ ] coder user deleted/suspended
- [ ] spend row archived (`/key/list` output into the offboarding ticket)
