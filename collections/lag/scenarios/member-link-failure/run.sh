#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_lag_scenario_common.sh"

SCENARIO="member-link-failure"
LAB_NAME="$(lag_lab_name "$SCENARIO")"
TOPOLOGY="$(lag_topology_path "$SCENARIO")"
CAPTURE_DIR="$(lag_artifact_dir "$SCENARIO")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/member-link-failure-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/member-link-failure-$TIMESTAMP.txt"
BEFORE_SW1="$CAPTURE_DIR/sw1-before-$TIMESTAMP.txt"
BEFORE_SW2="$CAPTURE_DIR/sw2-before-$TIMESTAMP.txt"
AFTER_SW1="$CAPTURE_DIR/sw1-after-$TIMESTAMP.txt"
AFTER_SW2="$CAPTURE_DIR/sw2-after-$TIMESTAMP.txt"
HOST_CHECKS="$CAPTURE_DIR/hosts-$TIMESTAMP.txt"

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying member-link-failure lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH"
  scenario_log "Artifacts:"
  scenario_log "  $BEFORE_SW1"
  scenario_log "  $BEFORE_SW2"
  scenario_log "  $AFTER_SW1"
  scenario_log "  $AFTER_SW2"
  scenario_log "  $HOST_CHECKS"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the member-link-failure lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying the member-link-failure lab"
run_clab deploy -t "$TOPOLOGY"

lag_wait_for_convergence 30

scenario_log "Starting capture on sw1 eth2 to observe the surviving member"
"$ROOT_DIR/bin/clab-capture" capture "$LAB_NAME" sw1 eth2 \
  --duration 24 \
  --count 15000 \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 2

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw1)" "$BEFORE_SW1" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw2)" "$BEFORE_SW2" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

: > "$HOST_CHECKS"
capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.10.10.12"
capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.20.20.12"

scenario_log "Shutting Ethernet0/1 on both switches to simulate a lost member link"
lag_switch_session "$(lag_node_container "$LAB_NAME" sw1)" \
  "configure terminal" \
  "interface Ethernet0/1" \
  "shutdown" \
  "end" \
  >/dev/null
lag_switch_session "$(lag_node_container "$LAB_NAME" sw2)" \
  "configure terminal" \
  "interface Ethernet0/1" \
  "shutdown" \
  "end" \
  >/dev/null

sleep 8

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw1)" "$AFTER_SW1" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

capture_switch_commands "$(lag_node_container "$LAB_NAME" sw2)" "$AFTER_SW2" \
  "show etherchannel summary" \
  "show lacp neighbor" \
  "show interfaces trunk"

capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.10.10.12"
capture_ping_check "$(lag_node_container "$LAB_NAME" h1)" "$HOST_CHECKS" "10.20.20.12"

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

grep -q "Po1(SU)" "$AFTER_SW1" || { scenario_log "Port-channel did not stay up on sw1"; exit 1; }
grep -q "Po1(SU)" "$AFTER_SW2" || { scenario_log "Port-channel did not stay up on sw2"; exit 1; }
grep -q "Et0/1(D)" "$AFTER_SW1" || { scenario_log "Failed member not marked down on sw1"; exit 1; }
grep -q "Et0/2(P)" "$AFTER_SW1" || { scenario_log "Surviving member not bundled on sw1"; exit 1; }
grep -q "Et0/1(D)" "$AFTER_SW2" || { scenario_log "Failed member not marked down on sw2"; exit 1; }
grep -q "Et0/2(P)" "$AFTER_SW2" || { scenario_log "Surviving member not bundled on sw2"; exit 1; }
[ -s "$PCAP_PATH" ] || { scenario_log "Member-link-failure pcap was not written"; exit 1; }
assert_decoded_pcap_has_packets "$DECODE_PATH" || { scenario_log "Member-link-failure pcap decode did not contain packets"; exit 1; }

scenario_log "Member-link-failure capture completed successfully"
