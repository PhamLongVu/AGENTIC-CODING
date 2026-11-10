# Project Execution Plan: Cloud Coding Platform

> **STATUS: SUPERSEDED IN PART — see `docs/CONFIGURATION_BASELINE.md` (single source of truth).**
>
> This document is the original execution plan, received 2026-11-10. It was written
> for a **50+ developer, EKS-based production platform**. The project owner has since
> confirmed a **re-scoped MVP baseline** (single EC2 instance, Docker Compose,
> 5 concurrent workspaces, USD 200/month, AWS ap-southeast-1).
>
> The document is retained in full because most of its *functional* requirements,
> security constraints, lifecycle semantics, test procedures, approval gates, and
> the Definition of Done remain binding. Where its *technical implementation
> details* conflict with the confirmed baseline, the baseline wins.
>
> ## Reconciliation of conflicts (baseline wins)
>
> | # | Area | Original plan says | Confirmed baseline resolution |
> |---|---|---|---|
> | 1 | Scale | 50+ developers, 30–50 concurrent workspaces | **5 concurrent workspaces** initially; design notes for growth kept, capacity claims must be re-benchmarked |
> | 2 | Compute | AWS EKS + managed node groups / Karpenter | **Single EC2 instance**; EKS explicitly out of scope for MVP |
> | 3 | Orchestration | Helm charts, Kubernetes manifests | **Docker Compose**; Helm/K8s out of scope for MVP |
> | 4 | Database | AWS RDS PostgreSQL | **PostgreSQL as a Docker container** on the EC2 instance |
> | 5 | Cache | AWS ElastiCache Redis | **None** — single LiteLLM replica needs no shared Redis cache; revisit only with a demonstrated requirement |
> | 6 | Networking | 3 AZs, public/private/data subnets, NAT | **Single instance in a single AZ**, minimal VPC; multi-AZ out of scope |
> | 7 | Workspace runtime | Kubernetes Pods + PVCs (EBS CSI) | **Docker containers + named Docker volumes** on the instance, provisioned by Coder's Docker provider |
> | 8 | Workspace profiles | Small 2/4/30, Medium 4/8/50, Large 8/16/100 (vCPU/GiB/GiB) | **Small 1/2/20, Medium 2/4/30, Large 4/8/50** |
> | 9 | Budget | Not quantified | **USD 200/month hard ceiling** for infrastructure |
> | 10 | Region | Unspecified | **ap-southeast-1 (Singapore)** |
> | 11 | Domain/TLS | Production domain, TLS everywhere | **Temporary endpoint, no custom domain** for POC; TLS posture documented as a known limitation |
> | 12 | AI provider | Unspecified | **AWS Bedrock**, reachable **only** through LiteLLM |
> | 13 | Registry/storage | ECR, S3 for backups | **Deferred** — not required for MVP; local registry pull-through only if a demonstrated need arises |
> | 14 | Monitoring | CloudWatch + Prometheus/Grafana | **Minimal**: docker health checks + host-level scripts for POC; full observability deferred |
> | 15 | Auth | OIDC for developers | **AWS IAM Identity Center for AWS administration only**; developer-facing POC auth = Coder built-in accounts; OIDC remains the documented extension path |
> | 16 | Agent model | Claude Code implements, Codex reviews | **Owner ruling 2026-11-10: no separate Codex agent** — Claude does implementation *and* review. The review duty becomes a fresh-eyes self-review pass (discipline defined in `AGENTS.md` §Review pass) before any security sign-off; the owner may still assign an external human reviewer for 4.7 |
>
> Phases 2–10 of the original plan are re-scoped by the baseline into the milestone
> plan in `TASKS.md` (local-first, then AWS POC, then validation). Nothing in
> the original plan is deleted; items that no longer apply at MVP scope (EKS
> acceptance criteria, RDS backups, EKS-specific security tests) are marked there as
> **deferred** with their trigger conditions.
>
> **Repository layout note**: the implemented repo follows §3's structure for
> everything that is implemented (workspace/, gateway/, deploy/, infra/,
> tests/, docs/{architecture,operations,decisions/ADR,runbooks}, root tracking
> files, .github/workflows). Per §3's own rule ("create each directory when
> its implementation begins") the deferred components' directories are
> **omitted**: eks/, rds/, redis/, ecr/, s3/, monitoring/, helm/,
> kubernetes/, prod/, load tests, platform-api source (README-only
> placeholder explaining the trigger). `CODEX.md` from §3 is likewise
> omitted per reconciliation row 16 — its content lives in `AGENTS.md`.

## 1. Project Overview

### Objective

Build a self-hosted cloud coding platform on AWS for 50+ developers.

Each developer must have an isolated, persistent cloud workspace accessible through a browser.

The platform must support two experiences:

1. Chat-first AI coding using OpenCode Web.
2. IDE-first coding using code-server.

Both experiences must operate on the same filesystem and project directory.

The developer should be able to:
- Log in from any device.
- Start their workspace.
- Open OpenCode Chat.
- Open browser-based VS Code.
- Access terminal.
- Clone and work with Git repositories.
- Run Python, Node.js, tests, builds and other development tools.
- Stop their workspace without losing data.
- Start the workspace later and continue working.
- Use AI models through a centralized AI gateway.
- Have individual usage and spending tracked.

### Project owner

One human owner is responsible for:
- Architecture approval.
- AWS account and IAM access.
- Cost approval.
- Domain and identity provider configuration.
- Approving destructive operations.
- Final production acceptance.

Coding agents are responsible for implementation, testing, documentation and troubleshooting.

### Target capacity

Initial target:
- 50+ registered developers.
- 30 concurrent workspaces as initial capacity target.
- Architecture designed to scale to 50 concurrent workspaces.
- Persistent storage for all registered developers.
- Independent workspace isolation.

Do not claim the system supports 50 concurrent users until load tests demonstrate it.

---

## 2. Architecture Decisions

Use the following components.

| Component | Technology | Responsibility |
|---|---|---|
| Workspace control plane | Coder | User access, workspace provisioning, lifecycle |
| Cloud compute | AWS EKS | Run developer workspaces |
| Infrastructure | Terraform | Provision AWS resources |
| Container deployment | Helm | Install platform components |
| AI coding agent | OpenCode | AI coding and agent sessions |
| Browser IDE | code-server | VS Code-like browser IDE |
| AI gateway | LiteLLM | Model routing, virtual keys, budgets |
| Database | AWS RDS PostgreSQL | Coder and LiteLLM metadata |
| Cache | AWS ElastiCache Redis | LiteLLM shared cache and rate-limit state |
| Persistent storage | EBS gp3 | Workspace data |
| Object storage | S3 | Backups and artifacts |
| Container registry | ECR | Workspace images |
| Monitoring | CloudWatch + Prometheus/Grafana | Infrastructure and application observability |
| Authentication | OIDC | Centralized login |

### Important architectural rules

1. Do not fork Coder.
2. Do not fork OpenCode.
3. Do not build a custom IDE.
4. Do not build a custom workspace scheduler.
5. Do not build a custom frontend in MVP.
6. Do not expose workspace services directly to the public Internet.
7. Do not share a single workspace between developers.
8. Do not store persistent project data in the container writable layer.
9. Do not use a shared master AI API key inside every workspace.
10. Pin all production images and dependency versions. Avoid `latest`.

### Workspace topology

Each developer gets one independently provisioned workspace.

A workspace contains:

- One Kubernetes Pod or equivalent isolated workspace runtime.
- One Coder Agent.
- One OpenCode server.
- One code-server process.
- One persistent EBS PVC.
- One developer-specific AI gateway credential.
- Resource requests and limits.

OpenCode and code-server must use the same persistent project directory.

Example:

```text
/home/coder/
├── projects/
├── .config/
│   └── opencode/
├── .local/
│   └── share/
│       └── opencode/
└── .ssh/
```

The actual persistent paths must be verified against the selected OpenCode version.

### Workspace lifecycle

Create:
- Coder provisions workspace resources.
- Kubernetes creates the Pod.
- PVC is attached.
- Workspace services start.
- Health checks become healthy.

Stop:
- Stop or remove compute.
- Preserve PVC.
- Preserve user project data.
- Preserve OpenCode data according to the selected persistence configuration.

Start:
- Recreate workspace runtime.
- Reattach existing PVC.
- Restart OpenCode and code-server.
- Verify access to previous project data.

Delete:
- Require explicit confirmation for persistent storage deletion.
- Support a retention period.
- Never automatically delete a PVC when stopping a workspace.

---

## 3. Repository Structure

Create one monorepo:

```text
cloud-coding-platform/
│
├── README.md
├── AGENTS.md
├── CLAUDE.md
├── CODEX.md
├── Makefile
├── .env.example
├── .gitignore
│
├── docs/
│   ├── architecture/
│   │   ├── overview.md
│   │   ├── aws-network.md
│   │   ├── workspace-lifecycle.md
│   │   ├── security-model.md
│   │   └── data-persistence.md
│   │
│   ├── operations/
│   │   ├── deployment.md
│   │   ├── rollback.md
│   │   ├── backup-restore.md
│   │   ├── incident-response.md
│   │   └── troubleshooting.md
│   │
│   ├── decisions/
│   │   └── ADR/
│   │
│   └── runbooks/
│       ├── onboarding.md
│       ├── offboarding.md
│       ├── workspace-recovery.md
│       └── cost-management.md
│
├── infra/
│   └── terraform/
│       ├── modules/
│       │   ├── vpc/
│       │   ├── eks/
│       │   ├── rds/
│       │   ├── redis/
│       │   ├── ecr/
│       │   ├── s3/
│       │   ├── iam/
│       │   └── monitoring/
│       │
│       └── environments/
│           ├── dev/
│           └── prod/
│
├── deploy/
│   ├── helm/
│   │   ├── coder/
│   │   ├── litellm/
│   │   └── monitoring/
│   │
│   ├── kubernetes/
│   │   ├── namespaces/
│   │   ├── network-policies/
│   │   ├── resource-quotas/
│   │   ├── storage-classes/
│   │   └── policies/
│   │
│   └── scripts/
│
├── workspace/
│   ├── images/
│   │   ├── base/
│   │   └── development/
│   │
│   ├── opencode/
│   │   ├── config/
│   │   └── startup/
│   │
│   ├── code-server/
│   │   └── config/
│   │
│   ├── scripts/
│   └── templates/
│       ├── standard/
│       ├── python/
│       └── fullstack/
│
├── gateway/
│   └── litellm/
│       ├── config/
│       ├── policies/
│       └── scripts/
│
├── platform-api/
│   └── README.md
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── security/
│   ├── infrastructure/
│   └── load/
│
├── scripts/
│   ├── bootstrap.sh
│   ├── validate.sh
│   ├── deploy-dev.sh
│   ├── backup.sh
│   └── destroy-dev.sh
│
└── .github/
    └── workflows/
        ├── lint.yaml
        ├── test.yaml
        ├── build-images.yaml
        ├── terraform-plan.yaml
        └── deploy.yaml
```

Do not create empty modules just to fill this structure. Create each directory when its implementation begins.

The `platform-api` module is optional and must remain minimal until a concrete integration requirement is identified.

---

## 4. Coding Agent Operating Model

Use Claude Code as the primary implementation orchestrator.

Use Codex as an independent reviewer and test engineer.

### Claude Code responsibilities

- Read the project plan and architecture.
- Create implementation tasks.
- Implement features.
- Write Terraform and Kubernetes configuration.
- Build Docker images.
- Write tests.
- Run local tests.
- Fix implementation failures.
- Update documentation.
- Maintain the project status file.

### Codex responsibilities

- Review architecture decisions.
- Review Terraform for security and correctness.
- Review Kubernetes manifests.
- Review container security.
- Find data-loss and isolation risks.
- Review test coverage.
- Run independent validation.
- Report issues with severity and remediation.

### Agent collaboration rules

1. Only one agent owns implementation of a given module at a time.
2. Do not let Claude Code and Codex concurrently edit the same files.
3. Claude Code creates a branch for each milestone.
4. Codex reviews the branch after implementation.
5. Claude Code fixes review findings.
6. Human owner approves merge to main.
7. Use separate Git worktrees when agents need to work in parallel.
8. Every task must have acceptance criteria.
9. Every completed task must include test evidence.
10. Do not mark a task complete based only on code generation.

### Required project tracking files

Maintain:

- `PROJECT_STATUS.md`
- `TASKS.md`
- `DECISIONS.md`
- `KNOWN_ISSUES.md`
- `DEPLOYMENT_STATUS.md`

Update them after every milestone.

---

# 5. Implementation Phases

## Phase 0 — Repository and architecture initialization

Estimated duration: 2–3 days.

### Tasks

1. Inspect the current repository.
2. Create the repository structure.
3. Write the architecture overview.
4. Write security model.
5. Write workspace lifecycle documentation.
6. Create ADRs for important decisions.
7. Create `.env.example`.
8. Create `Makefile`.
9. Create agent instructions.
10. Create task tracking files.

### Architecture decisions to document

- AWS region.
- VPC CIDR.
- EKS Kubernetes version.
- Workspace CPU/RAM profiles.
- Persistent storage strategy.
- Authentication method.
- OpenCode version.
- code-server version.
- LiteLLM version.
- Database topology.
- Workspace ingress model.
- Backup and retention policy.

Do not invent AWS account IDs, ARNs, domain names or secrets.

Use placeholders for unknown configuration.

### Acceptance criteria

- Repository structure is coherent.
- All important architectural choices have ADRs.
- Security and persistence assumptions are documented.
- No cloud resources have been created.
- A human-readable implementation roadmap exists.

---

## Phase 1 — Local development environment

Estimated duration: 3–5 days.

Goal: Prove that the applications work together before spending money on AWS.

### Tasks

1. Create a Docker Compose environment.
2. Run PostgreSQL for local integration testing.
3. Run LiteLLM.
4. Build the workspace Docker image.
5. Install OpenCode in the image.
6. Install code-server.
7. Start both services.
8. Configure both services to access the same project directory.
9. Configure a test AI provider using a development credential.
10. Test AI requests through LiteLLM.

### Workspace image requirements

- Non-root user.
- Git.
- Bash.
- Python.
- Node.js.
- npm/pnpm where appropriate.
- Common build utilities.
- OpenCode.
- code-server.
- Health check endpoint or process checks.
- Graceful shutdown.
- Structured logs.

Do not bake API keys into the image.

### Tests

- Container starts successfully.
- OpenCode server is healthy.
- code-server is healthy.
- Both can access the same project.
- A file edited through IDE is visible to OpenCode.
- A file edited by OpenCode is visible through IDE.
- Terminal commands work.
- Git clone and commit work.
- Restarting the container preserves mounted test data.
- AI requests reach LiteLLM.

### Acceptance criteria

A developer can use the same project directory through:
- Browser IDE.
- OpenCode Web.
- Terminal.

No AWS infrastructure is required yet.

---

## Phase 2 — AWS infrastructure foundation

Estimated duration: 1 week.

Goal: Create reproducible AWS infrastructure using Terraform.

### AWS environment

Use a dedicated AWS account or isolated environment.

Create:
- VPC.
- Three Availability Zones where available.
- Public subnets.
- Private application subnets.
- Private workspace subnets.
- Private data subnets.
- Internet Gateway.
- NAT design.
- Security groups.
- EKS cluster.
- ECR repositories.
- S3 buckets.
- RDS PostgreSQL.
- Redis if required by the selected LiteLLM topology.
- IAM roles.
- Secrets Manager entries.

### Cost-conscious deployment

Use small development sizing initially.

Do not deploy a full 50-user production capacity just to test the architecture.

The Terraform variables must support:
- Environment name.
- AWS region.
- VPC CIDR.
- EKS node sizes.
- Minimum and maximum node counts.
- Database size.
- Storage size.
- Environment-specific tags.

### Terraform requirements

- Remote state in S3.
- State locking using the currently supported Terraform backend locking mechanism.
- Encryption at rest.
- Versioning.
- State access restricted to deployment identities.
- Separate state per environment.
- No secrets in Terraform variables or state unless unavoidable and explicitly documented.
- Consistent naming and tags.
- `terraform fmt`.
- `terraform validate`.
- `tflint`.
- Security scanning.
- `terraform plan` before apply.

Do not hardcode credentials.

### EKS requirements

- Managed EKS control plane.
- Private worker nodes.
- Managed node groups or Karpenter-based workspace capacity.
- EBS CSI Driver.
- AWS Load Balancer Controller.
- Metrics Server.
- Cluster autoscaling strategy.
- Namespace separation.
- Pod Security Standards.
- Resource quotas.
- Network policies.

### Important security constraints

- No public IP for workspace Pods.
- No privileged workspace containers by default.
- No Docker socket mount.
- No hostPath mount.
- No host networking.
- Run workspace containers as non-root.
- Apply default-deny network policies where compatible with Coder connectivity.
- Explicitly allow required egress.
- Do not give workspace Pods broad AWS IAM permissions.

### Human approval gate

Before `terraform apply`, report:

- AWS region.
- Resources to be created.
- Estimated monthly cost.
- Publicly exposed resources.
- IAM permissions.
- Database configuration.
- NAT and networking costs.

Wait for human approval.

### Acceptance criteria

- Terraform validates.
- Terraform plan is reviewed.
- EKS becomes healthy.
- Worker nodes join successfully.
- ECR is accessible.
- EBS CSI Driver is healthy.
- Private workspace nodes can pull images.
- No workspace service is publicly exposed.

---

## Phase 3 — Deploy Coder

Estimated duration: 3–5 days.

### Tasks

1. Install Coder using its supported Helm deployment method.
2. Configure PostgreSQL.
3. Configure persistent application data as required.
4. Configure TLS.
5. Configure ingress.
6. Configure OIDC if an identity provider is available.
7. Create an administrator account.
8. Configure workspace templates.
9. Configure workspace resource limits.
10. Configure workspace startup and shutdown behavior.

### Workspace access

Use Coder's supported workspace application proxy mechanism.

Do not expose OpenCode or code-server with independent public LoadBalancers.

Both services must be accessible only through the authenticated Coder workspace access path.

### Tests

- Admin login works.
- Normal developer login works.
- Unauthorized user cannot access workspace.
- Workspace can be created.
- Workspace can be started and stopped.
- Workspace logs are accessible.
- Workspace application links work.

### Acceptance criteria

Coder is running and can provision a basic workspace on EKS.

---

## Phase 4 — Workspace implementation

Estimated duration: 1 week.

This is the most important phase.

### Build the workspace image

Create a reproducible Dockerfile.

Requirements:
- Pin base image.
- Pin OpenCode version.
- Pin code-server version.
- Run as non-root.
- Include required development tools.
- Support environment configuration.
- Do not include provider secrets.
- Implement graceful shutdown.
- Implement health checks.

### OpenCode

Run OpenCode using its supported server or web command for the pinned release.

Requirements:
- Listen on the expected internal interface.
- Use explicit authentication.
- Do not expose unauthenticated HTTP endpoints.
- Restrict CORS to required origins.
- Persist configuration and session data.
- Do not write persistent state only to the container writable layer.

Verify exact authentication environment variables and flags against the pinned OpenCode release before implementation.

### code-server

Requirements:
- Bind only to the intended workspace network interface.
- Authentication must be handled through the supported access mechanism.
- Avoid public direct exposure.
- Persist settings and extensions if required.
- Open the intended project directory by default.

### Coder template

Create a Kubernetes-based Coder template.

The template must:
- Create one workspace per user.
- Assign stable workspace identity.
- Create persistent storage.
- Set CPU and memory requests/limits.
- Configure OpenCode.
- Configure code-server.
- Configure health checks.
- Configure Coder Agent.
- Expose OpenCode Web as one workspace app.
- Expose code-server as another workspace app.
- Support start/stop.
- Preserve PVC when stopping.
- Avoid automatic PVC deletion.

### Resource profiles

Small:
- 2 vCPU.
- 4 GiB RAM.
- 30 GiB storage.

Medium:
- 4 vCPU.
- 8 GiB RAM.
- 50 GiB storage.

Large:
- 8 vCPU.
- 16 GiB RAM.
- 100 GiB storage.

These are initial profiles. Validate actual scheduling and node packing through load tests.

### Persistence tests

1. Create workspace.
2. Create project directory.
3. Create source file.
4. Create Git repository.
5. Save OpenCode session.
6. Stop workspace.
7. Confirm Pod is removed or stopped.
8. Confirm PVC remains.
9. Start workspace.
10. Confirm source file exists.
11. Confirm Git repository exists.
12. Confirm OpenCode data is retained according to its configured persistence behavior.

### Acceptance criteria

A developer can use:
- OpenCode Web.
- code-server.
- Terminal.

All three use the same persistent project directory.

Workspace data survives stop/start.

---

## Phase 5 — LiteLLM integration

Estimated duration: 4–6 days.

### Tasks

1. Deploy LiteLLM.
2. Connect PostgreSQL.
3. Connect Redis when using multiple gateway replicas or shared rate-limit state.
4. Store master key in AWS Secrets Manager.
5. Store provider credentials in AWS Secrets Manager.
6. Configure supported models.
7. Create developer virtual-key workflow.
8. Configure team budgets.
9. Configure per-user budgets.
10. Configure RPM/TPM limits.
11. Configure usage logging.
12. Integrate OpenCode provider configuration.

### Credential requirements

- Workspace must never receive LiteLLM master key.
- Each developer must have a separate virtual key or appropriately scoped credential.
- Keys must be revocable.
- Keys must be rotatable.
- Keys must not be baked into container images.
- Keys must not be committed to Git.
- Keys must not appear in logs.

### OpenCode provider configuration

Use a custom OpenAI-compatible provider pointing to LiteLLM.

Verify compatibility against the selected OpenCode release.

Test:
- Text requests.
- Tool calls.
- Streaming.
- Long responses.
- Model selection.
- Error handling.
- Token usage reporting.

### Acceptance criteria

- OpenCode successfully calls an AI model through LiteLLM.
- Developer-specific key works.
- Invalid key is rejected.
- Budget limit is enforced.
- Usage is recorded.
- Master key is never accessible to a normal workspace.

---

## Phase 6 — Security hardening

Estimated duration: 1 week.

Security is a release blocker.

### Workspace isolation

Verify:
- Developer A cannot access Developer B's filesystem.
- Developer A cannot access Developer B's Pod.
- Developer A cannot read Developer B's environment variables.
- Developer A cannot access another developer's PVC.
- Developer A cannot access Coder administrative credentials.
- Workspace cannot access Kubernetes API with excessive permissions.
- Workspace cannot access node filesystem.
- Workspace cannot access cloud metadata credentials unnecessarily.

### Network isolation

Verify:
- Workspace A cannot connect to workspace B.
- Workspace cannot access RDS unless explicitly required.
- Workspace cannot access Redis directly.
- Workspace can reach LiteLLM only through the intended endpoint.
- Workspace can reach required Git providers and package registries.
- Ingress is restricted to approved access paths.

### Secrets

- Secrets Manager for AWS secrets.
- Kubernetes Secrets only when needed.
- Avoid environment variables for highly sensitive credentials where possible.
- No secrets in logs.
- No secrets in Git.
- Rotation and revocation documented.

### Container security

- Non-root.
- Read-only root filesystem where compatible.
- Drop Linux capabilities.
- seccomp.
- Resource limits.
- Image scanning.
- Pinned image digests or immutable tags.
- No privileged containers.

### Threat model

Document:
- Malicious repository content.
- Prompt injection in README/issues/code.
- Malicious commands executed by an AI agent.
- Compromised developer account.
- Compromised workspace.
- API key exfiltration.
- Lateral movement.
- Data loss.

Do not claim that prompt injection can be completely prevented. Treat AI agent execution as untrusted code execution.

### Acceptance criteria

All critical security tests pass.

Codex must perform an independent security review.

Human owner must approve the security report.

---

## Phase 7 — Monitoring and operations

Estimated duration: 4–5 days.

### Infrastructure metrics

Monitor:
- EKS node CPU and memory.
- Pod CPU and memory.
- Pending Pods.
- Node scheduling failures.
- EBS volume capacity.
- EBS IOPS and throughput.
- RDS CPU and connections.
- Redis memory and connections.
- ALB errors and latency.
- NAT data processing cost.

### Application metrics

Monitor:
- Coder workspace creation failures.
- Workspace startup time.
- Workspace stop/start failures.
- OpenCode process health.
- code-server process health.
- LiteLLM request count.
- LiteLLM errors.
- Model latency.
- Per-user token usage.
- Per-team spend.

### Alerts

Create alerts for:
- Workspace startup failure.
- PVC mount failure.
- Disk usage above 80%.
- Node memory pressure.
- RDS unavailable.
- LiteLLM unavailable.
- High API error rate.
- Unexpected spending increase.
- Backup failure.

### Operational runbooks

Write procedures for:
- Restarting workspace.
- Recovering workspace after Pod failure.
- Restoring EBS snapshots.
- Revoking user credentials.
- Removing a developer.
- Rotating secrets.
- Scaling node groups.
- Rolling back deployments.

### Acceptance criteria

The owner can identify the health of the platform without manually inspecting every Pod.

---

## Phase 8 — Backup and disaster recovery

Estimated duration: 3–4 days.

### Requirements

- EBS snapshot policy.
- S3 lifecycle policy.
- Database backups.
- Retention policy.
- Encryption.
- Backup failure alerting.
- Restore procedure.
- Recovery testing.

Do not assume that a successful snapshot configuration proves recovery works.

### Restore test

1. Create test workspace.
2. Add source code and OpenCode state.
3. Create snapshot.
4. Simulate workspace data loss in an isolated test environment.
5. Restore snapshot to a new test volume.
6. Attach restored volume.
7. Verify source files.
8. Verify Git metadata.
9. Verify OpenCode state.
10. Document recovery time.

Never run destructive restore tests on production user volumes.

### Acceptance criteria

A documented and tested recovery procedure exists.

---

## Phase 9 — Performance and load testing

Estimated duration: 1 week.

### Test stages

Stage A:
- 1 workspace.

Stage B:
- 5 workspaces.

Stage C:
- 10 workspaces.

Stage D:
- 20 workspaces.

Stage E:
- 30 workspaces.

Stage F:
- 50 workspaces.

Do not jump directly to 50.

### Metrics

Measure:
- Workspace startup latency.
- Workspace stop latency.
- Workspace scheduling latency.
- CPU and memory per workspace.
- Node packing efficiency.
- EBS latency.
- OpenCode response time.
- LiteLLM throughput.
- Browser IDE responsiveness.
- Network errors.
- Cost per active workspace.

### Initial acceptance targets

These are proposed goals, not guaranteed performance:

- Workspace startup P95 under 120 seconds.
- Workspace application health within 30 seconds after container startup.
- No cross-user data access.
- No persistent data loss during normal stop/start.
- No unexpected Pod eviction under the agreed resource profile.
- 30 concurrent workspaces can run without sustained node memory pressure.
- Platform can scale toward 50 concurrent workspaces without redesign.

Record actual results and revise targets based on measured performance.

---

## Phase 10 — Production release

### Production checklist

- [ ] Terraform reviewed.
- [ ] Terraform state backed up.
- [ ] AWS budget alerts configured.
- [ ] Production domain configured.
- [ ] TLS configured.
- [ ] OIDC configured.
- [ ] Admin access restricted.
- [ ] Workspace isolation tested.
- [ ] Persistent storage tested.
- [ ] Backup and restore tested.
- [ ] LiteLLM virtual keys configured.
- [ ] Usage tracking verified.
- [ ] Monitoring configured.
- [ ] Alerts configured.
- [ ] Rollback tested.
- [ ] Security review completed.
- [ ] Load test completed.
- [ ] User onboarding documentation completed.
- [ ] Incident response documentation completed.

### Rollout

1. Internal owner workspace.
2. 2–3 trusted developers.
3. 5–10 pilot developers.
4. 20 developers.
5. 30 developers.
6. 50+ developers after capacity validation.

Do not enable all users at once.

---

# 6. Human Approval Gates

Coding agents must stop and request approval before:

1. Creating paid AWS resources.
2. Running Terraform apply against shared or production environments.
3. Deleting AWS resources.
4. Deleting RDS databases.
5. Deleting persistent volumes.
6. Changing public ingress rules.
7. Granting new IAM permissions.
8. Rotating production credentials.
9. Changing production DNS.
10. Applying destructive database migrations.
11. Increasing production capacity beyond the approved budget.

Agents may run local Docker, unit tests, static analysis, Terraform formatting and validation without asking.

Agents may run `terraform plan` when configured with safe read-only credentials.

Agents must never print secret values.

Agents must never bypass an approval gate by invoking another tool or script.

---

# 7. Definition of Done

The project is complete only when:

1. A developer can authenticate.
2. A developer can create a workspace.
3. A developer can open OpenCode Web.
4. A developer can open code-server.
5. Both access the same project directory.
6. A developer can clone a Git repository.
7. A developer can run development commands.
8. OpenCode can call a model through LiteLLM.
9. Developer usage is tracked.
10. Workspace data persists after stop/start.
11. Developers are isolated from one another.
12. Workspace services are not publicly exposed.
13. Workspace can be recovered from backup.
14. Monitoring and alerts work.
15. The platform has passed the agreed concurrency test.
16. Deployment and recovery are documented.

---

# 8. First Task for Claude Code

Do not implement the entire project immediately.

Start with Phase 0 only.

Your first response must contain:

1. Repository inspection summary.
2. Architecture proposal.
3. List of unresolved decisions.
4. Proposed repository structure.
5. Security risks.
6. AWS cost assumptions.
7. Phase-by-phase implementation plan.
8. First implementation task list.

Then create the repository documentation and tracking files.

After Phase 0 is complete:
- Run documentation consistency checks.
- Ask Codex to review the architecture.
- Resolve review findings.
- Present the Phase 0 report to the human owner.
- Wait for approval before starting Phase 1.

For all subsequent phases, follow the same process:

Implement → Test → Review with Codex → Fix → Update documentation → Present evidence → Human approval.

Never report a feature as complete unless the acceptance tests have passed.

The human owner is the final authority for production decisions.
