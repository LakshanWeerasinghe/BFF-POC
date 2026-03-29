#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APIM_DIR="$SCRIPT_DIR/apim/wso2am-4.4.0"
AUTH_SERVICE_DIR="$SCRIPT_DIR/backend/auth_service"
WEBAPP_BACKEND_DIR="$SCRIPT_DIR/backend/webapp_backend"
BFF_DIR="$SCRIPT_DIR/bff_layer"
FRONTEND_DIR="$SCRIPT_DIR/webapp-frontend"

APIM_LOG="$SCRIPT_DIR/apim.log"
AUTH_LOG="$SCRIPT_DIR/auth_service.log"
WEBAPP_LOG="$SCRIPT_DIR/webapp_backend.log"
BFF_LOG="$SCRIPT_DIR/bff_layer.log"
FRONTEND_LOG="$SCRIPT_DIR/frontend.log"

stop_services() {
    echo ""
    echo "Stopping all services..."
    kill "$FRONTEND_PID" "$BFF_PID" "$AUTH_PID" "$WEBAPP_PID" 2>/dev/null
    "$APIM_DIR/bin/api-manager.sh" stop 2>/dev/null
    exit 0
}

trap stop_services INT TERM

# ── 1. APIM ───────────────────────────────────────────────────────────────────
echo "Starting WSO2 APIM 4.4.0..."
"$APIM_DIR/bin/api-manager.sh" start > "$APIM_LOG" 2>&1
echo "  APIM started  (logs: $APIM_LOG)"

# ── 2. Backend services ────────────────────────────────────────────────────────
echo "Starting auth_service on port 9090..."
cd "$AUTH_SERVICE_DIR" && bal run > "$AUTH_LOG" 2>&1 &
AUTH_PID=$!
echo "  auth_service  PID: $AUTH_PID  (logs: $AUTH_LOG)"

echo "Starting webapp_backend on port 8080..."
cd "$WEBAPP_BACKEND_DIR" && bal run > "$WEBAPP_LOG" 2>&1 &
WEBAPP_PID=$!
echo "  webapp_backend PID: $WEBAPP_PID  (logs: $WEBAPP_LOG)"

# ── 3. BFF ────────────────────────────────────────────────────────────────────
echo "Starting BFF layer on port 7001..."
cd "$BFF_DIR" && bal run > "$BFF_LOG" 2>&1 &
BFF_PID=$!
echo "  bff_layer     PID: $BFF_PID  (logs: $BFF_LOG)"

# ── 4. Wait for services to be ready, then start frontend ─────────────────────
echo ""
echo "Waiting 10s for services to initialise..."
sleep 10

echo "Starting frontend on port 3001..."
cd "$FRONTEND_DIR" && npm run dev > "$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!
echo "  frontend      PID: $FRONTEND_PID  (logs: $FRONTEND_LOG)"

# ── 5. Ready ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SonicWave is ready"
echo ""
echo "  UI          →  http://localhost:3001"
echo "  BFF         →  http://localhost:7001/bff"
echo "  APIM Portal →  https://localhost:9443/devportal"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Ctrl+C to stop all services."

wait "$AUTH_PID" "$WEBAPP_PID" "$BFF_PID" "$FRONTEND_PID"
