#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-proposal-agreement-failure"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/proposal-agreement-failure/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/proposal-agreement-failure"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/proposal-agreement-failure-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/proposal-agreement-failure-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/proposal-agreement-failure-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying proposal-agreement-failure lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"
ensure_bpdu_injector_image

scenario_log "Ensuring the proposal-agreement-failure lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying proposal-agreement-failure lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Installing injector runtime and bridging the baseline link"
install_bpdu_injector_runtime "clab-${LAB}-injector"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2 eth3

scenario_log "Waiting for baseline convergence"
sleep 16

scenario_log "Starting capture on relay eth1 for proposal and agreement visibility"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth1 \
  --duration 32 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 4
scenario_log "Forcing a re-proposal while dropping return agreements"
docker exec "clab-${LAB}-relay" sh -lc '
  ip link set eth2 nomaster
  ip link set eth2 up
'
sleep 2
drop_pvst_direction "clab-${LAB}-relay" eth2 eth1
docker exec "clab-${LAB}-relay" sh -lc '
  ip link set eth2 master br0
  ip link set eth2 up
'
sleep 8
clear_bridge_filters "clab-${LAB}-relay"

sleep 5
scenario_log "Injecting an orphan agreement after the proposal window has expired"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 2 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:91:10:00 \
  --root-priority 4106 \
  --root-mac aa:bb:cc:00:01:00 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:91:10:00 \
  --root-path-cost 100 \
  --port-id 0x8001 \
  --message-age 0 \
  --max-age 20 \
  --hello-time 2 \
  --forward-delay 15 \
  --flags 0x7c >/dev/null

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" proposal-agreement-failure \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --agreement-timeout 4 \
  --proposal-window 4

scenario_log "Proposal-agreement-failure capture completed successfully"
