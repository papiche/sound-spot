#!/bin/bash
# wait-pw-socket.sh — Attend que le socket PipeWire-Pulse soit disponible.
# Utilisé en ExecStartPre par soundspot-client.service (maître).
# Hérite de XDG_RUNTIME_DIR depuis le service systemd.

SOCKET="${XDG_RUNTIME_DIR:-/run/user/1000}/pulse/native"
TIMEOUT=60
elapsed=0

while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if [ -S "$SOCKET" ]; then
        echo "wait-pw-socket: socket PipeWire-Pulse présent après ${elapsed}s"
        exit 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

echo "wait-pw-socket: socket PipeWire-Pulse absent après ${TIMEOUT}s" >&2
exit 1
