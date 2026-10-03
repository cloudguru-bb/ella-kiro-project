# ella-kiro-project

An **AWS Free Tier** experiment deploying the [ella-core](https://github.com/ella-core/ella-core)
5G cellular core on a single EC2 instance, wrapped in an **autonomous agentic
lifecycle** (MCP tool server, multi-tier memory, self-healing loop, Well-Architected
auditing). The authoritative specification is [`Requirements-v2.md`](./Requirements-v2.md).

> ⚠️ Nothing here auto-deploys to your account. You run `terraform apply` yourself.
> Review the Free Tier notes below before deploying.

## Repository layout

```
infra/        AWS infrastructure (IaC) + host bootstrap
  main.tf           VPC, subnet, IGW, route table, security group,
                    scoped IAM role, EC2 t3.micro, Elastic IP, outputs
  cloud-init.yaml   Host bootstrap: Docker, TUN, NAT, CloudWatch agent,
                    deploys the app stack + agent, starts self-healing service
app/          Cellular core container stack
  docker-compose.yml   ella-core service definition
  config.yaml          ella-core runtime config (upstream schema; mounted at /config/config.yaml)
sim/          RAN/UE simulator stack (runs on a SEPARATE EC2 host)
  docker-compose.yml   UERANSIM gNodeB + UE containers
  gnb.yaml.tmpl        gNodeB config template (rendered with core/host IPs at boot)
  ue.yaml.tmpl         UE config template (IMSI/Ki/OPc matched to the subscriber)
  README.md            End-to-end attach + data-plane test guide
agent/        Autonomous agent control plane
  ella_mcp_server.py   Real MCP server (FastMCP) exposing 5 agent tools
  self_healing_loop.py Day-2 observability + self-healing daemon
  requirements.txt     Python deps (mcp SDK v1)
  systemd/ella-agent.service  systemd unit for the self-healing loop
  test_telegram_alert.sh      Telegram credential smoke test
```

## Deploy (Day-0 / Day-1)

```bash
cd infra
terraform init
# Recommended: lock SSH to your IP for a Well-Architected posture.
terraform apply -var="ssh_ingress_cidr=$(curl -s https://checkip.amazonaws.com)/32"
```

By default this provisions **two** Free-Tier instances: the ella-core host and a
RAN/UE simulator host. Set `-var="deploy_simulator=false"` to deploy only the core.

`cloud-init.yaml` then automatically, on the **core** instance:
1. Installs Docker, Python 3.12 + venv, and the CloudWatch agent.
2. Enables IP forwarding, creates `/dev/net/tun`, and applies the NAT masquerade.
3. Clones this repo, deploys the `ella-core` stack (`docker compose up -d`).
4. Creates the agent virtualenv and starts the `ella-agent` self-healing service.

And `cloud-init-sim.yaml` on the **simulator** instance installs Docker, renders the
UERANSIM configs with ella-core's **private** IP, and starts the gNodeB. See
[`sim/README.md`](./sim/README.md) for the end-to-end attach + data-plane test.

## End-to-end (UE → RAN → core → internet)

The simulator host reaches ella-core over **private VPC IPs**; ella-core's security
group permits N2 (SCTP/UDP 38412) and N3 (GTP-U 2152) **only from the simulator's
security group** (not the public internet). After deploy:

```bash
# On the simulator host:
cd /opt/ella-sim/sim
docker compose logs gnb | grep -i "NG Setup"     # gNodeB registered with the AMF
docker compose run --rm ue                        # UE registers + PDU session
ping -I uesimtun0 -c 4 8.8.8.8                     # UE data plane out via ella-core NAT
```

## Agent tools (MCP)

The MCP server (`agent/ella_mcp_server.py`) exposes six tools over the standard
MCP stdio transport:

| Tool | Purpose |
|------|---------|
| `get_cellular_status()` | Container state, API reachability (`:5002`), memory, GTP-U tunnel count |
| `provision_subscriber(imsi, key_k, opc, sst, sd)` | Provision a validated 5G test subscriber |
| `restart_core_service()` | Graceful container restart (self-healing) |
| `evaluate_well_architected()` | Live 6-pillar posture checks (cost / reliability / security / performance) |
| `apply_remediation(action_type)` | `clear_logs`, `restart_container`, `flush_stale_iptables`; destructive actions are HITL-gated |
| `run_e2e_attach_test()` | Verify RAN/UE attach: core up + N2 (NGAP) association + N3 (GTP-U) tunnel(s) |

### Memory tiers (SQLite at `/var/lib/ella-agent/memory.db`)
- `session_memory` — short-term tool executions & events
- `remediation_memory` — long-term incident RCA & remediation outcomes
- `topology_memory` — long-term topology / PLMN / subscriber state

### Optional Telegram alerts
Create `/etc/ella-agent/telegram.env` on the host:
```
TELEGRAM_BOT_TOKEN=123456789:ABC...
TELEGRAM_CHAT_ID=123456789
```
Verify with `bash agent/test_telegram_alert.sh`.

## Verification (Definition of Done)

```bash
# 3. Agent MCP server self-test — all tools execute cleanly, no live side-effects
python3 -m venv venv && ./venv/bin/pip install -r agent/requirements.txt
./venv/bin/python agent/ella_mcp_server.py --test

# 2. Cellular core status (on the host)
docker ps                                  # ella-core container Up/healthy
curl -fsS http://localhost:5002/api/v1/metrics | head   # API responding on :5002

# 4. Self-healing (on the host)
docker stop ella-core         # ella-agent detects + restarts within ~30s
journalctl -u ella-agent -f
```

## AWS Free Tier notes
- `t3.micro` is Free Tier eligible in most regions; some accounts/regions instead
  get `t2.micro`. Override with `-var="instance_type=t2.micro"` if needed.
- Root EBS volume is 20 GB `gp3`, encrypted — within the 30 GB free allotment.
- CloudWatch logs are scoped to the `/aws/ec2/ella-core` log group; the instance
  IAM role grants only scoped `logs:*` + namespaced `PutMetricData` (no wildcards).
- `terraform destroy` tears everything down to return to $0.

## Learning materials

New to agentic systems? Start here:
- **[`docs/TUTORIAL.md`](./docs/TUTORIAL.md)** — a guided, hands-on walkthrough that
  *teaches* the agent lifecycle (MCP tools, memory, self-healing, guardrails) with
  runnable exercises. Most of it works locally with no AWS account.
- **[`docs/TEST_CASES.md`](./docs/TEST_CASES.md)** — a 31-case, human-executable test
  suite with step-by-step commands, expected results, and pass/fail tracking. Maps
  directly to the Definition of Done in `Requirements-v2.md`.

## Changes from the initial drop

See [`CHANGELOG.md`](./CHANGELOG.md) for the full list of fixes applied to the
original flat-layout files.
