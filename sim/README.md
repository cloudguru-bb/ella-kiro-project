# RAN/UE Simulator (UERANSIM)

Runs a 5G SA **gNodeB** and **UE** using [UERANSIM](https://github.com/aligungr/UERANSIM)
on a dedicated EC2 host, giving you a full **end-to-end** path:

```
UE (uesimtun0) → gNodeB → [private VPC] → ella-core (N2/NGAP + N3/GTP-U) → NAT → Internet
```

## How it's deployed

Terraform (`infra/main.tf`, `var.deploy_simulator = true`) launches a second
Free-Tier instance. Its `cloud-init-sim.yaml`:
1. Installs Docker + the TUN device.
2. Clones this repo and copies `sim/` to `/opt/ella-sim/sim`.
3. Renders `gnb.yaml` / `ue.yaml` from the `.tmpl` files, substituting:
   - `__ELLA_CORE_IP__` → ella-core's **private** VPC IP (passed by Terraform)
   - `__GNB_IP__` → the simulator host's own private IP
4. Starts the **gNodeB** container.

The **UE** is started on demand (it needs the gNodeB registered and the
subscriber provisioned first).

## End-to-end attach test (manual)

SSH to the simulator host, then:

```bash
cd /opt/ella-sim/sim

# 0. Make sure the matching subscriber exists in ella-core first.
#    From the ella-core host, run the agent tool (provisions IMSI 999700000000001):
#      python3 /opt/ella/agent/ella_mcp_server.py --test     # dry-run, or
#      (via an MCP client) call provision_subscriber()

# 1. Confirm the gNodeB registered with ella-core's AMF (NG Setup success)
docker compose logs gnb | grep -i "NG Setup"

# 2. Start the UE and let it register + establish a PDU session
docker compose run --rm ue
#    Look for: "PDU Session establishment is successful" and an assigned IP.

# 3. In another shell, confirm the UE data-plane interface exists
ip addr show uesimtun0        # e.g. 10.45.0.x (from ella-core's UE subnet)

# 4. THE PAYOFF — route traffic through the UE tunnel out to the internet via ella-core
ping -I uesimtun0 -c 4 8.8.8.8
curl --interface uesimtun0 -s https://checkip.amazonaws.com
```

A successful `ping`/`curl` over `uesimtun0` proves the complete control-plane
attach **and** user-plane data path through ella-core's NAT.

## Credential / PLMN alignment (must match or attach fails)

| Field | Value | Set in |
|---|---|---|
| MCC / MNC | 999 / 70 | `gnb.yaml`, `ue.yaml`, ella-core subscriber (provisioned via API) |
| TAC | 1 | `gnb.yaml`, ella-core operator config |
| Slice | SST 1 / SD 000001 | `gnb.yaml`, `ue.yaml`, `provision_subscriber()` |
| IMSI | 999700000000001 | `ue.yaml`, `provision_subscriber()` |
| Ki / OPc | 465B… / E8ED… | `ue.yaml`, `provision_subscriber()` |

Change the subscriber? Update `ue.yaml` to match (or re-render from `ue.yaml.tmpl`).

## Networking (how the two hosts connect)

- Both instances live in the same VPC subnet `10.0.1.0/24` and talk over
  **private IPs** — N2/N3 never traverse the public internet.
- ella-core's security group allows **inbound N2 (SCTP+UDP 38412) and N3
  (UDP 2152) only from the simulator's security group** (`source_security_group_id`),
  not `0.0.0.0/0`. This is the Well-Architected, least-exposure posture.
- The simulator host has only SSH inbound (scoped by `var.ssh_ingress_cidr`) and
  full egress.

## Image & resource notes

- Image: `gradiant/ueransim:3.2.6` (pinned). gNodeB and UE run `network_mode: host`
  so SCTP/GTP-U bind the instance's private IP.
- A single UE attach fits comfortably on a `t3.micro`. This is a **functional**
  lab, not a load generator — for high UE counts use PacketRusher or a larger
  instance.
