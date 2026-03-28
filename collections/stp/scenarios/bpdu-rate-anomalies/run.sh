#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-bpdu-rate-anomalies"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/bpdu-rate-anomalies/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/bpdu-rate-anomalies"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/bpdu-rate-anomalies-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/bpdu-rate-anomalies-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/bpdu-rate-anomalies-$TIMESTAMP-summary.json"
TARGET_BRIDGE_BASE="200a.aa:bb:cc:95:10:00"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying bpdu-rate-anomalies lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"
ensure_bpdu_injector_image

scenario_log "Ensuring the bpdu-rate-anomalies lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying bpdu-rate-anomalies lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Installing injector runtime and bridging the segment"
install_bpdu_injector_runtime "clab-${LAB}-injector"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2

scenario_log "Waiting for the baseline root to stabilize"
sleep 10

scenario_log "Starting capture on relay eth1"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth1 \
  --duration 28 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 2
scenario_log "Injecting bursty and jittery BPDU timing from a synthetic bridge"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 3 \
  --interval 0.25 \
  --vlan 10 \
  --src-mac aa:bb:cc:95:10:00 \
  --root-priority 4106 \
  --root-mac aa:bb:cc:00:01:00 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:95:10:00 \
  --root-path-cost 100 \
  --flags 0x1e >/dev/null

sleep 2.5
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 2 \
  --interval 3.2 \
  --vlan 10 \
  --src-mac aa:bb:cc:95:10:00 \
  --root-priority 4106 \
  --root-mac aa:bb:cc:00:01:00 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:95:10:00 \
  --root-path-cost 100 \
  --flags 0x1e >/dev/null

sleep 0.7
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 4 \
  --interval 0.35 \
  --vlan 10 \
  --src-mac aa:bb:cc:95:10:00 \
  --root-priority 4106 \
  --root-mac aa:bb:cc:00:01:00 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:95:10:00 \
  --root-path-cost 100 \
  --flags 0x1e >/dev/null

sleep 4
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 2 \
  --interval 1.7 \
  --vlan 10 \
  --src-mac aa:bb:cc:95:10:00 \
  --root-priority 4106 \
  --root-mac aa:bb:cc:00:01:00 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:95:10:00 \
  --root-path-cost 100 \
  --flags 0x1e >/dev/null

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" bpdu-rate-anomalies \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --bridge-base "$TARGET_BRIDGE_BASE" \
  --hello-time 2 \
  --jitter-threshold 0.75 \
  --mean-deviation-threshold 0.5

scenario_log "Bpdu-rate-anomalies capture completed successfully"
