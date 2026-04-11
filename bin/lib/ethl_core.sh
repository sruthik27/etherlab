#!/bin/bash
#
# Etherlab Core Library
# Shared logic for collection-based networking labs
#

set -euo pipefail

# Path resolution
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
COLLECTIONS_DIR="$ROOT_DIR/collections"
LOCAL_DIR="$ROOT_DIR/local"
ARTIFACTS_BASE_DIR="$LOCAL_DIR/artifacts"
STATE_BASE_DIR="$LOCAL_DIR/state/clab"
SCREEN_LOG_DIR="$ARTIFACTS_BASE_DIR/logs/screen"

# Ensure core local directories exist
mkdir -p "$SCREEN_LOG_DIR" "$STATE_BASE_DIR"

# Global defaults
export CLAB_LABDIR_BASE="$STATE_BASE_DIR"

# --- Logging ---

lab_log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

lab_log_paths() {
  local pcap_path="${1:-}"
  local decode_path="${2:-}"
  local summary_path="${3:-}"

  [ -n "$pcap_path" ] && lab_log "Pcap: $pcap_path"
  [ -n "$decode_path" ] && lab_log "Decoded: $decode_path"
  [ -n "$summary_path" ] && lab_log "Summary: $summary_path"
}

# --- Runtime Resolution ---

resolve_clab_cmd() {
  if [ -n "${CLAB_CMD:-}" ]; then
    echo "$CLAB_CMD"
  elif command -v containerlab >/dev/null 2>&1; then
    echo "containerlab"
  else
    echo "$BIN_DIR/clab"
  fi
}

run_clab() {
  local clab_cmd
  clab_cmd="$(resolve_clab_cmd)"
  "$clab_cmd" "$@"
}

# --- Collection & Scenario Path Resolution ---

get_collection_dir() {
  local col="$1"
  echo "$COLLECTIONS_DIR/$col"
}

get_scenarios_dir() {
  local col="$1"
  echo "$(get_collection_dir "$col")/scenarios"
}

get_scenario_dir() {
  local col="$1"
  local sce="$2"
  echo "$(get_scenarios_dir "$col")/$sce"
}

get_topology_path() {
  local col="$1"
  local sce="$2"
  echo "$(get_scenario_dir "$col" "$sce")/topology.clab.yml"
}

get_run_script_path() {
  local col="$1"
  local sce="$2"
  echo "$(get_scenario_dir "$col" "$sce")/run.sh"
}

get_readme_path() {
  local col="$1"
  local sce="$2"
  echo "$(get_scenario_dir "$col" "$sce")/README.md"
}

get_artifact_dir() {
  local col="$1"
  local sce="$2"
  echo "$ARTIFACTS_BASE_DIR/$col/$sce"
}

get_lab_name() {
  local topo="$1"
  [ -f "$topo" ] && awk '/^name:/{print $2; exit}' "$topo"
}

# --- Container Helpers ---

node_container_name() {
  local lab_name="$1"
  local node_name="$2"
  echo "clab-${lab_name}-${node_name}"
}

# Generic Python-based switch session helper
switch_session() {
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
    # Use preexec_fn for setsid if available, though script -q usually handles it
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

# --- Lab Management ---

launch_run_in_screen() {
  local col="$1"
  local sce="$2"
  local runner
  runner="$(get_run_script_path "$col" "$sce")"
  shift 2

  if ! command -v screen >/dev/null 2>&1; then
    echo "Error: screen is required for scenario runs" >&2
    exit 1
  fi

  local session_name="${col}-${sce}-$(date +%Y%m%d-%H%M%S)"
  local log_path="$SCREEN_LOG_DIR/${session_name}.log"
  local runner_cmd

  screen -wipe >/dev/null 2>&1 || true
  # Format command for screen /bin/bash -lc
  printf -v runner_cmd "%q " "$runner" "$@"

  screen -L -Logfile "$log_path" -dmS "$session_name" /bin/bash -lc "$runner_cmd"

  echo "Started in screen session '$session_name'."
  echo "Log: $log_path"
}

show_status() {
  local col="$1"
  local sce="$2"
  local topo
  topo="$(get_topology_path "$col" "$sce")"
  local lab_name
  lab_name="$(get_lab_name "$topo")"
  local artifact_dir
  artifact_dir="$(get_artifact_dir "$col" "$sce")"

  if [ -z "$lab_name" ]; then
    echo "Lab for $col/$sce is not defined or topology missing."
    return 1
  fi

  docker ps -a --format 'table {{.Names}}\t{{.Status}}' | sed -n "1p;/${lab_name}/p"

  if [ -d "$artifact_dir" ] && [ "$(find "$artifact_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')" -gt 0 ]; then
    echo ""
    echo "Latest artifacts:"
    ls -1t "$artifact_dir" | head -n 6 | sed "s#^#  ${artifact_dir}/#"
  fi
}
