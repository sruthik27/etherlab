#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-root-misconfiguration"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/root-misconfiguration/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/root-misconfiguration"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/root-misconfiguration-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/root-misconfiguration-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/root-misconfiguration-$TIMESTAMP-summary.json"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying root-misconfiguration lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"
ensure_bpdu_injector_image

scenario_log "Ensuring the root-misconfiguration lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying root-misconfiguration lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Waiting for the stable domain to converge"
sleep 18

scenario_log "Starting capture on relay eth1 to capture the crafted root claim on the switch-facing segment"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" relay eth1 \
  --duration 35 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
scenario_log "Connecting the injector relay"
create_relay_bridge "clab-${LAB}-relay" br0 eth1 eth2

sleep 2
scenario_log "Copying the injector runtime into the injector node"
docker exec "clab-${LAB}-injector" sh -lc 'mkdir -p /opt/injector'
docker cp "$ROOT_DIR/build/stp_bpdu_injector/bpdu_inject.py" "clab-${LAB}-injector:/opt/injector/bpdu_inject.py"

sleep 1
scenario_log "Injecting superior BPDUs with a non-standard root priority"
docker exec "clab-${LAB}-injector" python3 /opt/injector/bpdu_inject.py send \
  --iface eth1 \
  --count 12 \
  --interval 1 \
  --vlan 10 \
  --src-mac aa:bb:cc:90:10:00 \
  --root-priority 25010 \
  --root-mac aa:bb:cc:90:10:00 \
  --bridge-priority 25010 \
  --bridge-mac aa:bb:cc:90:10:00 \
  --root-path-cost 0 \
  --port-id 0x8001 \
  --message-age 0 \
  --max-age 20 \
  --hello-time 2 \
  --forward-delay 15 \
  --flags 0x3c >/dev/null

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" root-misconfiguration \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

scenario_log "Root-misconfiguration capture completed successfully"
