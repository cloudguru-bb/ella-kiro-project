> **⚠️ Implementation note (updated after live testing).** This spec was written
> against an assumed Open5GS-style image. The real upstream **Ella Core**
> (`ghcr.io/ellanetworks/ella-core`) differs in several ways, and the code now
> follows the upstream reality, not these original lines:
> - Image is `ghcr.io/ellanetworks/ella-core:v1.19.0` (not `ella-core/ella-core:v0.1.0`).
> - Config is a single `--config /config/config.yaml` file in the upstream schema
>   (not env vars, not `/etc/ella/ella-core.yaml`).
> - REST API + UI (and the health probe `/api/v1/metrics`) are on **:5002**, not :8080.
> - The user-plane datapath is **eBPF (XDP/TCX)** on the host NICs — there is **no**
>   `ogstun` TUN device or Open5GS iptables NAT; only a generic egress masquerade.
>
> See `CHANGELOG.md` and `README.md` for the authoritative, as-built behavior.

# Project Specification v2: Minimal ella-core Deployment with Autonomous Agentic Lifecycle Management on AWS

## 1. Executive Summary & Objective
This updated specification defines the functional, technical, and architectural requirements for building, deploying, and autonomously operating a lightweight instance of **ella-core** (cellular core network stack) on **AWS Free Tier** infrastructure.

In addition to the core cellular deployment (Day-0/Day-1), this specification integrates **Full Lifecycle AI Agent System Elements**—derived from the AWS AI Agent Learning Series and AWS Well-Architected Agent framework—to deliver end-to-end autonomous lifecycle management across:
- **Phase 1: Foundation & Agent Architecture** (Frameworks, MCP Tool Boundaries, Thought-Action-Observation loop).
- **Phase 2: Building & Multi-Agent Orchestration** (Intake/IaC Agent, Deployment Agent, Well-Architected Review Agent, Observability/Healing Agent).
- **Phase 3: Operating, Memory & Security Governance** (In-context, short-term, and long-term memory, task-scoped IAM roles, CloudWatch log lineage).
- **Phase 4: Scaling, Continuous Evaluation & Guardrails** (Bedrock AgentCore trajectory evaluations, cost guardrails, human-in-the-loop gates).

---

## 2. Constraints & Free Tier Target Architecture

### 2.1 AWS Free Tier Guardrails
- **Compute**: Single `t3.micro` (or `t2.micro`) EC2 instance (1 vCPU, 1 GB RAM, 750 hours/month free).
- **Storage**: 20 GB General Purpose SSD (`gp3`) EBS volume (up to 30 GB total free).
- **Networking**: AWS VPC with single public subnet, Elastic IP, Security Group with restricted ingress.
- **Agent State & Memory**: Local SQLite database / DynamoDB Local / JSON file store (< 25 GB free tier).
- **Observability & Agent Tracing**: CloudWatch Agent for container logs & metrics (< 5 GB/month free).

### 2.2 System Architecture Diagram (Cellular Core + Agent Lifecycle Plane)
```
[ gNodeB / UE Simulator ]
         │ (SCTP/GTP-U/HTTP)
         ▼
[ AWS VPC Security Group ]
         │
         ▼
[ AWS EC2 t3.micro (Ubuntu 24.04 LTS) ]
  ├── Linux Kernel (TUN/TAP Device `ogstun`, IP Forwarding, iptables NAT)
  ├── Docker Runtime
  │     └── Container: ella-core (AMF / SMF / UPF / Subscriber DB)
  │
  └── [ Autonomous Local Agent Control Plane ]
        ├── Model Context Protocol (MCP) Tool Server
        ├── Multi-Agent Orchestrator (State Machine)
        ├── Agent Memory Store (SQLite / JSON)
        └── CloudWatch Logs & Metrics Telemetry Agent
```

---

## 3. Detailed Functional & System Requirements

### Requirement 1: Infrastructure as Code (IaC) Provisioning (Day-0 / Day-1)
- **Spec 1.1**: Provide a single-file Terraform (`main.tf`) or AWS CDK script to provision the underlying AWS infrastructure.
- **Spec 1.2**: Create a VPC with CIDR `10.0.0.0/16`, a single Public Subnet `10.0.1.0/24`, an Internet Gateway, and a Route Table.
- **Spec 1.3**: Configure Security Group rules allowing:
  - `SSH (22)` from designated admin IP.
  - `SCTP / UDP (38412, 2152)` for gNodeB / N2 / N3 signaling and GTP-U data tunnels.
  - `HTTP/HTTPS (80, 443, 8080)` for management REST API and Agent MCP server endpoints.
- **Spec 1.4**: Launch an Ubuntu 24.04 LTS `t3.micro` instance with 20GB `gp3` root volume and auto-assigned public IP.

---

### Requirement 2: Host OS, Kernel & Container Configuration
- **Spec 2.1**: Provision automated user-data initialization script (`cloud-init`) to update host OS packages, install Docker Engine, Python 3.12, and MCP server runtime.
- **Spec 2.2**: Enable kernel IP forwarding (`sysctl -w net.ipv4.ip_forward=1`).
- **Spec 2.3**: Create and configure persistent TUN device (`/dev/net/tun`) required for user-plane packet routing.
- **Spec 2.4**: Configure iptables NAT / MASQUERADE rules on the primary interface (`eth0`) for user-plane internet egress:
  ```bash
  iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
  ```
- **Spec 2.5**: Define a minimal `docker-compose.yml` deploying `ella-core` with memory limit <= 512 MB, `NET_ADMIN` capabilities, and local volume mounts for `ella-core.yaml`.

---

### Requirement 3: Multi-Agent System Architecture & MCP Tool Boundaries
- **Spec 3.1: Model Context Protocol (MCP) Server**: Implement an MCP server (`ella_mcp_server.py`) on the host/EC2 exposing standardized agent tools:
  - `get_cellular_status()`: Queries `ella-core` health and active GTP-U tunnel count.
  - `provision_subscriber(imsi, key, opc, slice)`: Provision or update subscriber profiles.
  - `restart_core_service()`: Gracefully restarts container stack upon crash detection.
  - `evaluate_well_architected()`: Runs automated 6-pillar posture checks on host OS and AWS security group.
  - `apply_remediation(patch_type)`: Executes automated fix (e.g. flushing stale iptables, clearing container logs).
- **Spec 3.2: Multi-Agent Role Definitions**:
  1. **Topology & Provisioning Agent**: Translates high-level 3GPP network descriptors into `ella-core.yaml` and subscriber REST commands.
  2. **Well-Architected Review Agent**: Evaluates security group rules, EC2 memory pressure, and cost limits against the 6 pillars.
  3. **Day-2 Observability & Self-Healing Agent**: Continuously polls `get_cellular_status()` and CloudWatch alarms; executes auto-healing actions or escalates to human operator.

---

### Requirement 4: Agent Memory, Identity & Security Governance
- **Spec 4.1: Agent Memory Architecture**:
  - **In-Context Working Memory**: Manages current execution state during multi-step subscriber attach / provisioning tasks.
  - **Short-Term Session Memory**: Persists active session logs and health checks in local SQLite (`/var/lib/ella-agent/memory.db`).
  - **Long-Term Topological Memory**: Stores network topology state, PLMN configurations, and past incident remediation outcomes for retrieval during recurring outages.
- **Spec 4.2: Task-Scoped IAM & Least-Privilege Identity**:
  - Assign EC2 IAM Instance Profile with strictly scoped permissions (`CloudWatchLogsFullAccess` restricted to `/aws/ec2/ella-core`, no wildcard `*` IAM permissions).
  - Agent MCP tools enforce local input validation to prevent prompt injection and unauthorized shell command execution.

---

### Requirement 5: Day-2 Observability, Self-Healing & Well-Architected Auditing
- **Spec 5.1: CloudWatch Log & Metric Ingestion**: Ingest container `stdout`/`stderr` and host memory/CPU metrics into CloudWatch Log Group `/aws/ec2/ella-core`.
- **Spec 5.2: Autonomous Self-Healing Loop**:
  - If container memory > 85% or health check fails 3 consecutive times, the Self-Healing Agent automatically triggers `restart_core_service()`.
  - Log incident details, root cause hypotheses, and remediation actions to `/var/lib/ella-agent/memory.db`.
- **Spec 5.3: Automated Well-Architected Auditing**:
  - Periodically verify that AWS Cost Explorer forecast remains $0.00 (Free Tier compliance).
  - Verify Security Group ingress rules contain no unauthorized open ports (e.g., world-open SSH `0.00.0/0`).
- **Spec 5.4: Human-in-the-Loop Escalation Gate**:
  - For destructive or high-impact changes (e.g. tearing down VPC or wiping subscriber DB), the agent halts and creates an approval request (`approval_pending.json`), requiring explicit human confirmation.

---

## 4. Definition of Done & Verification Steps

1. **Deployment Test**:
   - `terraform apply` provisions `t3.micro` instance within AWS Free Tier limits.
2. **Cellular Core Status**:
   - `docker ps` shows `ella-core` healthy and `ogstun` interface initialized (`10.45.0.1/16`).
3. **Agent MCP Server Test**:
   - Running `python3 ella_mcp_server.py --test` verifies all 5 tools (`get_cellular_status`, `provision_subscriber`, etc.) execute cleanly.
4. **Autonomous Self-Healing Verification**:
   - Simulating a container failure (`docker stop ella-core`) triggers the Self-Healing Agent to detect the outage, log the event to memory, and restart the container automatically within 30 seconds.
5. **Well-Architected Audit Test**:
   - The Well-Architected Review Agent generates a compliance report confirming zero cost accrual and verifying secure security group rules.

---

## 5. Execution Instructions for Kiro / AI Coding Agent
To implement this specification in Kiro:
1. Drop `Requirements-v2.md` into your project root directory.
2. Prompt Kiro: *"Implement the full lifecycle specification in Requirements-v2.md step-by-step. Build the Terraform files in `/infra`, the ella-core container stack in `/app`, and the Python MCP Agent server with memory persistence in `/agent`."*

> Implemented. The repository now follows this layout — Terraform + host bootstrap
> in [`infra/`](./infra), the container stack in [`app/`](./app), and the MCP agent
> server (`ella_mcp_server.py`) + self-healing loop + SQLite memory in
> [`agent/`](./agent). See [`README.md`](./README.md) and [`CHANGELOG.md`](./CHANGELOG.md).
