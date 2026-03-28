#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAB="stp-root-instability"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/root-instability/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/root-instability"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/root-instability-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/root-instability-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/root-instability-$TIMESTAMP-summary.json"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

cleanup() {
  local rc=$?
  set +e
  log "Destroying root-instability lab"
  "$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true
  log "Pcap: $PCAP_PATH"
  log "Decoded: $DECODE_PATH"
  log "Summary: $SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

mkdir -p "$CAPTURE_DIR"

log "Ensuring the root-instability lab is down"
"$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true

log "Deploying root-instability lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

log "Waiting for STP convergence"
sleep 15

log "Starting capture on sw2 eth2"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth2 \
  --duration 60 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 4
log "Pausing sw1 to force a backup-root election"
docker pause clab-stp-root-instability-sw1
sleep 10
log "Unpausing sw1"
docker unpause clab-stp-root-instability-sw1
sleep 8
log "Pausing sw1 again for a second transient election"
docker pause clab-stp-root-instability-sw1
sleep 10
log "Unpausing sw1"
docker unpause clab-stp-root-instability-sw1
sleep 8

wait "$CAPTURE_PID"

log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" root-instability \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

log "Root-instability capture completed successfully"
