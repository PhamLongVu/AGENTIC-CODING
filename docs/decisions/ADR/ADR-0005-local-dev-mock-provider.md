# ADR-0005: Local development without AWS — mock AI provider

- Status: CONFIRMED (baseline mandates local-first development)

## Context

The local dev machine has no AWS access and must not need AWS credentials,
yet the full workflow (OpenCode → gateway → response) must be testable.

## Decision

- LiteLLM's built-in **`mock_response`** model config powers a `mock/` model
  family in `gateway/litellm/config/config-mock.yaml`: every chat completion returns
  a deterministic string, offline, with no API keys.
- `AI_PROVIDER_MODE=mock|bedrock` in `.env` selects which LiteLLM config file
  is mounted (compose interpolation). Default: `mock`.
- The workspace image and OpenCode configuration are **identical** in both
  modes; only the gateway's upstream differs. Workspaces therefore exercise
  the real code path (OpenCode → OpenAI-compatible client → LiteLLM → key
  check → budget check → response) locally.
- Virtual keys work in mock mode exactly as in Bedrock mode (they are gateway
  features), so auth/budget/usage tests run locally.
- Bedrock-specific tests (in `deploy/scripts/validate-deployment.sh`) are separate and opt-in; they are the
  only tests that require deployed AWS infrastructure.

## Consequences

- ✅ CI and laptops run the full integration suite with zero AWS.
- ⚠️ Mock responses carry no realism (no tool-calling variety, no latency
  profile) — prompt-behavior testing of OpenCode itself is out of scope for
  the local suite.
