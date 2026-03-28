#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAB="stp-slow-reconvergence"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/slow-reconvergence/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/slow-reconvergence"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/slow-reconvergence-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/slow-reconvergence-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/slow-reconvergence-$TIMESTAMP-summary.json"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

cleanup() {
  local rc=$?
  set +e
  log "Destroying slow-reconvergence lab"
  "$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true
  log "Pcap: $PCAP_PATH"
  log "Decoded: $DECODE_PATH"
  log "Summary: $SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

mkdir -p "$CAPTURE_DIR"

log "Ensuring the slow-reconvergence lab is down"
"$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true

log "Deploying slow-reconvergence lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

log "Waiting for STP convergence"
sleep 20

log "Starting capture on sw2 eth2"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth2 \
  --duration 45 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
TRIGGER_TIME="$(python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime('%H:%M:%S.%f'))
PY
)"
log "Suppressing PVST BPDUs across the primary path"
docker exec clab-stp-slow-reconvergence-fault sh -lc \
  "ebtables -A FORWARD -d 01:00:0c:cc:cc:cd -j DROP"

wait "$CAPTURE_PID"

log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" slow-reconvergence \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --trigger-time "$TRIGGER_TIME" \
  --slow-threshold 6

log "Slow-reconvergence capture completed successfully"
