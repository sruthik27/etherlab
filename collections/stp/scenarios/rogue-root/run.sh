#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAB="stp-rogue-root"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/rogue-root/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/rogue-root"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/rogue-root-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/rogue-root-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/rogue-root-$TIMESTAMP-summary.json"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

cleanup() {
  local rc=$?
  set +e
  log "Destroying rogue-root lab"
  "$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true
  log "Pcap: $PCAP_PATH"
  log "Decoded: $DECODE_PATH"
  log "Summary: $SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

mkdir -p "$CAPTURE_DIR"

log "Ensuring the rogue-root lab is down"
"$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true

log "Deploying rogue-root lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

log "Waiting for the stable domain to converge"
sleep 15

log "Starting capture on sw3 eth3"
"$ROOT_DIR/bin/clab-capture" capture "$LAB" sw3 eth3 \
  --duration 35 \
  --count 100000 \
  --filter 'ether dst 01:00:0c:cc:cc:cd' \
  --output "$PCAP_PATH" &
CAPTURE_PID=$!

sleep 5
log "Connecting the rogue-root relay"
docker exec clab-stp-rogue-root-relay sh -lc '
  ip link add br0 type bridge
  ip link set eth1 up
  ip link set eth2 up
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
'

wait "$CAPTURE_PID"

log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" rogue-root \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH"

log "Rogue-root capture completed successfully"
