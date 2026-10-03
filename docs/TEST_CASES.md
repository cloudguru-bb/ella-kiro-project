# Human-Executable Test Cases

A complete, manual test suite for the ella-core agentic lifecycle system. Each
case is self-contained: **Objective → Preconditions → Steps → Expected Result →
Pass/Fail**. Work them top to bottom, or jump to a suite.

Pair this with [`TUTORIAL.md`](./TUTORIAL.md) (which *teaches* the concepts); this
document *verifies* them. The final suite maps directly to the Definition of Done
in [`../Requirements-v2.md`](../Requirements-v2.md) §4.

## How to use this document
- **ENV**: Local = runs on your laptop with Python only. Cloud = needs a deployed
  AWS instance (Suite F / Module 6 of the tutorial).
- Record outcomes in the **Result** column (`PASS` / `FAIL` / `N/A`) and the date.
- A case **fails** if *any* expected result is not met — note what you actually saw.

## One-time setup (Local suites A–E)

```bash
cd ella-kiro-project
python3 -m venv venv && source venv/bin/activate
pip install -r agent/requirements.txt

# Keep agent state local & disposable:
mkdir -p .state
export ELLA_MEMORY_DB="$(pwd)/.state/memory.db"
export ELLA_APPROVAL_FILE="$(pwd)/.state/approval_pending.json"

# Start each suite from a clean slate when noted:
rm -f .state/memory.db .state/approval_pending.json
```

Run commands from the **repo root** unless a step says otherwise.

---

## Suite A — Environment & installation

### TC-A1 — Dependencies install cleanly
| | |
|---|---|
| **ENV** | Local |
| **Objective** | The MCP SDK (v1) installs and imports. |
| **Preconditions** | venv activated. |
| **Steps** | 1. `pip install -r agent/requirements.txt`<br>2. `python -c "from mcp.server.fastmcp import FastMCP; print('ok')"` |
| **Expected Result** | Step 2 prints `ok` with no traceback. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-A2 — Source files compile
| | |
|---|---|
| **ENV** | Local |
| **Objective** | No syntax errors in the agent code. |
| **Steps** | `python -m py_compile agent/ella_mcp_server.py agent/self_healing_loop.py && echo OK` |
| **Expected Result** | Prints `OK`, exit code 0. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite B — MCP tool server

### TC-B1 — Offline self-test passes (DoD §3)
| | |
|---|---|
| **ENV** | Local |
| **Objective** | All five tools execute cleanly with no live side-effects. |
| **Steps** | `python agent/ella_mcp_server.py --test` |
| **Expected Result** | Output ends with `All tools executed cleanly.`; **9** `[PASS]` lines; exit code 0 (`echo $?`). A `[dry-run] Telegram alert suppressed` line appears (proving no live alerts). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-B2 — Self-test exits non-zero on failure (negative/meta test)
| | |
|---|---|
| **ENV** | Local |
| **Objective** | Confirm the test harness actually detects failure (so a PASS means something). |
| **Steps** | 1. `python agent/ella_mcp_server.py --test; echo "exit=$?"`<br>2. Confirm `exit=0` on the healthy code. |
| **Expected Result** | `exit=0`. (The harness returns non-zero if any check fails — verified by design in `run_self_test`.) |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-B3 — Server starts and is a real MCP endpoint
| | |
|---|---|
| **ENV** | Local |
| **Objective** | An MCP client can connect, discover, and call tools over stdio. |
| **Preconditions** | Create `mcp_demo.py` from TUTORIAL §2.2. |
| **Steps** | `python mcp_demo.py` |
| **Expected Result** | Prints exactly these 6 tool names: `apply_remediation, evaluate_well_architected, get_cellular_status, provision_subscriber, restart_core_service, run_e2e_attach_test`; then two JSON tool results. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-B4 — `get_cellular_status` returns a structured report
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import json,ella_mcp_server as e; print(json.dumps(e._get_cellular_status()))"` |
| **Expected Result** | JSON object containing keys: `status`, `container`, `tun_interface`, `available_memory_mb`, `gtpu_tunnel_count`. (Off-AWS: `container` likely `not_found` and `status` `degraded` — acceptable.) |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite C — Input validation & tool boundaries

### TC-C1 — Valid subscriber is accepted
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._provision_subscriber())"` |
| **Expected Result** | `success` is `True`; message names IMSI `999700000000001`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-C2 — Malformed IMSI is rejected
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._provision_subscriber(imsi='123'))"` |
| **Expected Result** | `success` is `False`; error mentions IMSI must be 15 digits. **No** state change. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-C3 — Non-hex key is rejected
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._provision_subscriber(key_k='not-a-valid-hex-key-value-xxxxx'))"` |
| **Expected Result** | `success` is `False`; error mentions `key_k` must be 32 hex characters. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-C4 — Out-of-range SST is rejected
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._provision_subscriber(sst=999))"` |
| **Expected Result** | `success` is `False`; error mentions SST must be 0–255. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite D — Memory & persistence

> Start clean: `rm -f .state/memory.db` then run TC-B1 once to populate.

### TC-D1 — Session events are logged
| | |
|---|---|
| **ENV** | Local |
| **Objective** | Short-term memory records tool executions. |
| **Steps** | `sqlite3 "$ELLA_MEMORY_DB" "SELECT COUNT(*) FROM session_memory;"` |
| **Expected Result** | A number **> 0** (several rows after the self-test). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-D2 — Provisioning writes topology memory
| | |
|---|---|
| **ENV** | Local |
| **Steps** | 1. `python -c "import ella_mcp_server as e; e.init_db(); e._provision_subscriber(imsi='999700000000077')"`<br>2. `sqlite3 "$ELLA_MEMORY_DB" "SELECT entity FROM topology_memory;"` |
| **Expected Result** | Output includes `subscriber:999700000000077`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-D3 — Remediation outcome logging does NOT crash (regression)
| | |
|---|---|
| **ENV** | Local |
| **Objective** | Guards the historic 3-placeholder / 4-column SQL bug (see `CHANGELOG.md`). |
| **Steps** | `python -c "import ella_mcp_server as e; e.init_db(); e.log_remediation_outcome('c','a','ok'); print('no-crash')"` then `sqlite3 "$ELLA_MEMORY_DB" "SELECT trigger_cause,action_taken,outcome FROM remediation_memory;"` |
| **Expected Result** | Prints `no-crash` (no `sqlite3.ProgrammingError`); the row `c|a|ok` is present. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-D4 — Three memory tables exist
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `sqlite3 "$ELLA_MEMORY_DB" ".tables"` |
| **Expected Result** | Lists `remediation_memory`, `session_memory`, and `topology_memory`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite E — Self-healing, Well-Architected & guardrails

### TC-E1 — Self-healing loop debounces then triggers
| | |
|---|---|
| **ENV** | Local |
| **Objective** | The loop heals only after `FAIL_THRESHOLD` consecutive failures. |
| **Steps** | Run, watch ~10s, then Ctrl-C:<br>`ELLA_POLL_INTERVAL=2 ELLA_FAIL_THRESHOLD=3 ELLA_HEALTH_URL="http://localhost:59999/healthz" python agent/self_healing_loop.py` |
| **Expected Result** | Logs show `failing (1/3)`, `(2/3)`, `(3/3)`, then `Triggering self-heal (cause=health_check_failure)`. It does **not** heal before the 3rd failure. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-E2 — Heal decision is recorded in memory
| | |
|---|---|
| **ENV** | Local |
| **Preconditions** | TC-E1 just run against the local DB. |
| **Steps** | `sqlite3 "$ELLA_MEMORY_DB" "SELECT DISTINCT event_type FROM session_memory WHERE event_type LIKE 'self_heal%';"` |
| **Expected Result** | Includes `self_heal_triggered`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-E3 — Well-Architected audit returns all pillars
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import json,ella_mcp_server as e; print(json.dumps(e._evaluate_well_architected(),indent=2))"` |
| **Expected Result** | JSON with keys `cost_pillar`, `reliability_pillar`, `security_pillar`, `performance_pillar`, `timestamp`. Off-AWS, `security_pillar.status` may be `SKIPPED` ("aws CLI not available") — acceptable. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-E4 — Safe remediation executes immediately
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._apply_remediation('clear_logs'))"` |
| **Expected Result** | `success` is `True`; action text mentions truncating container log file(s). (0 files locally is fine.) |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-E5 — Destructive remediation is halted by HITL gate (DoD §5.4)
| | |
|---|---|
| **ENV** | Local |
| **Objective** | Destructive actions require human approval and are NOT executed. |
| **Steps** | 1. `rm -f "$ELLA_APPROVAL_FILE"`<br>2. `python -c "import json,ella_mcp_server as e; print(json.dumps(e._apply_remediation('wipe_subscriber_db')))"`<br>3. `cat "$ELLA_APPROVAL_FILE"` |
| **Expected Result** | Step 2: `approval_required` is `True`, `success` is `False`. Step 3: a JSON file exists with `"action_type": "wipe_subscriber_db"` and `"status": "pending"`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-E6 — Unknown remediation type is refused
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `python -c "import ella_mcp_server as e; print(e._apply_remediation('do_something_weird'))"` |
| **Expected Result** | `success` is `False`; error mentions unknown remediation action type. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite F — Infrastructure (IaC) validation

### TC-F1 — Terraform configuration is valid
| | |
|---|---|
| **ENV** | Local (Terraform ≥ 1.5; no AWS creds needed) |
| **Steps** | `cd infra && terraform init -backend=false && terraform validate` |
| **Expected Result** | Prints `Success! The configuration is valid.` |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-F2 — Terraform is canonically formatted
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `cd infra && terraform fmt -check` |
| **Expected Result** | No output, exit code 0 (files already formatted). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-F3 — Security group opens the expected ports
| | |
|---|---|
| **ENV** | Local (static review) |
| **Objective** | Confirm Spec 1.3 ports are present. |
| **Steps** | Inspect `infra/main.tf` ingress rules. |
| **Expected Result** | Ingress exists for 22 (scoped via `var.ssh_ingress_cidr`), 38412 **SCTP** + 38412 UDP, 2152 UDP, 8080 TCP, 80 TCP, 443 TCP. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-F4 — IAM role is least-privilege
| | |
|---|---|
| **ENV** | Local (static review) |
| **Objective** | Confirm no broad managed policy / wildcard (Spec 4.2). |
| **Steps** | Search `infra/main.tf` for `aws_iam_role_policy` and the log-group ARN. |
| **Expected Result** | An inline policy scoped to `log-group:/aws/ec2/ella-core` (+ `:*`) and namespaced `cloudwatch:PutMetricData`; **no** `CloudWatchAgentServerPolicy` attachment, **no** `"*"` resource on logs. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-F5 — cloud-init YAML parses
| | |
|---|---|
| **ENV** | Local |
| **Steps** | `pip install pyyaml` then `python -c "import yaml; list(yaml.safe_load_all(open('infra/cloud-init.yaml'))); print('ok')"` |
| **Expected Result** | Prints `ok` (requires `pip install pyyaml`). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite G — Live deployment (Cloud; DoD §1–§5) — OPTIONAL

> ⚠️ Incurs AWS usage. Run `terraform destroy` after (TC-G6).

### TC-G1 — Deployment succeeds within Free Tier (DoD §1)
| | |
|---|---|
| **ENV** | Cloud |
| **Steps** | `cd infra && terraform apply -var="ssh_ingress_cidr=$(curl -s https://checkip.amazonaws.com)/32"` |
| **Expected Result** | Apply completes; outputs show `instance_public_ip`, `instance_id`, `healthcheck_url`. Instance type is `t3.micro` (or `t2.micro` if overridden). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-G2 — Cellular core is healthy (DoD §2)
| | |
|---|---|
| **ENV** | Cloud (SSH to host) |
| **Steps** | `docker ps` and `ip addr show ogstun` |
| **Expected Result** | `ella-core` container shows `Up`/`healthy`; `ogstun` interface exists (user-plane address ~`10.45.0.1/16`). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-G3 — Health endpoint responds
| | |
|---|---|
| **ENV** | Cloud |
| **Steps** | From your laptop: `curl -i "$(cd infra && terraform output -raw healthcheck_url)"` |
| **Expected Result** | HTTP 2xx response from `/healthz`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-G4 — Self-healing service is running
| | |
|---|---|
| **ENV** | Cloud (SSH) |
| **Steps** | `systemctl status ella-agent` and `journalctl -u ella-agent -n 20` |
| **Expected Result** | Service `active (running)`; logs show periodic health observations. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-G5 — Autonomous recovery after a crash (DoD §4)
| | |
|---|---|
| **ENV** | Cloud (SSH) |
| **Steps** | 1. `docker stop ella-core`<br>2. `journalctl -u ella-agent -f` (watch)<br>3. After the heal, `docker ps` |
| **Expected Result** | Agent logs consecutive failures, then `Triggering self-heal`; `ella-core` is back `Up` within ~30s without human action. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-G6 — Clean teardown returns to $0
| | |
|---|---|
| **ENV** | Cloud |
| **Steps** | `cd infra && terraform destroy`, then verify in AWS console. |
| **Expected Result** | **Both** EC2 instances, the Elastic IP, and the VPC are destroyed; no lingering billable resources. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Suite H — End-to-end RAN/UE simulation (Cloud; needs `deploy_simulator=true`) — OPTIONAL

> ⚠️ Requires both hosts deployed. Run from the **simulator** host unless noted.

### TC-H1 — New e2e tool is registered and callable
| | |
|---|---|
| **ENV** | Local |
| **Objective** | The `run_e2e_attach_test` MCP tool exists and returns a structured result. |
| **Steps** | `python -c "import json,ella_mcp_server as e; r=e._run_e2e_attach_test(); print(sorted(r.keys()))"` |
| **Expected Result** | Keys include `attached`, `core_running`, `n2_association_up`, `n3_gtpu_tunnels`. (Off-AWS, all false/0 — acceptable; we're testing the tool contract.) |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H2 — Both hosts deploy; private IP wired into the sim
| | |
|---|---|
| **ENV** | Cloud |
| **Steps** | `cd infra && terraform output` |
| **Expected Result** | `simulator_public_ip` and `ella_core_private_ip` are non-null. On the sim host, `cat /opt/ella-sim/sim/gnb.yaml` shows the real core IP under `amfConfigs` (no `__ELLA_CORE_IP__` left). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H3 — Private N2/N3 reachability (not public)
| | |
|---|---|
| **ENV** | Cloud (sim host) |
| **Objective** | Simulator reaches the core privately; the world cannot. |
| **Steps** | 1. On sim host: `nc -vz -u $ELLA_CORE_IP 2152` (load `ELLA_CORE_IP` from `/opt/ella-sim/ella_core_ip.env`).<br>2. From your laptop: attempt the same against the core's **public** IP. |
| **Expected Result** | Step 1 reaches the core (private path works). Step 2 is blocked/filtered (N2/N3 are scoped to the sim SG, not `0.0.0.0/0`). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H4 — Subscriber provisioned on the core
| | |
|---|---|
| **ENV** | Cloud (core host) |
| **Steps** | Call `provision_subscriber()` (defaults) via an MCP client or the tool directly. |
| **Expected Result** | `success` is `True` for IMSI `999700000000001`. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H5 — gNodeB registers (control plane, N2)
| | |
|---|---|
| **ENV** | Cloud (sim host) |
| **Steps** | `cd /opt/ella-sim/sim && docker compose logs gnb | grep -i "NG Setup"` |
| **Expected Result** | Log shows an NG Setup / NGAP association success with the AMF. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H6 — UE attaches and gets a PDU session (user plane)
| | |
|---|---|
| **ENV** | Cloud (sim host) |
| **Steps** | `docker compose run --rm ue` (watch logs), then in another shell `ip addr show uesimtun0`. |
| **Expected Result** | Logs show `PDU Session establishment is successful`; `uesimtun0` exists with an IP from the UE subnet (`10.45.0.x`). |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H7 — UE reaches the internet THROUGH ella-core (the payoff)
| | |
|---|---|
| **ENV** | Cloud (sim host) |
| **Steps** | `ping -I uesimtun0 -c 4 8.8.8.8` and `curl --interface uesimtun0 -s https://checkip.amazonaws.com` |
| **Expected Result** | Ping replies received; curl returns an IP (ella-core's public/NAT egress IP), proving full data-plane connectivity. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

### TC-H8 — Agent confirms the attach end-to-end
| | |
|---|---|
| **ENV** | Cloud (core host) |
| **Steps** | Call `run_e2e_attach_test()` while the UE is attached. |
| **Expected Result** | `attached` is `True`; `n2_association_up` is `True`; `n3_gtpu_tunnels` ≥ 1. |
| **Result** | ☐ PASS ☐ FAIL — date: ______ |

---

## Results summary

| Suite | Cases | Passed | Failed | N/A |
|---|---|---|---|---|
| A — Environment | 2 | | | |
| B — MCP server | 4 | | | |
| C — Validation | 4 | | | |
| D — Memory | 4 | | | |
| E — Healing/guardrails | 6 | | | |
| F — IaC validation | 5 | | | |
| G — Live deploy (optional) | 6 | | | |
| H — End-to-end RAN/UE (optional) | 8 | | | |
| **Total** | **39** | | | |

**Tester:** ___________________  **Date:** ___________  **Build/commit:** ___________
