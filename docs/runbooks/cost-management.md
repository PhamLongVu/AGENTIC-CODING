# Runbook: cost management (USD 200/month ceiling)

## Cost model recap (full detail: docs/operations/deployment.md §3)

| Lever | Monthly effect |
|---|---|
| 24/7 m6a.2xlarge + 200 GiB + EIP | ~USD 270–309 ❌ over budget |
| Duty-cycle (autostop 45m, nights/weekends stopped) | ~USD 80–91 ✅ |
| Bedrock | pass-through, capped USD 20/month/developer key |
| ElastiCache/RDS/etc | USD 0 — not deployed (baseline) |

## Daily levers

1. **Workspace autostop** is on by default (45 min). Verify occasionally:
   every workspace row shows its TTL; nothing runs 24/7.
2. **Instance stop/start** (`deploy/scripts/instance-stop.sh stop|start`) —
   the big lever (~USD 0.39/hr). EIP (~USD 3.6/mo while stopped) + root
   volume (~USD 19/mo) keep accruing; compute does not.
3. **Gateway budgets**: per-key USD 20/month cap; check spend weekly:
   `curl -s http://127.0.0.1:4000/key/list -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '.keys[] | {key_alias, spend, max_budget}'`
   (never print keys themselves).

## Weekly checklist (operator, ~5 min)

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep coder-ws   # anything running that shouldn't?
docker system df                                                # disk creep
make backup                                                     # + copy off-host
# aws ec2 describe-instances ... State, and compare month-to-date spend in AWS Billing
```

## Escalation rules

- MTD spend projected > USD 150 → instance-stop during non-work hours
  becomes mandatory; owner informed.
- Any single developer's key spend > USD 15 → notify + tighten rpm.
- Budget ceiling is **infrastructure**; Bedrock pass-through is tracked
  separately but reported together to the owner.

## Before any capacity increase

ADR-0007: measured numbers must be published (Phase 4) before any claim
that >5 concurrent workspaces fit — and any bigger instance is a baseline
change requiring owner approval.
