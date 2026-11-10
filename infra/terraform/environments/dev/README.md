# POC environment (dev)

**STATUS: PREPARED, NEVER APPLIED.** No AWS resources exist for this stack.
Applying requires explicit owner approval recorded in the conversation
(non-negotiable #2 in `CLAUDE.md`; gate = `TASKS.md` item 3.5).

## What it creates (all costs stoppable)

| Resource | Type | Cost note |
|---|---|---|
| VPC + subnet + IGW + route | vpc module | free |
| IAM role + instance profile | iam module | free; Bedrock invoke only |
| m6a.2xlarge + 200 GiB gp3 root + EIP | ec2 module | ~USD 0.39/hr on-demand; stop when idle |
| Security group | 22 admin-cidr, 7080 dev-cidr only | free |

Full cost model incl. duty-cycle assumptions: `docs/operations/deployment.md` §3.

## Commands (validate/plan only — apply is gated)

```bash
make terraform-validate           # containerized validate, no creds needed for syntax
cd infra/terraform/environments/dev
terraform init                    # on the host with credentials
terraform plan -out poc.tfplan    # REVIEW: resources, cost, IAM scope
# terraform apply poc.tfplan      # ONLY after owner approval
```

Remote state: not configured for the POC (local state is git-ignored).
The original plan's S3+locking backend template lives in `backend.tf.example`
— enable it before any second environment or team use.
