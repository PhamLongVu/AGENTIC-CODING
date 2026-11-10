# Security Model — MVP

Security is a release blocker. This document states the controls, the
assumptions, and the known limitations of the single-instance MVP.

## 1. Threat model (summary)

| Threat | Primary controls | Residual risk |
|---|---|---|
| Developer A accesses Developer B's workspace/files | Per-workspace container + dedicated docker network + per-workspace volume; no shared mounts; Coder RBAC | Container-level isolation only (shared kernel) — accepted for POC, see §6 |
| Workspace escapes to host | Non-root user, dropped capabilities, no privileged mode, no host mounts, no host networking, seccomp default, pids limit | Kernel exploits shared-host risk remains — accepted for trusted-team POC |
| Workspace reaches EC2 metadata ( credential theft) | IMDSv2 required, hop limit 1 → bridge-network containers cannot obtain instance-profile tokens; only LiteLLM (host network) can | Host-network processes are trusted by definition |
| AWS credentials leak into workspaces | Bedrock only via LiteLLM; no static AWS keys anywhere; workspaces get only LiteLLM virtual keys | Virtual key theft → contained by per-key budget/rate limits + revocation |
| Docker socket abuse | Socket mounted **only** into the Coder server container (control plane); workspace image contains no docker CLI and template mounts no socket; workspace containers cannot see the control plane network | Compromise of coder server = host compromise (documented, monitored) |
| LiteLLM master key leak | Lives in `.env` on the instance (root-readable) / Secrets Manager path documented; never env-injected into workspaces, never in Git, never in logs | Operator misuse — runbook warnings |
| Unauthenticated service exposure | Only Coder :7080 exposed (SG-restricted); LiteLLM :4000 host-internal; Postgres localhost; workspace apps loopback-only behind Coder auth | POC endpoint is HTTP (no TLS) — see §5 |
| Malicious repo content / prompt injection executing in workspace | Treated as **untrusted code execution by design**: containment = non-root, resource limits, no host access, no cloud creds in workspace | Cannot be prevented, only contained (per original plan §Phase 6) |
| Secret sprawl in Git | `.gitignore` blocks `.env*`, `*.key`, `*.pem`, tfstate, tfvars; pre-commit checks in CI | — |

## 2. Identity & access

- **AWS operations**: IAM Identity Center SSO → scoped IAM roles (Terraform
  apply, EC2 admin). Operators never use long-lived access keys.
- **Developer platform access**: Coder built-in accounts, operator-provisioned
  (POC). Passwords set out-of-band; no self-registration (`CODER_ALLOW_ALL_USERS`
  style open signups disabled).
- **Workspace → AI**: per-developer LiteLLM virtual key, injected as an
  environment variable through the Coder template parameter marked sensitive
  (not printed in logs, not visible in UI after set).
- Extension path: OIDC federation into Coder for both operator and developer
  login (ADR-0003).

## 3. Bedrock IAM blast radius (AWS mode)

```text
EC2 instance profile role "cloud-coding-litellm"
  └── bedrock:InvokeModel, bedrock:InvokeModelWithResponseStream
      Resource: arn:aws:bedrock:ap-southeast-1::*:foundation-model/*
      (and any granted inference profiles)
```

- No S3, no EC2, no IAM permissions. Nothing else runs with AWS credentials.
- LiteLLM reaches IMDS because it runs on the **host network**; every other
  container (including all workspaces) is on bridge networks and blocked by
  `HttpTokens=required` + `HttpPutResponseHopLimit=1` (set in Terraform).
- Defense in depth: workspace image additionally ships an iptables-free
  guard — no AWS CLI, no docker CLI. On a local dev laptop there is no IMDS
  at all; the on-host proof that `169.254.169.254` is unreachable from
  bridge containers runs on the EC2 instance via
  `deploy/scripts/validate-deployment.sh` (AWS mode only — cannot be
  simulated locally).

## 4. Workspace hardening

- Image runs everything as `coder` (uid 1000); sudo is never installed;
  setuid binaries are asserted absent by test.
- Template enforces: `privileged=false`, `capabilities.drop=[ALL]`,
  `security_opts=["no-new-privileges:true"]`, `pids_limit`, CPU/memory limits;
  read-only rootfs *not* forced (dev toolchains write too much; documented
  trade-off).
- One docker network per workspace → workspaces cannot address each other.
- Workspace egress allowed (git hosts, package registries) — that is a product
  requirement; isolation is ingress- and peer-focused, as in the original plan.

## 5. Known limitations (POC, accepted by baseline)

1. **HTTP-only endpoint** (`http://<ip>:7080`): passwords and session cookies
   travel in cleartext. Mandatory mitigations while in POC: SG restricts :7080
   to operator/office IP ranges; rotate the bootstrap admin password; switch to
   TLS or a domain+ALB before any wider rollout.
2. **Shared kernel**: container escape by a determined insider is possible;
   this MVP serves a trusted team, not adversaries.
3. **Single host**: no workload placement isolation, one noisy neighbor can
   degrade others; resource limits bound (not eliminate) this.
4. **LiteLLM admin UI**: AWS mode — host network + SG (4000 not open), so
   reachable only from the instance itself (operator via SSH tunnel); local
   mode — published on the dev machine only, no AWS behind it (mock).
5. **Coder server holds docker.sock**: a Coder-server RCE equals host RCE.
   Coder is pinned and not internet-exposed beyond :7080 with SG allowlist.
6. **Prompt injection / malicious repos**: contained, not prevented —
   workspaces are untrusted-execution environments by design.

## 6. Secret inventory

| Secret | Storage | Rotation |
|---|---|---|
| `.env` (all platform secrets) | Instance file, mode 600, root-owned; never in Git | on demand — operator regenerates via `scripts/gen-secrets.sh` against a fresh `.env`, then restarts dependent services |
| LiteLLM master key | `.env` → LiteLLM container env | rotate + update virtual keys runbook |
| LiteLLM salt | `.env` | rotating invalidates stored creds — plan carefully |
| Developer virtual keys | LiteLLM DB; injected per-workspace via template param | revocable per user from LiteLLM |
| Coder DB password / admin password | `.env` | on demand |
| Terraform state | local/S3 with encryption (see `infra/terraform`) | n/a |

## 7. Security test matrix (executed in CI where local-runnable)

| Test | Where | Status |
|---|---|---|
| Workspace image has no docker CLI / socket path | `tests/integration/test_workspace_image.sh` | written (verification pass pending) |
| Live workspace container mounts no docker.sock | `tests/security/test_container_isolation.sh` | written (verification pass pending) |
| 169.254.169.254 unreachable from bridge containers | `deploy/scripts/validate-deployment.sh` (on-host, AWS mode) | written; opt-in, runs only after owner-approved deploy |
| IMDS hop-limit=1 asserted in Terraform | `infra/terraform/modules/ec2/main.tf` + `tests/infrastructure/run.sh` | written (validate runs locally; no apply ever without approval) |
| Two workspaces cannot address each other | `tests/integration/test_isolation.sh` | written (verification pass pending) |
| Invalid/revoked LiteLLM key rejected (401) | `tests/security/test_gateway_hardening.sh` | written (manual path verified 2026-11-10) |
| Virtual key cannot admin the gateway | `tests/security/test_gateway_hardening.sh` | written (verification pass pending) |
| Master key / AWS creds absent from workspace env | `tests/security/test_container_isolation.sh` | written (verification pass pending) |
| Workspace runs as non-root | `tests/integration/test_workspace_image.sh` | written (manual check passed 2026-11-10) |
| Postgres not reachable from workspace network | `tests/integration/test_isolation.sh` | written (verification pass pending) |
