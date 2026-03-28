#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-bpdu-guard-violations"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/bpdu-guard-violations/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/bpdu-guard-violations"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/bpdu-guard-violations-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/bpdu-guard-violations-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/bpdu-guard-violations-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying bpdu-guard-violations lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the bpdu-guard-violations lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying bpdu-guard-violations lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Waiting for the guarded access port baseline"
sleep 10

scenario_log "Starting capture on relay any so the offending BPDU is visible even if the guarded port drops"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay any \
  --duration 25 \
  --count 100000 \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 4
scenario_log "Connecting the rogue-switch relay"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" bpdu-guard-violations \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --local-bridge-base "100a.aa:bb:cc:00:02:00" \
  --silence-threshold 4

scenario_log "BPDU-guard-violations capture completed successfully"
