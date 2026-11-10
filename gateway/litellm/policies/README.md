# Gateway policies

The per-developer key policy applied by `scripts/create-virtual-key.sh`.
Single source for operator defaults; the script mirrors these values.

## Default key policy (POC)

| Control | Default | Rationale |
|---|---|---|
| Budget (`max_budget`) | USD 20 / month | .env `LITELLM_DEFAULT_USER_BUDGET`; ~10 keys fit a model-spend envelope well below the infra ceiling |
| Rate limit (`rpm`) | 30 | agents burst; humans don't need more |
| Rate limit (`tpm`) | 100 000 | keeps one runaway agent from monopolizing Bedrock |
| Model allowlist | the two platform models | keys cannot mint access to other models |
| Revocation | immediate (`/key/delete`) | offboarding runbook step 2 |

## Enforcement notes (honest limits)

- Budget exhaustion is enforced by LiteLLM against **tracked spend**. In
  mock mode completions cost USD 0, so numeric budget exhaustion is not
  locally testable — revocation and rate limits are (tests/security).
- The **master key** never leaves `.env`/the compose service. Nothing in
  `workspace/` ever sees it; `OPENCODE_PROVIDER_API_KEY` is always a
  virtual key.
