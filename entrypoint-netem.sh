#!/bin/sh
# Verzögerung und Verlust auf eth0 (nur ausgehend). Beide Container zusammen: RTT = 2*DELAY_MS, Verlust je Richtung LOSS_PCT.
set -e
tc qdisc replace dev eth0 root netem delay "${DELAY_MS:-50}ms" loss "${LOSS_PCT:-1}%"
# Optional: initiales Congestion Window für TCP (Segmente), z. B. INITCWND=32
if [ -n "${INITCWND:-}" ]; then
  ip route show dev eth0 | while read -r r; do ip route change $r dev eth0 initcwnd "$INITCWND"; done
fi
exec "$@"
