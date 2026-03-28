#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STP_COLLECTION_DIR="$ROOT_DIR/collections/stp"
STP_SCENARIOS_DIR="$STP_COLLECTION_DIR/scenarios"
SCREEN_LOG_DIR="${SCREEN_LOG_DIR:-$ROOT_DIR/local/artifacts/logs/screen}"
STP_ARTIFACTS_DIR="${STP_ARTIFACTS_DIR:-$ROOT_DIR/local/artifacts/stp}"
STP_SWITCH_IMAGE="${STP_SWITCH_IMAGE:-vrnetlab/cisco_iol:L2-15.1a}"
STP_BPDU_INJECTOR_IMAGE="${STP_BPDU_INJECTOR_IMAGE:-nicolaka/netshoot:latest}"
CLAB_LABDIR_BASE="${CLAB_LABDIR_BASE:-$ROOT_DIR/local/state/clab}"

mkdir -p "$SCREEN_LOG_DIR" "$STP_ARTIFACTS_DIR" "$CLAB_LABDIR_BASE"

export STP_ARTIFACTS_DIR
export STP_SWITCH_IMAGE
export STP_BPDU_INJECTOR_IMAGE
export CLAB_LABDIR_BASE

scenario_log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

scenario_log_paths() {
  local pcap_path="${1:-}"
  local decode_path="${2:-}"
  local summary_path="${3:-}"

  [ -n "$pcap_path" ] && scenario_log "Pcap: $pcap_path"
  [ -n "$decode_path" ] && scenario_log "Decoded: $decode_path"
  [ -n "$summary_path" ] && scenario_log "Summary: $summary_path"
}

resolve_clab_cmd() {
  if [ -n "${CLAB_CMD:-}" ]; then
    echo "$CLAB_CMD"
  elif command -v containerlab >/dev/null 2>&1; then
    echo "containerlab"
  else
    echo "$ROOT_DIR/bin/clab"
  fi
}

run_clab() {
  local clab_cmd
  clab_cmd="$(resolve_clab_cmd)"
  "$clab_cmd" "$@"
}

stp_scenario_dir() {
  local scenario="$1"
  echo "$STP_SCENARIOS_DIR/$scenario"
}

stp_topology_path() {
  local scenario="$1"
  echo "$(stp_scenario_dir "$scenario")/topology.clab.yml"
}

stp_run_path() {
  local scenario="$1"
  echo "$(stp_scenario_dir "$scenario")/run.sh"
}

stp_readme_path() {
  local scenario="$1"
  echo "$(stp_scenario_dir "$scenario")/README.md"
}

stp_artifact_dir() {
  local scenario="$1"
  echo "$STP_ARTIFACTS_DIR/$scenario"
}

stp_lab_name() {
  local scenario="$1"
  awk '/^name:/{print $2; exit}' "$(stp_topology_path "$scenario")"
}

stp_list_scenarios() {
  find "$STP_SCENARIOS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

ensure_scenario_capture_dir() {
  mkdir -p "$1"
}

ensure_scenario_down() {
  local topology="$1"
  run_clab destroy -t "$topology" >/dev/null 2>&1 || true
}

ensure_bpdu_injector_image() {
  if ! docker image inspect "$STP_BPDU_INJECTOR_IMAGE" >/dev/null 2>&1; then
    scenario_log "Missing injector base image: $STP_BPDU_INJECTOR_IMAGE"
    return 1
  fi
}

install_bpdu_injector_runtime() {
  local container_name="$1"
  docker exec "$container_name" sh -lc 'mkdir -p /opt/injector'
  docker cp "$ROOT_DIR/build/stp_bpdu_injector/bpdu_inject.py" "${container_name}:/opt/injector/bpdu_inject.py"
}

run_bpdu_injector() {
  local container_name="$1"
  shift
  docker exec "$container_name" python3 /opt/injector/bpdu_inject.py "$@"
}

create_relay_bridge() {
  local container_name="$1"
  local bridge_name="${2:-br0}"
  shift 2
  local interfaces=("$@")
  local commands=("ip link add ${bridge_name} type bridge || true" "ip link set ${bridge_name} up")
  local iface
  for iface in "${interfaces[@]}"; do
    commands+=("ip link set ${iface} up")
    commands+=("ip link set ${iface} master ${bridge_name}")
  done
  docker exec "$container_name" sh -lc "$(printf '%s\n' "${commands[@]}")"
}

clear_bridge_filters() {
  local container_name="$1"
  docker exec "$container_name" sh -lc 'ebtables -F || true'
}

drop_pvst_direction() {
  local container_name="$1"
  local src_iface="$2"
  local dst_iface="$3"
  docker exec "$container_name" sh -lc "ebtables -A FORWARD -i ${src_iface} -o ${dst_iface} --dst 01:00:0c:cc:cc:cd -j DROP"
}

retry_scenario_once() {
  local scenario_name="$1"
  local topology="$2"
  local runner="$3"
  shift 3

  local attempt=1
  local max_attempts=2
  while true; do
    scenario_log "Running ${scenario_name} (attempt ${attempt}/${max_attempts})"
    if "$runner" "$@"; then
      scenario_log "${scenario_name} completed successfully"
      return 0
    fi

    local rc=$?
    if [ "$attempt" -ge "$max_attempts" ]; then
      scenario_log "${scenario_name} failed after ${attempt} attempts"
      return "$rc"
    fi

    scenario_log "${scenario_name} failed with exit code ${rc}; retrying once after cleanup"
    ensure_scenario_down "$topology"
    sleep 3
    attempt=$((attempt + 1))
  done
}

destroy_scenario_lab() {
  local topology="$1"
  run_clab destroy -t "$topology"
}

show_scenario_status() {
  local lab_name="$1"
  local artifact_dir="$2"

  docker ps -a --format 'table {{.Names}}\t{{.Status}}' | sed -n "1p;/${lab_name}/p"

  if [ -d "$artifact_dir" ] && [ "$(find "$artifact_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')" -gt 0 ]; then
    echo ""
    echo "Latest artifacts:"
    ls -1t "$artifact_dir" | head -n 6 | sed "s#^#  ${artifact_dir}/#"
  fi
}

maybe_notify_when_done() {
  local session_name="$1"
  if command -v zsh >/dev/null 2>&1 && zsh -ic 'source ~/.zshrc >/dev/null 2>&1; command -v notify_when_done >/dev/null 2>&1' >/dev/null 2>&1; then
    zsh -ic "source ~/.zshrc; notify_when_done '$session_name'" >/dev/null 2>&1 &
  fi
}

launch_scenario_run() {
  local session_prefix="$1"
  local runner="$2"
  shift 2

  if ! command -v screen >/dev/null 2>&1; then
    echo "screen is required for scenario runs" >&2
    exit 1
  fi

  local session_name="${session_prefix}-$(date +%Y%m%d-%H%M%S)"
  local log_path="$SCREEN_LOG_DIR/${session_name}.log"
  local runner_cmd

  screen -wipe >/dev/null 2>&1 || true
  printf -v runner_cmd "%q " "$runner" "$@"

  screen -L -Logfile "$log_path" -dmS "$session_name" /bin/bash -lc "$runner_cmd"
  maybe_notify_when_done "$session_name"

  echo "Started in screen session '$session_name'."
  echo "Log: $log_path"
}
