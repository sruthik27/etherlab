#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$ROOT_DIR/bin/_stp_scenario_common.sh"

LAB="stp-port-stuck-nonforwarding"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/port-stuck-nonforwarding/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/port-stuck-nonforwarding"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/port-stuck-nonforwarding-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/port-stuck-nonforwarding-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/port-stuck-nonforwarding-$TIMESTAMP-summary.json"

utc_trigger_time() {
  python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime("%H:%M:%S.%f"))
PY
}

cleanup() {
  local rc=$?
  set +e
  scenario_log "Destroying port-stuck-nonforwarding lab"
  ensure_scenario_down "$TOPOLOGY"
  scenario_log_paths "$PCAP_PATH" "$DECODE_PATH" "$SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

ensure_scenario_capture_dir "$CAPTURE_DIR"

scenario_log "Ensuring the port-stuck-nonforwarding lab is down"
ensure_scenario_down "$TOPOLOGY"

scenario_log "Deploying port-stuck-nonforwarding lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

scenario_log "Waiting for STP convergence"
sleep 18

scenario_log "Starting capture on sw2 eth2"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth2 \
  --duration 34 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
TRIGGER_TIME="$(utc_trigger_time)"
scenario_log "Breaking the primary path and suppressing return BPDUs on the backup path"
docker exec "clab-${LAB}-primaryfault" sh -lc '
  ebtables -A FORWARD -i eth1 -o eth2 -j DROP
  ebtables -A FORWARD -i eth2 -o eth1 -j DROP
'
docker exec "clab-${LAB}-backupfault" sh -lc '
  ebtables -A FORWARD -i eth1 -o eth2 -d 01:00:0c:cc:cc:cd -j DROP
'

wait "$CAPTURE_PID"

scenario_log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" port-stuck-nonforwarding \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --trigger-time "$TRIGGER_TIME" \
  --local-bridge-base "300a.aa:bb:cc:00:05:00" \
  --stuck-threshold 8

scenario_log "Port-stuck-nonforwarding capture completed successfully"
