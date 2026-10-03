#!/usr/bin/env python3
"""
Day-2 Observability & Self-Healing Loop — Spec 5.2
==================================================

Continuously polls ella-core health via the MCP tool layer and triggers
automatic remediation:

  * If the container is not running OR the health endpoint fails
    `FAIL_THRESHOLD` consecutive times, invoke restart_core_service().
  * If host available memory drops below `MIN_FREE_MB`, treat as memory
    pressure and restart as well.

Incidents (trigger cause, action, outcome) are logged to the long-term
remediation memory in SQLite and announced via Telegram (if configured).

Run as a long-lived process (see agent/systemd/ella-agent.service), NOT via
the bash tool in this environment.
"""

import logging
import os
import sys
import time
import urllib.request

# Reuse the tool implementations + memory from the MCP server module.
import ella_mcp_server as core

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s", stream=sys.stderr
)
logger = logging.getLogger("ella-self-healing")

POLL_INTERVAL = int(os.getenv("ELLA_POLL_INTERVAL", "15"))     # seconds between polls
FAIL_THRESHOLD = int(os.getenv("ELLA_FAIL_THRESHOLD", "3"))     # consecutive failures before restart
MIN_FREE_MB = int(os.getenv("ELLA_MIN_FREE_MB", "80"))          # memory-pressure floor
HEALTH_URL = os.getenv("ELLA_HEALTH_URL", "http://localhost:8080/healthz")


def health_ok() -> bool:
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=5) as resp:
            return 200 <= resp.status < 300
    except Exception:
        return False


def main() -> int:
    core.init_db()
    logger.info(
        "Self-healing loop started (interval=%ss, threshold=%s, min_free=%sMB, url=%s).",
        POLL_INTERVAL, FAIL_THRESHOLD, MIN_FREE_MB, HEALTH_URL,
    )
    consecutive_failures = 0

    while True:
        status = core._get_cellular_status()
        container_up = status.get("container") == "running"
        endpoint_up = health_ok()
        avail_mb = status.get("available_memory_mb", 0)

        failing = (not container_up) or (not endpoint_up)
        if failing:
            consecutive_failures += 1
            logger.warning(
                "Health check failing (%d/%d): container=%s endpoint_up=%s",
                consecutive_failures, FAIL_THRESHOLD, status.get("container"), endpoint_up,
            )
        else:
            if consecutive_failures:
                logger.info("Health recovered; resetting failure counter.")
            consecutive_failures = 0

        memory_pressure = 0 < avail_mb < MIN_FREE_MB

        if consecutive_failures >= FAIL_THRESHOLD or memory_pressure:
            cause = "memory_pressure" if memory_pressure else "health_check_failure"
            logger.error("Triggering self-heal (cause=%s). Restarting ella-core.", cause)
            core.log_session_event("self_heal_triggered", {"cause": cause, "status": status})
            core._restart_core_service()
            consecutive_failures = 0
            # Give the container time to come back before re-polling.
            time.sleep(max(POLL_INTERVAL, 10))

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        pass
