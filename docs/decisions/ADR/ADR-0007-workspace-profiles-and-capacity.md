# ADR-0007: Workspace profiles, instance sizing, and the budget guardrail

- Status: CONFIRMED (profile table from baseline; sizing is our recommendation)

## Context

Baseline profiles (configurable starting points, not guaranteed capacity):

| Profile | vCPU | RAM | Storage |
|---|---:|---:|---:|
| Small | 1 | 2 GiB | 20 GiB |
| Medium | 2 | 4 GiB | 30 GiB |
| Large | 4 | 8 GiB | 50 GiB |

USD 200/month ceiling. Workspaces must not run 24/7 — idle autostop required.

## Decision

1. Instance: **`m6a.2xlarge`** (8 vCPU / 32 GiB) — smallest general-purpose
   instance that hosts 5 concurrent Small workspaces (5 vCPU / 10 GiB) plus
   platform overhead (~1.5 vCPU / ~3 GiB) with headroom. AMD variant for
   ~10% savings vs m6i.
2. Template defaults every workspace to **Small**; Medium/Large are explicit
   parameter choices.
3. Idle autostop default **45 minutes** (user-adjustable); no 24/7 workspaces.
4. `WORKSPACE_MAX_CONCURRENT=5` guardrail: operator-audited (workspace count
   script) — soft limit until Phase 4 measures real consumption.
5. **Capacity truth table (no benchmarks yet — do not overclaim):**
   - 5 concurrent Small: fits compute; storage fits (100 GiB volumes on
     200 GiB disk with margin) — **to be verified by measurement**.
   - 2–3 concurrent Medium: fits.
   - 5 concurrent Medium: does **not** fit (12 vCPU needed vs 8 available).
6. Phase 4 must publish measured per-workspace CPU/RAM/disk and the resulting
   max-concurrency-vs-budget table before any capacity claim is made.

## Alternatives rejected

- `m6a.xlarge` (4/16): cannot host even 3 concurrent Small plus platform —
  violates the 5-workspace requirement.
- Graviton (`m7g`): ~equal price/vCPU at this size; AMD x86 avoids any
  workspace-image arch surprises (base images, opencode binaries).

## Cost if wrong

One instance resize (`terraform apply` with a new instance type + restart) —
no data migration needed since volumes persist on the same EBS root disk.
