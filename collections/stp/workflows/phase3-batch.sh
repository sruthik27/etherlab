#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

scenario_log "Starting STP phase-3 batch"
ensure_bpdu_injector_image

retry_scenario_once \
  "proposal-agreement-failure" \
  "$(stp_topology_path proposal-agreement-failure)" \
  "$(stp_run_path proposal-agreement-failure)"

retry_scenario_once \
  "dispute-detection" \
  "$(stp_topology_path dispute-detection)" \
  "$(stp_run_path dispute-detection)"

retry_scenario_once \
  "tcn-ack-failure" \
  "$(stp_topology_path tcn-ack-failure)" \
  "$(stp_run_path tcn-ack-failure)"

retry_scenario_once \
  "bpdu-malformation" \
  "$(stp_topology_path bpdu-malformation)" \
  "$(stp_run_path bpdu-malformation)"

retry_scenario_once \
  "bpdu-rate-anomalies" \
  "$(stp_topology_path bpdu-rate-anomalies)" \
  "$(stp_run_path bpdu-rate-anomalies)"

scenario_log "STP phase-3 batch completed successfully"
