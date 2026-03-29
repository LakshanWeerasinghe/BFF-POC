#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTH_SERVICE_DIR="$SCRIPT_DIR/backend/auth_service"
WEBAPP_BACKEND_DIR="$SCRIPT_DIR/backend/webapp_backend"

AUTH_LOG="/tmp/auth_service.log"
WEBAPP_LOG="/tmp/webapp_backend.log"

stop_services() {
    echo "Stopping backend services..."
    kill "$AUTH_PID" "$WEBAPP_PID" 2>/dev/null
    exit 0
}

trap stop_services INT TERM

echo "Starting auth_service on port 9090..."
cd "$AUTH_SERVICE_DIR" && bal run > "$AUTH_LOG" 2>&1 &
AUTH_PID=$!

echo "Starting webapp_backend on port 8080..."
cd "$WEBAPP_BACKEND_DIR" && bal run > "$WEBAPP_LOG" 2>&1 &
WEBAPP_PID=$!

echo "auth_service  PID: $AUTH_PID  (logs: $AUTH_LOG)"
echo "webapp_backend PID: $WEBAPP_PID  (logs: $WEBAPP_LOG)"
echo ""
echo "Press Ctrl+C to stop both services."

wait "$AUTH_PID" "$WEBAPP_PID"
