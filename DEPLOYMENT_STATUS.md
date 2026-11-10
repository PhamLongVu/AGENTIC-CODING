# Deployment status

# ⛔ NOT DEPLOYED — no AWS resources exist for this project

| | |
|---|---|
| **AWS account activity** | none — zero resources created, changed or destroyed |
| **`terraform apply` runs** | zero (validate/plan only, ever) |
| **Local stack** | code written; last green local run 2026-11-10 (PROJECT_STATUS.md test log); full verification pass pending |
| **CI/CD** | workflows committed; deploy workflow is `workflow_dispatch` + environment reviewer + approval-reference secret, and **intentionally stops before deployment** — the operator deploys per runbook |

## What exists vs. what doesn't

| Layer | Written (in repo) | Actually running |
|---|---|---|
| Local compose stack (postgres, LiteLLM, Coder) | ✅ | local only, dev machine |
| Workspace image + template | ✅ | image built once locally (2026-11-10) |
| Terraform (VPC/IAM/EC2) | ✅ validated text | ❌ never applied |
| AWS compose override + host bootstrap | ✅ | ❌ never executed on AWS |
| Post-deploy validation | ✅ script | ❌ nothing to validate |

## Gate to any deployment (baseline rule #2)

1. Owner approval **in the conversation** — for AWS resources generally and
   again per deploy.
2. `make aws-plan` output reviewed (cost + blast radius).
3. `deploy/scripts/bootstrap-host.sh` executed by the operator on the
   instance (runbook: `docs/operations/deployment.md`).
4. `deploy/scripts/validate-deployment.sh` green, results recorded in
   PROJECT_STATUS.md.

Until all four: this file's banner stays **NOT DEPLOYED**.
