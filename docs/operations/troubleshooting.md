# Troubleshooting

First stop for "something is weird". Deeper dev-environment notes live in
`docs/operations/development.md`.

| Symptom | Cause | Fix |
|---|---|---|
| `make up` fails: postgres unhealthy | init script failed once; data dir half-initialized | `scripts/destroy-dev.sh data && make up` (fresh platform data) |
| litellm stuck `health: starting` | DB mode first boot is slow (~1 min) | wait; then `docker compose logs litellm` |
| coder logs `access url not reachable` | CODER_ACCESS_URL wrong or hosts entry missing (local) | `sudo make dev-hosts-setup`; check `.env` |
| workspace build `Connecting…` forever | workspace cannot reach CODER_ACCESS_URL | template's extra_hosts (`host.docker.internal:host-gateway`) + port published on 0.0.0.0 |
| workspace apps unhealthy | services failed in-container | `docker exec coder-ws-… cat ~/.cache/code-server.log` / `opencode.log` |
| template push fails | no admin session / template dir stale | `make bootstrap` (re-creates session) then retry |
| `bash: tests/lib/env.sh: No such file` | wrong cwd | run from repo root (all scripts assume it) |
| virtual key works locally, 403 on AWS | wrong mode config mounted | `.env AI_PROVIDER_MODE`; AWS needs `bedrock` + aws.yml override |
| bedrock: `Unable to verify signature` | LiteLLM not on host network in AWS mode | apply `deploy/compose/aws.yml`; check IMDS (`deploy/scripts/validate-deployment.sh`) |
| port 4000 reachable from the internet | SG misconfiguration | only 22/7080 should be open; fix SG, re-run validate-deployment |
| disk filling up | volume quota is soft (data-persistence.md) | `docker system df`; identify via workspace Home tile; prune images |
| OOM / workspace killed | profile memory cap working as intended | move to a larger profile or reduce workload |

## Diagnostic one-liners

```bash
make ps                                   # service health
docker compose logs coder | tail -50
docker ps --format '{{.Names}} {{.Status}}' | grep coder-ws
docker exec <ws-container> workspace/scripts/health-check.sh   # if copied in
curl -s http://127.0.0.1:4000/health/liveliness   # gateway
curl -s http://127.0.0.1:7080/api/v2/buildinfo     # coder
```
