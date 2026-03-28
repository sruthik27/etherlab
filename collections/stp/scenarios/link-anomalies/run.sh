#!/bin/bash

set -euo pipefail

MODE="${1:-unidirectional}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAB="stp-link-anomalies"
TOPOLOGY="$ROOT_DIR/collections/stp/scenarios/link-anomalies/topology.clab.yml"
CAPTURE_DIR="$ROOT_DIR/local/artifacts/stp/link-anomalies"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PCAP_PATH="$CAPTURE_DIR/link-anomalies-$MODE-$TIMESTAMP.pcap"
DECODE_PATH="$CAPTURE_DIR/link-anomalies-$MODE-$TIMESTAMP.txt"
SUMMARY_PATH="$CAPTURE_DIR/link-anomalies-$MODE-$TIMESTAMP-summary.json"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

cleanup() {
  local rc=$?
  set +e
  log "Destroying link-anomalies lab"
  "$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true
  log "Pcap: $PCAP_PATH"
  log "Decoded: $DECODE_PATH"
  log "Summary: $SUMMARY_PATH"
  exit "$rc"
}

trap cleanup EXIT

mkdir -p "$CAPTURE_DIR"

log "Ensuring the link-anomalies lab is down"
"$ROOT_DIR/bin/clab" destroy -t "$TOPOLOGY" >/dev/null 2>&1 || true

log "Deploying link-anomalies lab"
"$ROOT_DIR/bin/clab" deploy -t "$TOPOLOGY"

log "Waiting for STP convergence"
sleep 18

case "$MODE" in
  unidirectional)
    log "Starting capture on sw2 eth2"
    "$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth2 \
      --duration 35 \
      --count 100000 \
      --filter 'ether dst 01:00:0c:cc:cc:cd' \
      --output "$PCAP_PATH" &
    CAPTURE_PID=$!

    sleep 5
    log "Dropping BPDUs only from sw1 toward sw2 on the affected link"
    docker exec clab-stp-link-anomalies-fault sh -lc \
      "ebtables -A FORWARD -i eth1 -o eth2 -d 01:00:0c:cc:cc:cd -j DROP"
    ;;
  self-loop)
    log "Starting capture on sw2 eth4"
    "$ROOT_DIR/bin/clab-capture" capture "$LAB" sw2 eth4 \
      --duration 30 \
      --count 100000 \
      --filter 'ether dst 01:00:0c:cc:cc:cd' \
      --output "$PCAP_PATH" &
    CAPTURE_PID=$!

    sleep 5
    log "Bridging sw2 Ethernet1/0 and Ethernet1/1 to reflect BPDUs"
    docker exec clab-stp-link-anomalies-fault sh -lc '
      ip link add br1 type bridge
      ip link set br1 up
      ip link set eth3 master br1
      ip link set eth4 master br1
    '
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Expected: unidirectional or self-loop" >&2
    exit 1
    ;;
esac

wait "$CAPTURE_PID"

log "Decoding capture"
"$ROOT_DIR/bin/clab-capture" read "$PCAP_PATH" > "$DECODE_PATH"

python3 "$ROOT_DIR/scripts/stp_summary.py" link-anomalies \
  --pcap "$PCAP_PATH" \
  --decoded "$DECODE_PATH" \
  --summary "$SUMMARY_PATH" \
  --mode "$MODE"

log "Link-anomalies capture completed successfully"
