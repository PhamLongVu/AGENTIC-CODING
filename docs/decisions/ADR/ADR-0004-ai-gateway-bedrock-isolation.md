# ADR-0004: AI gateway — LiteLLM with per-developer virtual keys; Bedrock IAM confined to LiteLLM

- Status: CONFIRMED (baseline mandates LiteLLM + Bedrock and "only LiteLLM may
  invoke Bedrock")

## Context

Workspaces must call AI models (Bedrock) with per-developer budgets, rate
limits, and usage tracking, while never holding AWS credentials or the gateway
master key.

## Decision

1. **LiteLLM proxy in DB mode** (PostgreSQL) owns all provider access.
2. Each developer receives a **virtual key** (LiteLLM) with:
   monthly budget (`LITELLM_DEFAULT_USER_BUDGET`), RPM/TPM limits, and per-key
   usage tracking. Keys are issued by the operator via
   `gateway/litellm/scripts/create-virtual-key.sh` and stored only in the
   LiteLLM database.
3. Workspaces receive exactly two AI-related env vars:
   `OPENAI_API_BASE=http://host.docker.internal:4000/v1` and
   `OPENCODE_PROVIDER_API_KEY=<their virtual key>` (a sensitive Coder template
   parameter). OpenCode is configured with an OpenAI-compatible provider
   pointing at LiteLLM.
4. **AWS mode**: LiteLLM authenticates to Bedrock with the **EC2 instance
   profile** — no static keys anywhere. To let LiteLLM (a container) reach the
   Instance Metadata Service while blocking all other containers:
   - LiteLLM runs with `network_mode: host` on AWS (bridge + published port
     locally),
   - the instance enforces IMDSv2 (`HttpTokens=required`) with
     `HttpPutResponseHopLimit=1`, so **bridge-network containers (all
     workspaces, postgres, coder) cannot reach IMDS at all**.

## Alternatives rejected

- Static AWS keys for LiteLLM in `.env`: violates "never expose static AWS
  credentials" posture; rotation pain; leak blast radius.
- Workspace-level Bedrock roles via container role chaining (ECS/EKS
  patterns): not available meaningfully on plain Docker without exposing
  instance-wide creds.
- Bedrock access from inside workspaces via LiteLLM pass-through of an AWS
  role: unnecessary; gateway centralizes policy.

## Consequences

- ✅ Single audit point for model usage; per-user spend visible in LiteLLM UI.
- ✅ Revoking a developer's AI access = disabling one virtual key.
- ⚠️ LiteLLM host networking on AWS means its :4000 binds on all host
  interfaces; the security group must (and does) block :4000 from the
  internet — workspaces reach it via the host gateway internally.
- ⚠️ Per-key budgets count model spend at LiteLLM list prices; treat as
  budget signal, not billing truth (Bedrock billing lands in the AWS bill).
