#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAB="stp-bpdu-silence"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/bpdu-silence/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/bpdu-silence"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/bpdu-silence-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/bpdu-silence-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/bpdu-silence-$TIMESTAMP-summary.json"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

cleanup() {
  local rc=$?
  set +e
  log "Destroying BPDU-silence lab"
  "$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true
  log "Pcap: $PCAP_PATH"
  log "Decoded: $DECODE_PATH"
  log "Summary: $SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

mkdir -p "$CAPTURE_DIR"

log "Ensuring the BPDU-silence lab is down"
"$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true

log "Deploying BPDU-silence lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

log "Waiting for STP convergence"
sleep 12

log "Starting capture on sw2 eth1"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth1 \
  --duration 50 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
log "Pausing the root switch long enough to exceed max-age"
docker pause clab-stp-bpdu-silence-sw1
sleep 25
log "Unpausing the root switch"
docker unpause clab-stp-bpdu-silence-sw1
sleep 5

wait "$CAPTURE_PID"

log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" bpdu-silence \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --gap-threshold 20

log "BPDU-silence capture completed successfully"
