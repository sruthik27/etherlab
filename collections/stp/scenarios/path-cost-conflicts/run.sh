#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-path-cost-conflicts"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/path-cost-conflicts/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/path-cost-conflicts"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/path-cost-conflicts-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/path-cost-conflicts-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/path-cost-conflicts-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying path-cost-conflicts lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the path-cost-conflicts lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying path-cost-conflicts lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Waiting for STP convergence"
sleep 18

scenario_log "Capturing on sw4 any to observe both candidate uplinks"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw4 any \
  --duration 24 \
  --count 100000 \
  --output "$PCAP_PATH"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" path-cost-conflicts \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

scenario_log "Path-cost-conflicts capture completed successfully"
