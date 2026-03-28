#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_NAME="${1:?wrapper name required}"
shift

SCENARIO="${WRAPPER_NAME#stp-}"

usage() {
  cat <<EOF
Usage: bin/$WRAPPER_NAME [command] [args...]

Commands:
  run [args...]  Launch the scenario in screen (default)
  down           Destroy the scenario lab
  status         Show scenario containers and recent artifacts
  info           Show the scenario README
  help           Show this help
EOF
}

cmd="${1:-run}"

case "$cmd" in
  run)
    if [ "$#" -gt 0 ]; then
      shift
    fi
    exec "$ROOT_DIR/bin/stp" run "$SCENARIO" "$@"
    ;;
  down|status|info)
    if [ "$#" -gt 0 ]; then
      shift
    fi
    exec "$ROOT_DIR/bin/stp" "$cmd" "$SCENARIO" "$@"
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
