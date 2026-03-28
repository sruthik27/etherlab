#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-version-mismatch"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/version-mismatch/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/version-mismatch"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/version-mismatch-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/version-mismatch-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/version-mismatch-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying version-mismatch lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the version-mismatch lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying version-mismatch lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Waiting for control traffic to stabilize"
sleep 16

scenario_log "Starting capture on sw1 any to observe both rapid and legacy trunks"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw1 any \
  --duration 30 \
  --count 100000 \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
scenario_log "Flapping the mixed-version trunk once"
docker exec "clab-${LAB}-fault" sh -lc '
  ebtables -A FORWARD -i eth1 -o eth2 -j DROP
  ebtables -A FORWARD -i eth2 -o eth1 -j DROP
  sleep 3
  ebtables -F
'

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" version-mismatch \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

scenario_log "Version-mismatch capture completed successfully"
