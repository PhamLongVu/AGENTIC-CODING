# ADR-0003: Developer authentication for the POC

- Status: CONFIRMED (baseline requires an explicit decision; this is it)

## Context

The baseline separates **AWS administration identity** (IAM Identity Center /
SSO — confirmed) from **developer-facing platform identity** (unspecified).
The original plan assumed generic OIDC. We must pick a POC-appropriate
mechanism that is simple, explicit, and extensible.

## Decision

1. **AWS operators** authenticate via IAM Identity Center SSO to AWS APIs and
   the EC2 host (SSH/SSM). This identity has **no** meaning inside the coding
   platform.
2. **Developers** authenticate to the platform with **Coder built-in accounts**
   (username + password), provisioned by the operator. Self-registration is
   disabled; accounts are created via `coder users create` by an admin.
3. **Future production path**: Coder's OIDC support (any corporate IdP:
   Okta, Entra ID, Google Workspace). The platform adds zero custom auth code
   now; switching is a Coder server configuration change
   (`CODER_OIDC_ISSUER_URL` etc.), not an application change.

## Why not OIDC in the POC

A POC-grade OIDC setup requires a domain, TLS, and an IdP tenant — the
baseline explicitly says "temporary endpoint, no custom domain". Built-in
accounts give the same isolation and audit properties with zero external
dependencies. Passwords are transmitted over the SG-restricted HTTP endpoint
(documented limitation, docs/architecture/security-model.md §5) and rotated at first login.

## Consequences

- ✅ Zero new services; extensible by configuration only.
- ⚠️ Operator must manage the user list manually (acceptable at ≤10 users).
- ⚠️ Password reset is an operator action (`coder users ...` / admin UI).
