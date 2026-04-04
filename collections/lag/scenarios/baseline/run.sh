#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_lag_scenario_common.sh"

SCENARIO="baseline"
LAB_NAME="$(lag_lab_name "$SCENARIO")"
TOPOLOGY="$(lag_topology_path "$SCENARIO")"
CAPTURE_DIR="$(lag_artifact_dir "$SCENARIO")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/baseline-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/baseline-$TIMESTAMP.txt"
SW1_STATE="$CAPTURE_DIR/sw1-$TIMESTAMP.txt"
SW2_STATE="$CAPTURE_DIR/sw2-$TIMESTAMP.txt"
HOST_CHECKS="$CAPTURE_DIR/hosts-$TIMESTAMP.txt"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying baseline lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH"
  scenario_log "Artifacts:"
  scenario_log "  $SW1_STATE"
  scenario_log "  $SW2_STATE"
  scenario_log "  $HOST_CHECKS"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the baseline lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying the baseline LAG lab"
run_clab deploy -t "$TOPOLOGY"

lag_wait_for_convergence 30

scenario_log "Starting capture on sw1 eth1 for baseline control traffic"
"$ROOT_DIR/bin/clab-capture" capture "$LAB_NAME" sw1 eth1 \
  --duration 18 \
  --count 10000 \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 2

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw1)" "$SW1_STATE" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw2)" "$SW2_STATE" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

: > "$HOST_CHECKS"
capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.10.10.12"
capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.20.20.12"

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

grep -q "Po1(SU)" "$SW1_STATE" || { scenario_log "Healthy Port-channel state missing on sw1"; exit 1; }
grep -q "Po1(SU)" "$SW2_STATE" || { scenario_log "Healthy Port-channel state missing on sw2"; exit 1; }
[ -s "$PCAP_PATH" ] || { scenario_log "Baseline pcap was not written"; exit 1; }
assert_decoded_pcap_has_packets "$DECODE_PATH" || { scenario_log "Baseline pcap decode did not contain packets"; exit 1; }
grep -q "10.10.10.12" "$HOST_CHECKS" || { scenario_log "VLAN 10 ping result missing"; exit 1; }
grep -q "10.20.20.12" "$HOST_CHECKS" || { scenario_log "VLAN 20 ping result missing"; exit 1; }

scenario_log "Baseline LAG capture completed successfully"
