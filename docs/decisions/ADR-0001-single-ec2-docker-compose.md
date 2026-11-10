# ADR-0001: Single EC2 instance + Docker Compose for the MVP

- Status: CONFIRMED (owner baseline, 2026-11-10)
- Supersedes: EKS/Helm/RDS/ElastiCache architecture in `PROJECT_EXECUTION_PLAN.md`

## Context

The original plan targeted 50+ developers with EKS, managed node groups, RDS,
and ElastiCache. The owner re-scoped the project to a POC/MVP: 5 concurrent
workspaces, USD 200/month, temporary endpoint.

## Decision

Run the entire platform (Coder, LiteLLM, PostgreSQL, workspaces) as Docker
containers on **one EC2 instance** in `ap-southeast-1`, orchestrated by Docker
Compose. No Kubernetes, no managed data services.

## Consequences

- ✅ Cost fits the budget at POC duty cycles; operational surface is one host.
- ✅ Same compose file works locally (mock mode) and on AWS — high fidelity
  between dev and prod for this stack.
- ⚠️ Single point of failure; maintenance = platform downtime.
- ⚠️ Capacity ceiling ~5 Small concurrent workspaces on the chosen instance.
- ⚠️ Isolation is container-grade (shared kernel), not VM-grade.

## Growth triggers (revisit EKS path from the original plan when ANY holds)

1. Concurrent workspaces needed > ~6–8 sustained.
2. Team needs independent host failure domains or >1 AZ.
3. Workspace CPU/memory demands exceed the largest single sensible instance.
4. Compliance requires VM-grade isolation.

Cost if wrong: migrating workspaces off docker volumes to EBS/PVCs is the
hardest part; keeping workspace data under `/home/coder` in a named volume
makes the future migration a volume-to-EBS copy.
