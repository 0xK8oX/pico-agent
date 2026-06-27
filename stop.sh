#!/usr/bin/env bash
# Stop the PicoAgent llama-server.

set -e

PID_FILE="/tmp/picoagent-server.pid"

if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "Stopping PicoAgent server (PID $PID)..."
    kill "$PID"
    sleep 2
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
    fi
    echo "Stopped."
  else
    echo "PID $PID not running."
  fi
  rm -f "$PID_FILE"
else
  pkill -f "llama-server.*Qwythos" 2>/dev/null && echo "Stopped." || echo "No PicoAgent server running."
fi
