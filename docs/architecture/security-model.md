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
  guard — no AWS CLI, no docker CLI, and a shell profile warning against
  IMDS probing; tests assert `169.254.169.254` is unreachable from a
  workspace container (`tests/local/`).

## 4. Workspace hardening

- Image runs everything as `coder` (uid 1000); no sudo (removed from the
  image); no setuid escalation paths beyond defaults.
- Template enforces: `privileged=false`, `capabilities.drop=[ALL]`,
  `security_opts=["no-new-privileges:true"]`, `pids_limit`, CPU/memory limits,
  read-only *not* forced (dev toolchains write too much; documented trade-off),
  tmpfs on `/tmp`.
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
4. **LiteLLM admin UI** reachable only from the host (port 4000 host-internal);
   operator access via SSH tunnel.
5. **Coder server holds docker.sock**: a Coder-server RCE equals host RCE.
   Coder is pinned and not internet-exposed beyond :7080 with SG allowlist.
6. **Prompt injection / malicious repos**: contained, not prevented —
   workspaces are untrusted-execution environments by design.

## 6. Secret inventory

| Secret | Storage | Rotation |
|---|---|---|
| `.env` (all platform secrets) | Instance file, mode 600, root-owned; root dir not in Git | on demand; `make rotate-secrets` documented |
| LiteLLM master key | `.env` → LiteLLM container env | rotate + update virtual keys runbook |
| LiteLLM salt | `.env` | rotating invalidates stored creds — plan carefully |
| Developer virtual keys | LiteLLM DB; injected per-workspace via template param | revocable per user from LiteLLM |
| Coder DB password / admin password | `.env` | on demand |
| Terraform state | local/S3 with encryption (see `infra/terraform`) | n/a |

## 7. Security test matrix (executed in CI where local-runnable)

| Test | Where | Status |
|---|---|---|
| Workspace image has no docker CLI / socket path | `tests/local/test_workspace_image.sh` | implemented |
| Workspace container cannot reach 169.254.169.254 | `tests/local/test_workspace_isolation.sh` | implemented (local proxy assertion) |
| Two workspaces cannot address each other | `tests/local/test_workspace_isolation.sh` | implemented |
| Invalid LiteLLM key rejected | `tests/local/test_litellm.sh` | implemented |
| Master key absent from workspace env | `tests/local/test_litellm.sh` | implemented |
| Workspace runs as non-root | `tests/local/test_workspace_image.sh` | implemented |
| Postgres not reachable from workspace network | `tests/local/test_workspace_isolation.sh` | implemented |
| IMDS hop-limit=1 asserted in Terraform | `infra/terraform` + `tests/aws/` | planned (Phase 3) |
