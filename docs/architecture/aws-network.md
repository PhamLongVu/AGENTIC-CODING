# AWS network model (POC)

Single instance, single AZ — deliberately minimal (ADR-0001). The original
plan's 3-AZ public/private/data topology is deferred with documented growth
triggers.

## Layout

```text
VPC 10.42.0.0/24 (ap-southeast-1a)
├─ public subnet 10.42.0.0/28  (map_public_ip)
│    └─ m6a.2xlarge + 200 GiB gp3 root (encrypted) + EIP
│         SG: inbound 22 (admin_cidr), 7080 (dev_cidr); all outbound
└─ IGW + public route table

docker host networking on the instance:
├─ platform bridge "platform": postgres(:5432 internal) + coder(:7080 published)
├─ host network: LiteLLM (:4000, bound on host — SG does NOT open it)
└─ per-workspace bridges ws-*: workspace containers, isolated from peers
     host.docker.internal -> host-gateway (workspace -> coder:7080 / litellm:4000)
```

## Why LiteLLM is on the host network (AWS only)

Bedrock credentials come from the **instance profile via IMDSv2**. IMDSv2
`PUT` requires `HttpPutResponseHopLimit = 1`, which makes the metadata
service unreachable from ANY docker bridge network. Consequences:

- workspace containers: cannot read instance metadata ✅ (security goal)
- LiteLLM in a bridge network: could not assume the role either ❌
- therefore LiteLLM runs host-net in AWS mode (`deploy/compose/aws.yml`),
  reaches IMDS directly, and talks to postgres over host loopback
  (`127.0.0.1:5432`, published loopback-only in AWS mode).

This is the ONLY host-network component; it is still unauthenticated-local
only (4000 is not in the security group) and requires the master key.

## Ports — allowed vs reachable

| Port | Service | SG inbound | Who reaches it |
|---|---|---|---|
| 22 | sshd | admin_cidr | operator (or SSM, no key) |
| 7080 | Coder UI/API | dev_cidr | browsers, workspace agents (host-gateway) |
| 4000 | LiteLLM | **closed** | workspaces via host-gateway only |
| 5432 | PostgreSQL | **closed** | platform containers; loopback-only publish in AWS |

Verified post-deploy by `deploy/scripts/validate-deployment.sh` (IMDS block,
role assumption, 4000-closed checks).
