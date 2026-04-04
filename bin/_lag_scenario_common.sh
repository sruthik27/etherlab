#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAG_COLLECTION_DIR="$ROOT_DIR/collections/lag"
LAG_SCENARIOS_DIR="$LAG_COLLECTION_DIR/scenarios"
SCREEN_LOG_DIR="${SCREEN_LOG_DIR:-$ROOT_DIR/local/artifacts/logs/screen}"
LAG_ARTIFACTS_DIR="${LAG_ARTIFACTS_DIR:-$ROOT_DIR/local/artifacts/lag}"
LAG_SWITCH_IMAGE="${LAG_SWITCH_IMAGE:-vrnetlab/cisco_iol:L2-15.1a}"
CLAB_LABDIR_BASE="${CLAB_LABDIR_BASE:-$ROOT_DIR/local/state/clab}"

mkdir -p "$SCREEN_LOG_DIR" "$LAG_ARTIFACTS_DIR" "$CLAB_LABDIR_BASE"

export LAG_ARTIFACTS_DIR
export LAG_SWITCH_IMAGE
export CLAB_LABDIR_BASE

scenario_log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

scenario_log_paths() {
  local pcap_path="${1:-}"
  local decode_path="${2:-}"

  [ -n "$pcap_path" ] && scenario_log "Pcap: $pcap_path"
  [ -n "$decode_path" ] && scenario_log "Decoded: $decode_path"
}

assert_decoded_pcap_has_packets() {
  local decode_path="$1"
  grep -Eq '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.' "$decode_path"
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

lag_scenario_dir() {
  local scenario="$1"
  echo "$LAG_SCENARIOS_DIR/$scenario"
}

lag_topology_path() {
  local scenario="$1"
  echo "$(lag_scenario_dir "$scenario")/topology.clab.yml"
}

lag_run_path() {
  local scenario="$1"
  echo "$(lag_scenario_dir "$scenario")/run.sh"
}

lag_readme_path() {
  local scenario="$1"
  echo "$(lag_scenario_dir "$scenario")/README.md"
}

lag_artifact_dir() {
  local scenario="$1"
  echo "$LAG_ARTIFACTS_DIR/$scenario"
}

lag_lab_name() {
  local scenario="$1"
  awk '/^name:/{print $2; exit}' "$(lag_topology_path "$scenario")"
}

lag_list_scenarios() {
  find "$LAG_SCENARIOS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

ensure_scenario_capture_dir() {
  mkdir -p "$1"
}

ensure_scenario_down() {
  local topology="$1"
  run_clab destroy -t "$topology" >/dev/null 2>&1 || true
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

lag_node_container() {
  local lab_name="$1"
  local node_name="$2"
  echo "clab-${lab_name}-${node_name}"
}

lag_wait_for_convergence() {
  local seconds="${1:-18}"
  scenario_log "Waiting ${seconds}s for EtherChannel state to settle"
  sleep "$seconds"
}

lag_switch_session() {
  local container_name="$1"
  shift

  python3 - "$container_name" "$@" <<'PY'
import re
import subprocess
import sys
import time

container = sys.argv[1]
commands = sys.argv[2:]
payload = ("\rterminal length 0\r" + "".join(f"{command}\r" for command in commands)).encode()
proc = subprocess.Popen(
    ["script", "-q", "/dev/null", "docker", "attach", container],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)

captured = b""
try:
    time.sleep(0.4)
    if proc.stdin:
        proc.stdin.write(payload)
        proc.stdin.flush()
    try:
        captured, _ = proc.communicate(timeout=3.0)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            captured, _ = proc.communicate(timeout=1.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            captured, _ = proc.communicate()
finally:
    if proc.poll() is None:
        proc.kill()
        captured, _ = proc.communicate()

text = captured.decode("utf-8", "ignore")
text = text.replace("\r\n", "\n").replace("\r", "\n")
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
text = text.replace("\x08", "")
text = "".join(ch for ch in text if ch in "\n\t" or 32 <= ord(ch) < 127)
text = text.strip()
if text:
    print(text)
PY
}

lag_switch_cli() {
  local container_name="$1"
  local command="$2"
  lag_switch_session "$container_name" "$command"
}

capture_switch_command() {
  local container_name="$1"
  local output_path="$2"
  local command="$3"

  {
    printf '=== %s ===\n' "$command"
    lag_switch_cli "$container_name" "$command"
    printf '\n'
  } >> "$output_path"
}

capture_switch_commands() {
  local container_name="$1"
  local output_path="$2"
  shift 2

  : > "$output_path"
  local command
  for command in "$@"; do
    capture_switch_command "$container_name" "$output_path" "$command"
  done
}

capture_host_command() {
  local container_name="$1"
  local output_path="$2"
  local label="$3"
  shift 3
  local rc=0

  {
    printf '=== %s ===\n' "$label"
    if docker exec "$container_name" "$@"; then
      rc=0
    else
      rc=$?
      printf '[exit-code=%s]\n' "$rc"
    fi
    printf '\n'
  } >> "$output_path"

  return "$rc"
}

capture_ping_check() {
  local container_name="$1"
  local output_path="$2"
  local target="$3"

  capture_host_command "$container_name" "$output_path" "ping $target" ping -c 3 -W 1 "$target"
}
