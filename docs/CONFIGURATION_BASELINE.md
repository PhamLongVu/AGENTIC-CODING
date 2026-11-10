# Configuration Baseline — Single Source of Truth

Status: **CONFIRMED by project owner, 2026-11-10. Supersedes conflicting statements in `PROJECT_EXECUTION_PLAN.md`.**

This file is the authoritative reference for scope, architecture and constraints.
Any document, config file or script that conflicts with this baseline is wrong
and must be fixed. Changes to this file require explicit owner approval.

## 1. Platform scope

| Item | Value |
|---|---|
| Purpose | Self-hosted, multi-user cloud coding platform (POC → MVP) |
| Users | Small team of developers; each gets an isolated persistent workspace |
| Initial capacity | **5 concurrent workspaces** (hard guardrail until benchmarks prove more) |
| Budget ceiling | **USD 200 / month** total infrastructure cost |
| Experience | Chat-first AI coding (OpenCode Web) **and** IDE-first (code-server), same filesystem |

## 2. AWS environment

| Item | Value |
|---|---|
| Provider | AWS |
| Region | `ap-southeast-1` (Singapore) |
| Deployment | **Single EC2 instance**, Docker Compose orchestration |
| Development | Local machine, **no AWS access, no AWS credentials required** |
| Endpoint | Temporary: `http://<ec2-public-ip>:7080` — no custom domain for POC |
| Database | PostgreSQL as a **Docker container** on the instance |
| AI provider | **AWS Bedrock**, reachable only through LiteLLM |
| IAM for AWS admin | AWS IAM Identity Center / SSO (operators only — NOT developer auth) |

### Explicitly out of scope for MVP

EKS, Kubernetes, Helm, RDS, ElastiCache, multi-AZ, extra microservices, managed
services without a demonstrated requirement. Any proposal to add one of these
requires an owner decision record and a budget impact statement.

## 3. Component selection (fixed)

| Component | Technology | Responsibility | Version policy |
|---|---|---|---|
| Workspace control plane | Coder | Login, workspace provisioning, lifecycle, app proxy | pinned in `.env` (`CODER_IMAGE`) |
| AI coding agent | OpenCode | Chat/web AI coding sessions in the workspace | pinned in workspace image |
| Browser IDE | code-server | VS Code in the browser | pinned via base image |
| AI gateway | LiteLLM (DB mode) | Model routing, per-developer virtual keys, budgets, usage tracking | pinned in `.env` (`LITELLM_IMAGE`) |
| Model provider | AWS Bedrock (prod) / LiteLLM mock (local) | Model inference | region + model IDs in `.env` |
| Database | PostgreSQL 16 | Coder + LiteLLM metadata | pinned in `.env` (`POSTGRES_IMAGE`) |
| Infrastructure | Terraform | Reproducible AWS provisioning | `infra/terraform/` |

## 4. Workspace profiles (initial, configurable)

| Profile | vCPU | RAM | Storage | Notes |
|---|---:|---:|---:|---|
| Small | 1 | 2 GiB | 20 GiB | default for POC users |
| Medium | 2 | 4 GiB | 30 GiB | |
| Large | 4 | 8 GiB | 50 GiB | requires justification |

These are **starting points, not guaranteed capacity**. Five concurrent
Medium workspaces plus platform overhead needs ~12 vCPU / ~24 GiB — the chosen
instance (`m6a.2xlarge`, 8 vCPU / 32 GiB) can host at most **2–3 Medium or
5 Small** concurrent workspaces. Actual consumption must be benchmarked
(Phase 4) before any "5 concurrent workspaces fit the budget" claim.

## 5. Workspace lifecycle requirements

- Workspace runtime runs **only when the user is active** or per an approved
  schedule: idle autostop default **45 min** (configurable per workspace).
- Stop must preserve all persistent data (project files, OpenCode state,
  code-server settings, shell history).
- Persistent data lives in a per-workspace Docker volume mounted at `/home/coder`.
- Start re-attaches the same volume; data survives stop/start cycles.
- Delete requires explicit confirmation in the Coder UI; the workspace volume
  is destroyed on workspace **delete** (never on stop).

## 6. Identity & authentication

| Audience | Mechanism | Status |
|---|---|---|
| AWS operators | AWS IAM Identity Center / SSO → IAM roles | Confirmed (baseline) |
| Platform developers (POC) | Coder built-in accounts (username + password), created by the operator | Confirmed for POC |
| Platform developers (future) | OIDC against corporate IdP, wired into Coder | Extension path, documented in ADR-0003 |

AWS administrator identity is **never** reused as developer platform identity.

## 7. AI gateway policy

- Every AI request from a workspace flows **workspace → LiteLLM → Bedrock**.
- Workspaces hold **only** a LiteLLM **virtual key** (per developer, budgeted,
  rate-limited, revocable). The LiteLLM master key never enters a workspace.
- Only the LiteLLM service can obtain Bedrock credentials (instance profile,
  host network + IMDS hop limit 1). See ADR-0004 and `docs/architecture/security-model.md`.
- Per-developer usage and spend are tracked by LiteLLM (keyed on virtual keys).

## 8. Local development contract

- `docker compose up` on a laptop with **no AWS account** runs the full stack:
  PostgreSQL, LiteLLM (mock provider), Coder, and real workspaces.
- Mode switch: `AI_PROVIDER_MODE=mock|bedrock` selects the LiteLLM model config.
- Local tests never touch AWS. Bedrock integration tests are opt-in
  (opt-in steps in `deploy/scripts/validate-deployment.sh`, require deployed AWS POC).

## 9. Change control

The following require explicit owner approval **before** execution:

1. Creating or modifying paid AWS resources (including `terraform apply`).
2. Deploying to AWS.
3. Modifying AWS IAM permissions.
4. Destroying infrastructure or persistent user data.
5. Changing anything in this baseline.
6. Introducing new recurring infrastructure cost.
