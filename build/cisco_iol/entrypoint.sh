#!/bin/bash

set -euo pipefail

echo "Launching IOL with PID ${IOL_PID:-unset}"

if [ -n "${IOL_HOSTNAME:-}" ] && [ "$(hostname)" != "${IOL_HOSTNAME}" ]; then
  hostname "${IOL_HOSTNAME}" || true
fi

# Generate license dynamically based on container identity
python3 /iol/keygen.py > /iol/iourc

# eth0 belongs to the IOS process once IOUYAP is active.
ip addr flush dev eth0 || true
ip -6 addr flush dev eth0 || true

export LD_LIBRARY_PATH=/compat/root/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}

exec /usr/bin/iouyap 513 -q &

sleep 5

max_eth=$(ls /sys/class/net | grep '^eth' | grep -o -E '[0-9]+' | sort -n | tail -1)
num_slots=$(( (max_eth + 4) / 4 ))

exec /iol/iol.bin "${IOL_PID}" -e "${num_slots}" -s 0 -c config.txt -n 1024
