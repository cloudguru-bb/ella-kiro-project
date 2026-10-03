# Tutorial: Learning the Agentic Lifecycle with ella-core

A hands-on, learning-oriented walkthrough of an **autonomous agentic lifecycle**
built around the [ella-core](https://github.com/ella-core/ella-core) 5G cellular
core on **AWS Free Tier**.

By the end you will understand — by *doing* — how an AI agent system:
1. Exposes **tools** to act on real infrastructure (Model Context Protocol / MCP).
2. Keeps **memory** across a task and across incidents (SQLite tiers).
3. **Observes and self-heals** a running workload (Day-2 operations).
4. **Audits** itself against the AWS Well-Architected pillars and **asks a human**
   before doing anything destructive (guardrails + human-in-the-loop).

> **Audience:** engineers learning agentic systems. You do **not** need deep 5G
> knowledge — the cellular core is just a realistic workload for the agent to manage.
>
> **Companion:** work the exercises here, then formally verify with
> [`TEST_CASES.md`](./TEST_CASES.md).

---

## 0. How this maps to the AI Agent concepts

| Concept | Where it lives in this repo | You'll see it in |
|---|---|---|
| **Thought → Action → Observation loop** | `agent/self_healing_loop.py` | Module 4 |
| **Tools / tool boundaries (MCP)** | `agent/ella_mcp_server.py` | Module 2 |
| **In-context / short-term / long-term memory** | SQLite tables in `ella_mcp_server.py` | Module 3 |
| **Observability & self-healing (Day-2)** | `self_healing_loop.py` + CloudWatch config | Module 4 |
| **Guardrails & human-in-the-loop** | `apply_remediation` HITL gate | Module 5 |
| **Well-Architected evaluation** | `evaluate_well_architected` tool | Module 5 |
| **Infrastructure as Code (Day-0/1)** | `infra/main.tf`, `infra/cloud-init.yaml` | Module 6 |

---

## 1. Prerequisites & two ways to learn

You can do **almost everything locally** without spending a cent. Only Module 6
needs an AWS account.

### Path A — Local learning (recommended first; $0, no AWS)
You need: Python 3.10+ and (optionally) Docker.

### Path B — Full cloud deployment (Module 6)
You need: an AWS account, the AWS CLI configured, and Terraform ≥ 1.5.
Everything is sized for **Free Tier** — but *you* are responsible for the bill;
run `terraform destroy` when done.

### Set up a local Python environment (both paths)

```bash
cd ella-kiro-project
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r agent/requirements.txt
```

Keep the agent's state out of system directories while learning by pointing it at
a local folder:

```bash
mkdir -p .state
export ELLA_MEMORY_DB="$(pwd)/.state/memory.db"
export ELLA_APPROVAL_FILE="$(pwd)/.state/approval_pending.json"
```

> 💡 **Why env vars?** The agent reads `ELLA_MEMORY_DB` and `ELLA_APPROVAL_FILE`
> from the environment (with production defaults under `/var/lib/ella-agent`).
> Overriding them is your first lesson in **agent configuration**: the same code
> behaves safely in a learning sandbox and in production.

---

## 2. Module — The agent's hands: MCP tools

An agent is only as capable as the **tools** you give it. This project exposes
five tools over the **Model Context Protocol (MCP)**:

| Tool | What it does | Learning point |
|---|---|---|
| `get_cellular_status()` | Reads container health, `ogstun`, memory, GTP-U tunnels | *Observation* tool (read-only) |
| `provision_subscriber(imsi, key_k, opc, sst, sd)` | Adds a validated 5G test subscriber | *Action* tool with **input validation** |
| `restart_core_service()` | Restarts the core container | *Remediation* action |
| `evaluate_well_architected()` | Live 6-pillar posture check | *Reasoning/audit* tool |
| `apply_remediation(action_type)` | Executes a fix; destructive ones are gated | *Guarded* action |

### Exercise 2.1 — Run the offline self-test

The fastest way to see all tools execute safely:

```bash
python agent/ella_mcp_server.py --test
```

Expected: a list ending in **`All tools executed cleanly.`** and 8 `[PASS]` lines.

> 🔎 **Observe:** `--test` runs in *dry-run* mode. Notice the log line
> `[dry-run] Telegram alert suppressed`. This is a crucial agent-safety idea:
> **a test must not cause real side-effects** (no live alerts, no restarting
> containers, no truncating logs). Open `ella_mcp_server.py` and find the
> `_DRY_RUN` flag to see how that's enforced.

### Exercise 2.2 — Talk to the agent the way an LLM would (real MCP client)

The self-test calls the functions directly. A real AI agent instead speaks the
**MCP protocol**. Let's prove the server is a genuine MCP endpoint by connecting a
client to it.

Create `mcp_demo.py` in the repo root:

```python
import asyncio, os
from mcp.client.stdio import stdio_client, StdioServerParameters
from mcp.client.session import ClientSession

async def main():
    params = StdioServerParameters(
        command="python",
        args=["agent/ella_mcp_server.py"],
        env={**os.environ},
    )
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            print("Discovered tools:", sorted(t.name for t in tools.tools))

            res = await s.call_tool("get_cellular_status", {})
            print("get_cellular_status ->", res.content[0].text)

            res = await s.call_tool("provision_subscriber", {"imsi": "999700000000055"})
            print("provision_subscriber ->", res.content[0].text)

asyncio.run(main())
```

Run it:

```bash
python mcp_demo.py
```

Expected: `Discovered tools: ['apply_remediation', 'evaluate_well_architected',
'get_cellular_status', 'provision_subscriber', 'restart_core_service']`, followed
by two JSON tool results.

> 🔑 **Key insight:** This `list_tools` / `call_tool` handshake is exactly what a
> framework like Bedrock Agents, LangGraph, or Claude Desktop does under the hood.
> You just *became* the LLM. The agent's "intelligence" chooses *which* tool and
> *what* arguments; MCP is the standardized wire between brain and hands.

### Exercise 2.3 — Experience a tool boundary (input validation)

Try to provision a bad subscriber:

```bash
python - <<'PY'
import ella_mcp_server as e
print(e._provision_subscriber(imsi="123"))                 # too short
print(e._provision_subscriber(imsi="999700000000001",
                              key_k="not-hex"))            # bad key
print(e._provision_subscriber())                           # valid defaults
PY
```

> 🛡️ **Learning point:** The first two calls return `{"success": false, ...}`
> *without touching any state*. Agents act on untrusted LLM output, so **every
> tool validates its own inputs** — this is a primary defense against prompt
> injection and malformed actions.

---

## 3. Module — The agent's memory

Agents need to remember. This system uses three SQLite-backed tiers:

| Tier | Table | Lifespan | Example use |
|---|---|---|---|
| Short-term session | `session_memory` | Current operations | Every tool call is logged here |
| Long-term incident | `remediation_memory` | Across outages | "Last time memory spiked, a restart fixed it" |
| Long-term topology | `topology_memory` | Network state | Which subscribers/slices exist |

### Exercise 3.1 — Watch memory accumulate

After doing Module 2, inspect the database:

```bash
sqlite3 "$ELLA_MEMORY_DB" "SELECT event_type, substr(details,1,60) FROM session_memory ORDER BY id DESC LIMIT 8;"
sqlite3 "$ELLA_MEMORY_DB" "SELECT entity, state FROM topology_memory;"
```

> 🔎 **Observe:** Every tool execution left a trace in `session_memory`, and each
> `provision_subscriber` wrote a row to `topology_memory`. This is **auditability
> and lineage** — you can reconstruct exactly what the agent did and when.

### Exercise 3.2 — Simulate incident memory

```bash
python - <<'PY'
import ella_mcp_server as e
e.init_db()
e.log_remediation_outcome("high_memory_or_crash", "docker_restart", "success")
e.log_remediation_outcome("ogstun_missing", "flush_stale_iptables", "success")
PY
sqlite3 "$ELLA_MEMORY_DB" "SELECT trigger_cause, action_taken, outcome FROM remediation_memory;"
```

> 🧠 **Why this matters:** When the same failure recurs, a smarter agent can
> *retrieve* `remediation_memory` and prefer an action that worked before, instead
> of reasoning from scratch. That retrieval-over-reasoning pattern is the heart of
> long-term agent memory.

---

## 4. Module — Observe & self-heal (the Day-2 loop)

`agent/self_healing_loop.py` is the autonomous **Thought → Action → Observation**
engine. On a loop it:
1. **Observes** container state + the `/healthz` endpoint + host memory.
2. **Thinks**: counts consecutive failures; checks a memory floor.
3. **Acts**: after `FAIL_THRESHOLD` failures (or on memory pressure) it calls
   `restart_core_service()` and logs the incident.

Its behavior is tunable entirely through environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `ELLA_POLL_INTERVAL` | `15` | Seconds between observations |
| `ELLA_FAIL_THRESHOLD` | `3` | Consecutive failures before healing |
| `ELLA_MIN_FREE_MB` | `80` | Memory floor that triggers a restart |
| `ELLA_HEALTH_URL` | `http://localhost:8080/healthz` | Endpoint to probe |

### Exercise 4.1 — Run the loop against a "down" core (local, no Docker needed)

Point the loop at a URL that doesn't exist so it always sees failure, and speed it
up so you don't wait:

```bash
ELLA_POLL_INTERVAL=2 ELLA_FAIL_THRESHOLD=3 \
ELLA_HEALTH_URL="http://localhost:59999/healthz" \
python agent/self_healing_loop.py
```

Watch stderr. You'll see:
```
Health check failing (1/3): ...
Health check failing (2/3): ...
Health check failing (3/3): ...
Triggering self-heal (cause=health_check_failure). Restarting ella-core.
```
Press **Ctrl-C** to stop.

> 🔎 **Observe the loop's "patience":** It does **not** heal on the first failure.
> Requiring 3 consecutive failures prevents the agent from overreacting to a single
> transient blip — a core reliability pattern (debouncing). Try
> `ELLA_FAIL_THRESHOLD=1` and watch it react immediately. Which is safer in
> production, and why?

### Exercise 4.2 — Trace the heal in memory

After the loop triggers a heal, check what it remembered (without Docker, the
restart "fails" gracefully — that's fine, the *decision* is what we're studying):

```bash
sqlite3 "$ELLA_MEMORY_DB" "SELECT event_type FROM session_memory WHERE event_type LIKE 'self_heal%' OR event_type LIKE 'tool_restart%';"
```

> 🧠 Notice the agent recorded both the **decision** (`self_heal_triggered`) and the
> **action attempt** (`tool_restart_core_service`). Separating "what I decided" from
> "what happened" is essential for debugging autonomous systems.

---

## 5. Module — Guardrails: Well-Architected audit & human-in-the-loop

Autonomy without guardrails is dangerous. Two mechanisms keep this agent safe.

### Exercise 5.1 — Run a live Well-Architected audit

```bash
python - <<'PY'
import json, ella_mcp_server as e
print(json.dumps(e._evaluate_well_architected(), indent=2))
PY
```

You'll get a per-pillar report (cost / reliability / security / performance). Run
locally, some checks return `SKIPPED` ("aws CLI not available", "could not read
IMDS") — **that's expected off-AWS**. On a real instance they turn into real
findings.

> 🔎 **Learning point:** Compare this to the *old* version of the code (see
> `CHANGELOG.md`), which returned **hardcoded** "PASSED" strings. A real audit
> tool must *measure the live system*. An agent that lies about its own posture is
> worse than no agent.

### Exercise 5.2 — Hit the human-in-the-loop gate

Ask the agent to do something destructive:

```bash
python - <<'PY'
import json, ella_mcp_server as e
print(json.dumps(e._apply_remediation("wipe_subscriber_db"), indent=2))
PY
```

Expected: `"approval_required": true` and **no action taken**. Now inspect the
request the agent filed for a human:

```bash
cat "$ELLA_APPROVAL_FILE"
```

> 🛑 **Key insight:** `wipe_subscriber_db`, `teardown_vpc`, and `delete_volume` are
> on a **deny-by-default destructive list**. Instead of executing, the agent
> *halts*, writes `approval_pending.json`, and (if configured) pings a human on
> Telegram. Compare with a *safe* action that runs immediately:
> ```bash
> python -c "import ella_mcp_server as e; print(e._apply_remediation('clear_logs'))"
> ```
> This is the difference between an agent that **asks forgiveness** and one that
> **asks permission** — for high-impact changes, always the latter.

### Exercise 5.3 — (Optional) Wire up real alerts

If you have a Telegram bot (via BotFather):

```bash
export TELEGRAM_BOT_TOKEN="123456789:your-real-token"
export TELEGRAM_CHAT_ID="your-chat-id"
bash agent/test_telegram_alert.sh
```

> 🔐 **Security habit:** Never commit these values. They belong in environment
> variables or `/etc/ella-agent/telegram.env` (already in `.gitignore`).

---

## 6. Module — Day-0/Day-1: deploy the real thing on AWS (optional)

> ⚠️ **Costs money if misused.** Everything is Free-Tier sized, but confirm your
> account's eligibility and **always `terraform destroy` when finished.**

### Exercise 6.1 — Read the infrastructure before running it

Before `apply`, *read* `infra/main.tf` and answer:
- Which ports does the security group open, and which is scoped by a variable?
- What makes the IAM role **least-privilege** (hint: search for the log-group ARN)?
- Where does `cloud-init.yaml` actually start the agent?

> 🔎 This "read the IaC first" habit is itself part of the lifecycle: the
> **Intake/IaC agent** reasons about infrastructure the same way.

### Exercise 6.2 — Deploy

```bash
cd infra
terraform init
terraform validate                      # should print: Success!
terraform apply -var="ssh_ingress_cidr=$(curl -s https://checkip.amazonaws.com)/32"
```

Note the `instance_public_ip` and `healthcheck_url` outputs.

### Exercise 6.3 — Verify on the host

SSH in (`ssh ubuntu@<instance_public_ip>`), then:

```bash
docker ps                               # ella-core should be Up/healthy
ip addr show ogstun                     # user-plane TUN interface
systemctl status ella-agent             # the self-healing loop, Active (running)
journalctl -u ella-agent -n 20          # the agent's live observations
```

### Exercise 6.4 — Trigger a REAL self-heal

This is the payoff — autonomous recovery on live infrastructure:

```bash
docker stop ella-core                   # simulate a crash
journalctl -u ella-agent -f             # watch failures accumulate, then a restart
docker ps                               # ella-core back Up within ~30s
```

### Exercise 6.5 — Tear down (do not skip!)

```bash
cd infra
terraform destroy
```

> ✅ Confirm in the AWS console that the EC2 instance, EIP, and VPC are gone to
> return to **$0**.

---

## 6b. Module — End-to-end: attach a real RAN + UE (optional, Cloud)

So far the agent *manages* a core that nothing connects to. This module stands up
a **UERANSIM gNodeB + UE** on a **second Free-Tier instance** and drives real
traffic: **UE → gNodeB → ella-core (N2/N3) → NAT → internet.**

### How the two hosts talk
Both instances live in the same VPC subnet and communicate over **private IPs**.
ella-core's security group allows N2 (SCTP/UDP 38412) and N3 (GTP-U 2152)
**only from the simulator's security group** — not the public internet. Terraform
passes ella-core's private IP into the simulator so UERANSIM's `gnb.yaml` targets
the right AMF automatically.

> 🔎 **Learning point:** This is a deliberate security design. SCTP across the
> public internet is unreliable, and exposing GTP-U to the world is dangerous.
> Scoping ingress to a *source security group* (not a CIDR) is the Well-Architected
> way to let two tiers talk privately.

### Exercise 6b.1 — Deploy both hosts

```bash
cd infra
terraform apply -var="ssh_ingress_cidr=$(curl -s https://checkip.amazonaws.com)/32"
terraform output        # note simulator_public_ip and ella_core_private_ip
```

### Exercise 6b.2 — Provision the matching subscriber

The UE's IMSI/Ki/OPc must exist in ella-core. On the **core** host, provision it
via the agent (the SIM config already matches these defaults):

```bash
# Using an MCP client (see §2.2), call provision_subscriber() with defaults,
# or exercise the tool directly for learning:
cd /opt/ella/src
/opt/ella/agent/venv/bin/python -c "import sys; sys.path.insert(0,'agent'); import ella_mcp_server as e; print(e._provision_subscriber())"
```

### Exercise 6b.3 — Watch the gNodeB register

SSH to the **simulator** host (`simulator_public_ip`):

```bash
cd /opt/ella-sim/sim
docker compose logs gnb | grep -i "NG Setup"
```
Look for an **NG Setup** success — the gNodeB has associated with ella-core's AMF
over N2.

### Exercise 6b.4 — Attach the UE and go online

```bash
docker compose run --rm ue           # watch for "PDU Session establishment is successful"
# in a second shell on the sim host:
ip addr show uesimtun0               # the UE's data-plane interface, e.g. 10.45.0.x
ping -I uesimtun0 -c 4 8.8.8.8       # 🎉 traffic out via ella-core's NAT
curl --interface uesimtun0 -s https://checkip.amazonaws.com
```

> 🎯 A successful ping over `uesimtun0` means you've exercised the **entire** 5G
> path: registration + authentication (control plane) *and* a PDU session carrying
> user data through the core to the internet.

### Exercise 6b.5 — Let the agent confirm the attach

Back on the **core** host, have the agent verify end-to-end from its own vantage:

```bash
/opt/ella/agent/venv/bin/python -c "import sys,json; sys.path.insert(0,'agent'); import ella_mcp_server as e; print(json.dumps(e._run_e2e_attach_test(), indent=2))"
```

Expected (with the UE attached): `"n2_association_up": true`,
`"n3_gtpu_tunnels"` ≥ 1, `"attached": true`.

> 🧠 **Why this matters:** The agent doesn't just *host* the core — it can now
> **observe the live attach state** and remember it (`topology_memory`). Combine
> this with Module 4: an agent could detect that a UE *dropped* and react.

### Exercise 6b.6 — Tear down

`terraform destroy` removes **both** instances. Don't skip it.

---

## 7. Where to go next (stretch goals)

- **Connect a real LLM:** register this MCP server with Claude Desktop or an agent
  framework and ask it in natural language to "check the core and provision a test
  subscriber." Watch it choose tools on its own.
- **Add a tool:** implement `deprovision_subscriber(imsi)` with validation + memory
  logging, following the pattern of `provision_subscriber`. Add a test case.
- **Make healing smarter:** before restarting, have the loop query
  `remediation_memory` and escalate to a human if the same cause recurred 3× in an
  hour (combine Modules 3, 4, and 5).
- **Approve a gated action:** design the "other half" of the HITL gate — a tool or
  script that reads `approval_pending.json`, and only then performs the action.

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `ModuleNotFoundError: mcp` | Activate the venv and `pip install -r agent/requirements.txt` |
| `No module named 'mcp.server.fastmcp'` | You have MCP SDK v2; this repo pins v1. Reinstall: `pip install "mcp>=1.2,<2"` |
| Self-test writes to `/var/lib/...` permission error | Export `ELLA_MEMORY_DB`/`ELLA_APPROVAL_FILE` to a local path (see §1) |
| `sqlite3: command not found` | Install the SQLite CLI, or read tables from Python with `sqlite3` module |
| Well-Architected shows `SKIPPED` | Expected locally; only populated on an AWS instance with the AWS CLI |

Now put it all together with the formal checklist in [`TEST_CASES.md`](./TEST_CASES.md).
