#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

scenario_log "Starting STP phase-2 batch"
ensure_bpdu_injector_image

retry_scenario_once \
  "root-misconfiguration" \
  "$(stp_topology_path root-misconfiguration)" \
  "$(stp_run_path root-misconfiguration)"

retry_scenario_once \
  "timer-misconfigurations" \
  "$(stp_topology_path timer-misconfigurations)" \
  "$(stp_run_path timer-misconfigurations)"

retry_scenario_once \
  "path-cost-conflicts" \
  "$(stp_topology_path path-cost-conflicts)" \
  "$(stp_run_path path-cost-conflicts)"

retry_scenario_once \
  "port-stuck-nonforwarding" \
  "$(stp_topology_path port-stuck-nonforwarding)" \
  "$(stp_run_path port-stuck-nonforwarding)"

retry_scenario_once \
  "version-mismatch" \
  "$(stp_topology_path version-mismatch)" \
  "$(stp_run_path version-mismatch)"

retry_scenario_once \
  "bpdu-guard-violations" \
  "$(stp_topology_path bpdu-guard-violations)" \
  "$(stp_run_path bpdu-guard-violations)"

scenario_log "STP phase-2 batch completed successfully"
