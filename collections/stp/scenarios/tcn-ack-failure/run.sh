#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-tcn-ack-failure"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/tcn-ack-failure/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/tcn-ack-failure"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/tcn-ack-failure-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/tcn-ack-failure-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/tcn-ack-failure-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying tcn-ack-failure lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the tcn-ack-failure lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying tcn-ack-failure lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Bridging the trunk and access segments"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2
create_relay_bridge "clab-${LAB}-access-relay" br0 eth1 eth2

scenario_log "Waiting for legacy PVST to converge"
sleep 18

scenario_log "Starting capture on relay eth2"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth2 \
  --duration 32 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 4
scenario_log "Suppressing return acknowledgments from the root bridge"
drop_pvst_direction "clab-${LAB}-relay" eth1 eth2

scenario_log "Flapping the downstream access link to trigger TCN generation"
docker exec "clab-${LAB}-access-relay" sh -lc '
  ip link set eth1 down
  sleep 3
  ip link set eth1 up
'

sleep 10
clear_bridge_filters "clab-${LAB}-relay"

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" tcn-ack-failure \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --ack-timeout 1.5

scenario_log "Tcn-ack-failure capture completed successfully"
