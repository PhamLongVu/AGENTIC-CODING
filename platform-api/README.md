# platform-api — deferred

Per `PROJECT_EXECUTION_PLAN.md` §3 this component is **optional and
deferred**: no code lives here yet, and per the plan's own rule this
directory exists only to document the deferral, not to hold placeholders.

## Why deferred

The platform's API surface today is served by the components it wraps:

- **Coder API** (`/api/v2`) — users, workspaces, builds, template params,
  app proxying. `tests/lib/coder.sh` shows the exact calls in use.
- **LiteLLM API** (`/key/generate`, `/key/list`, `/key/delete`,
  `/chat/completions`) — gateway key lifecycle. `gateway/litellm/scripts/`
  wraps them.

Operator runbooks (onboarding/offboarding) are written directly against
those APIs. A bespoke platform-api would only add value once there is a
management UI or automation that Coder + LiteLLM APIs cannot express.

## Trigger to implement

- A custom operator dashboard/UI is requested, or
- automated flows beyond what the runbook scripts cover (e.g. self-service
  key rotation with approval), or
- a stable facade is needed because Coder/LiteLLM API versions drift.

Any implementation starts by reading `docs/architecture/overview.md` and
ADR-0004 (gateway isolation), and follows the repo rules in AGENTS.md.
