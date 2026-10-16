#!/bin/sh
export PATH="$PATH:/root/.local/bin:/usr/local/bin"
echo "[garza] starting raft-computer (reconnecting loop)..."
while true; do
  raft-computer start --foreground 2>&1 || true
  echo "[garza] raft-computer exited; retrying in 10s"
  sleep 10
done
