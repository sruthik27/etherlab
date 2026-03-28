#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

SCENARIO="baseline"
TOPOLOGY="$(stp_topology_path "$SCENARIO")"

scenario_log "Ensuring the baseline lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying the baseline STP lab"
run_clab deploy -t "$TOPOLOGY"

scenario_log "Baseline lab is ready"
scenario_log "Use bin/cisco-iol-stp console sw1|sw2 for switch access"
scenario_log "Use bin/stp graph baseline to inspect the topology"
