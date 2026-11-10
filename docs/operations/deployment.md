# AWS POC Deployment (prepared — NOT deployed)

> **STATUS: Documentation and Terraform only. No AWS resources have been
> created. Deployment requires explicit owner approval per
> `CONFIGURATION_BASELINE.md` §9.**

## 1. What gets provisioned (Terraform, `infra/terraform/`)

| Resource | Spec | Purpose |
|---|---|---|
| VPC | 10.42.0.0/24, single AZ, 1 public subnet | minimal network |
| Security group | ingress 22 (admin CIDR), 7080 (POC endpoint, admin CIDR); egress restricted-but-sufficient | boundary |
| EC2 instance | `m6a.2xlarge`, Ubuntu 24.04, `t3`-equivalent burst not needed, 200 GiB gp3 root | host for everything |
| IAM instance profile | `bedrock:InvokeModel*` on foundation models in `ap-southeast-1` only | LiteLLM→Bedrock |
| IMDS options | `HttpTokens=required`, `HttpPutResponseHopLimit=1` | block container metadata access |
| Key pair | operator-provided | SSH access |

Explicitly NOT created: EKS, RDS, ElastiCache, NAT Gateway (not needed: public
subnet with controlled egress), ECR, S3 (backups land on-instance until a
requirement is demonstrated).

## 2. Cost model (ESTIMATES — verify with AWS Pricing Calculator before approval)

Assumptions: ap-southeast-1, on-demand, Linux.

| Item | Rate (est.) | 24/7 cost | Duty-cycle cost* |
|---|---|---|---|
| `m6a.2xlarge` (8 vCPU/32 GiB) | ~USD 0.35–0.40/h | ~USD 252–288/mo | ~USD 62–70/mo |
| EBS root 200 GiB gp3 | ~USD 0.08/GB-mo | USD 16/mo | USD 16/mo |
| EBS snapshots (on demand) | ~USD 0.05/GB-mo | ~USD 2–5/mo | ~USD 2–5/mo |
| **Total** | | **~USD 270–309 — OVER BUDGET** | **~USD 80–91 — within USD 200** |

*Duty-cycle assumption: workspaces autostop after 45 min idle; the instance
itself runs 24/7 (it is a single instance — stopping it takes the whole
platform down; instance stop/start as a cost lever is a documented option via
`scripts/aws/instance-stop.sh` for e.g. nights/weekends, trading a ~3–5 min
cold start). **The duty-cycle figure is the operating assumption for the POC;
the 24/7 figure is the ceiling that must never be silently accepted.**

GPU: none. Data transfer: negligible at POC scale.

**Honest capacity statement**: within USD 200/month this instance supports
5 concurrent **Small** workspaces comfortably, ~2–3 concurrent **Medium**.
Five concurrent Medium does not fit (needs ~12 vCPU/24 GiB + platform
overhead). Phase 4 benchmarks will produce measured numbers.

## 3. IAM permissions required for deployment

The deploying operator (via IAM Identity Center) needs, scoped to the POC
account/resources:

- `ec2:*` on the created resources (or full EC2 in this dedicated account),
- `iam:CreateRole/AttachRolePolicy/PassRole` limited to the paths Terraform
  manages,
- `bedrock:InvokeModel*` **only** attached to the instance profile role
  (never to humans),
- SSM Session Manager (optional) instead of SSH key distribution.

Least-privilege statement documents are in `infra/terraform/iam-policies.md`.

## 4. Security implications (pre-deployment disclosure)

1. POC endpoint is plain HTTP on :7080 — SG must be restricted to the
   operator/office CIDR range (Terraform variable `admin_cidr_ipv4`). Browser
   traffic (including login) is unencrypted on the wire. Accepted for POC only.
2. The EC2 instance profile carries Bedrock invoke rights — confined to
   LiteLLM by IMDS hop limit 1 (all other containers are bridge-networked and
   metadata-blocked). Verified by `tests/aws/test_imds.sh` after deploy.
3. SSH exposed to `admin_cidr_ipv4` only; key-based.
4. `.env` on the instance holds platform secrets (mode 600 root). Backup
   procedures exclude it from unencrypted storage.

## 5. Deployment runbook (manual, after approval)

```bash
# 1. From an operator machine with IAM Identity Center credentials:
cd infra/terraform && terraform init && terraform plan -out poc.tfplan
# 2. Review plan; confirm 0 paid resources beyond those approved above.
terraform apply poc.tfplan
# 3. Configure the host (prints from Terraform outputs):
scripts/aws/bootstrap-host.sh   # installs docker, copies repo, writes .env
# 4. Bring up the platform:
make up deploy-target=aws bootstrap-coder
# 5. Validate: scripts/aws/validate-deployment.sh  (health, IMDS block, ports)
```

## 6. Rollback / cleanup

- Full teardown: `terraform destroy` — deletes the instance, volumes and IAM
  role. **Destructive: destroys all workspace data.** Requires owner approval.
- Partial: `scripts/aws/instance-stop.sh` stops billing for compute (EBS still
  bills) while keeping state.
- Workspace data export before teardown: `scripts/backup.sh all` → tarballs on
  operator machine.
