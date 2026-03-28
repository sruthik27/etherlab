#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-bpdu-malformation"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/bpdu-malformation/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/bpdu-malformation"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/bpdu-malformation-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/bpdu-malformation-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/bpdu-malformation-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying bpdu-malformation lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"
ensure_bpdu_injector_image

scenario_log "Ensuring the bpdu-malformation lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying bpdu-malformation lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Installing injector runtime and bridging the segment"
install_bpdu_injector_runtime "clab-${LAB}-injector"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2

scenario_log "Waiting for the baseline root to stabilize"
sleep 10

scenario_log "Starting capture on relay eth1"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth1 \
  --duration 20 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 2
scenario_log "Injecting an unknown protocol version BPDU"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 1 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:94:10:10 \
  --root-priority 8202 \
  --root-mac aa:bb:cc:94:10:10 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:94:10:10 \
  --protocol-version 9 \
  --bpdu-type 2 \
  --flags 0x1e >/dev/null

sleep 1
scenario_log "Injecting an invalid BPDU type"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 1 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:94:10:20 \
  --root-priority 8202 \
  --root-mac aa:bb:cc:94:10:20 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:94:10:20 \
  --protocol-version 2 \
  --bpdu-type 0x7f \
  --flags 0x1e >/dev/null

sleep 1
scenario_log "Injecting out-of-range timers"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 1 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:94:10:30 \
  --root-priority 8202 \
  --root-mac aa:bb:cc:94:10:30 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:94:10:30 \
  --protocol-version 2 \
  --bpdu-type 2 \
  --hello-time 12 \
  --max-age 2 \
  --forward-delay 1 \
  --flags 0x1e >/dev/null

sleep 1
scenario_log "Injecting a truncated malformed BPDU"
run_bpdu_injector "clab-${LAB}-injector" send \
  --iface eth1 \
  --count 1 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:94:10:40 \
  --root-priority 8202 \
  --root-mac aa:bb:cc:94:10:40 \
  --bridge-priority 8202 \
  --bridge-mac aa:bb:cc:94:10:40 \
  --protocol-version 2 \
  --bpdu-type 2 \
  --truncate-bytes 18 \
  --flags 0x1e >/dev/null

wait "$CAPTURE_PID"

scenario_log "Decoding capture with raw hex output"
docker run --rm \
  -v "$(dirname "$PCAP_PATH"):/captures" \
  nicolaka/netshoot:latest \
  sh -lc "tcpdump -nn -e -vvv -XX -r /captures/$(basename "$PCAP_PATH")" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" bpdu-malformation \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

scenario_log "Bpdu-malformation capture completed successfully"
