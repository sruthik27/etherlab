#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-dispute-detection"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/dispute-detection/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/dispute-detection"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/dispute-detection-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/dispute-detection-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/dispute-detection-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying dispute-detection lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"
ensure_bpdu_injector_image

scenario_log "Ensuring the dispute-detection lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying dispute-detection lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Installing injector runtime and bridging the forwarding segment"
install_bpdu_injector_runtime "clab-${LAB}-injector"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2 eth3

scenario_log "Waiting for the forwarding segment to converge"
sleep 16

scenario_log "Starting capture on relay eth1"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth1 \
  --duration 24 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 4
scenario_log "Injecting inferior designated BPDUs on the forwarding segment"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 6 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:92:10:00 \
  --root-priority 12298 \
  --root-mac aa:bb:cc:92:10:00 \
  --bridge-priority 12298 \
  --bridge-mac aa:bb:cc:92:10:00 \
  --root-path-cost 0 \
  --port-id 0x8001 \
  --message-age 0 \
  --max-age 20 \
  --hello-time 2 \
  --forward-delay 15 \
  --flags 0x1e >/dev/null

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" dispute-detection \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

scenario_log "Dispute-detection capture completed successfully"
