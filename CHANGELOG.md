# Changelog

## RAN/UE simulator on a dedicated host

Added full end-to-end simulation: a **second Free-Tier EC2 instance** running the
UERANSIM gNodeB + UE via Docker, attaching to ella-core for both control plane
(N2/NGAP) and user plane (N3/GTP-U) with internet egress through ella-core's NAT.

### New `sim/` module
- `sim/docker-compose.yml` — UERANSIM gNodeB + UE (`gradiant/ueransim:3.2.6`),
  host networking, TUN device for the UE's `uesimtun0` interface.
- `sim/gnb.yaml.tmpl` / `sim/ue.yaml.tmpl` — configs templated with the core/host
  IPs at boot; PLMN 999/70, TAC 1, slice SST 1/SD 000001, and IMSI/Ki/OPc matched
  to `provision_subscriber()` so attach works out of the box.
- `sim/README.md` — end-to-end attach + data-plane (`ping -I uesimtun0`) test guide.

### Infrastructure (`infra/main.tf`)
- Added a second instance `ran_sim_host`, gated by `var.deploy_simulator` (default
  true), with its own `var.simulator_instance_type` and a 10 GB root volume (keeps
  total EBS at 30 GB Free Tier).
- Added `infra/cloud-init-sim.yaml`; the instance's `user_data` is rendered via
  `templatefile()` with ella-core's **private** IP so the gNodeB targets the AMF.
- **Networking:** moved N2/N3 ingress off the SG block into dedicated
  `aws_security_group_rule` resources scoped to the simulator's SG via
  `source_security_group_id` — N2/N3 are now reachable **only** from the simulator
  (private, VPC-internal), not `0.0.0.0/0`.
- Added a dedicated simulator SG (SSH + egress) and new outputs
  (`ella_core_private_ip`, `simulator_public_ip`, `simulator_instance_id`).

### Agent (`agent/ella_mcp_server.py`)
- New MCP tool **`run_e2e_attach_test()`**: from the core host, confirms the core is
  running, an SCTP association is up on N2 (gNodeB connected), and GTP-U tunnel(s)
  exist on N3 (UE PDU session) — and records the outcome to topology memory. Makes
  the end-to-end simulation part of the agentic lifecycle. (Tool count: 5 → 6.)

### Docs
- Added TUTORIAL Module 6b and TEST_CASES Suite H for the simulator.

## Agentic lifecycle completion

Restructured the flat repo into the spec's `/infra`, `/app`, `/agent` layout and
fixed every issue found in the initial drop.

### Structure
- Moved files into `infra/`, `app/`, `agent/` as called for by `Requirements-v2.md` §5.
- Renamed `ella_mcp_server-v2.py` → `agent/ella_mcp_server.py` (matches the DoD command).
- Added `.gitignore`, `README.md`, `CHANGELOG.md`.

### Bug fixes (`agent/ella_mcp_server.py`)
- **SQL parameter mismatch (crash):** `log_remediation_outcome` INSERT now has four
  placeholders to match its four columns. Previously `(?, ?, ?)` with four values
  raised `sqlite3.ProgrammingError` on *every* self-healing event.
- **`--test` flag:** implemented real argparse handling. `--test` runs an offline,
  dry-run self-test of all five tools (no live Telegram alerts, no host mutation) and
  exits non-zero on any failure. Previously the self-test ran on *every* invocation
  and fired live alerts.
- **`apply_remediation("clear_logs")` was a no-op:** it built a command string but never
  executed it. It now truncates the container json logs and reports how many files.

### Real MCP server (was not actually MCP)
- Wired the five tools into a `FastMCP` server (official `mcp` SDK v1) over the stdio
  transport, with tool registration and docstrings. Verified an MCP client can
  `initialize`, `list_tools` (returns all 5), and `call_tool`.

### Spec compliance filled in
- **Self-healing loop (Spec 5.2):** new `agent/self_healing_loop.py` daemon polls health
  + container state + memory and auto-restarts after N consecutive failures or on memory
  pressure; logs incidents to long-term memory. Shipped with a systemd unit.
- **Live Well-Architected audit (Spec 5.3):** `evaluate_well_architected` now inspects the
  live instance type (IMDSv2), host memory, and security-group ingress (via AWS CLI) for
  world-open SSH — instead of returning hardcoded results.
- **Human-in-the-loop gate (Spec 5.4):** destructive actions (`wipe_subscriber_db`,
  `teardown_vpc`, `delete_volume`) halt and write `approval_pending.json`.
- **Topological memory (Spec 4.1):** added `topology_memory` table and recorded subscriber
  provisioning into it.
- **Scoped IAM (Spec 4.2):** replaced the broad `CloudWatchAgentServerPolicy` managed policy
  with a least-privilege inline policy limited to the `/aws/ec2/ella-core` log group plus
  namespaced `PutMetricData` (no wildcard IAM).
- **Stronger input validation:** `provision_subscriber` validates IMSI, Ki/OPc (32 hex),
  SST (0-255), and SD (6 hex).

### Infrastructure (`infra/main.tf`)
- Added ingress for HTTP (80) and HTTPS (443) per Spec 1.3.
- Added native **SCTP** (protocol 132) ingress for N2/38412 (kept the UDP fallback).
- SSH ingress is now scoped via a `ssh_ingress_cidr` variable (defaults open, documented).
- Added `instance_type` variable (default `t3.micro`; `t2.micro` override documented).
- Added an **Elastic IP** (Spec 2.1) and switched outputs to it.
- `user_data_replace_on_change = true` for clean re-provisioning.

### Host bootstrap (`infra/cloud-init.yaml`)
- Now actually **deploys the workload**: clones the repo, copies app + agent files into
  `/opt/ella`, runs `docker compose up -d`, creates the agent virtualenv, installs
  `requirements.txt`, and enables the `ella-agent` self-healing systemd service.
- Added `git` and `python3` to packages.

### Missing config added
- **`app/ella-core.yaml`** — the config file that `docker-compose.yml` mounts but which did
  not exist. ella-core would not start correctly without it.
