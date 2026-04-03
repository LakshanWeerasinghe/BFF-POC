#!/bin/bash
#
# setup.sh — SonicWave complete setup and startup
#
# First run — provide a local pack or let the script download one:
#   ./setup.sh --pack /path/to/wso2am-4.4.0.zip   # use a local zip
#   ./setup.sh                                      # auto-download from WSO2 VPN
#
# Subsequent runs (APIM already provisioned):
#   ./setup.sh
#
# What it does on first run:
#   • Resolves the APIM pack: --pack flag → existing extracted dir → VPN download
#   • Extracts the pack, patches CORS config in deployment.toml
#   • Starts APIM and provisions APIs, API Product, application, and OAuth keys via REST
#   • Writes generated credentials into bff_layer/Config.toml
#   • Continues to start all services without restarting APIM
#
# What it does on subsequent runs:
#   • Starts APIM normally (skips provisioning)
#   • Starts auth_service, webapp_backend, BFF, and frontend
#
# Requirements: curl, python3, unzip, bal, npm

# ─── colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ─── parse arguments ──────────────────────────────────────────────────────────
PACK_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pack) PACK_PATH="$2"; shift 2 ;;
    *) die "Unknown argument: $1\nUsage: $0 [--pack /path/to/wso2am-*.zip]" ;;
  esac
done

# ─── paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APIM_DOWNLOAD_URL="https://atuwa.private.wso2.com/WSO2-Products/api-manager/4.0.0/APIM/wso2am-4.0.0.zip"
APIM_DOWNLOAD_DEST="$SCRIPT_DIR/apim/wso2am-download.zip"

# ─── resolve APIM pack ────────────────────────────────────────────────────────
# Priority: --pack flag → existing extracted directory → download from WSO2 VPN

# 1. --pack flag was given
if [[ -n "$PACK_PATH" && ! -f "$PACK_PATH" ]]; then
  die "Pack not found: $PACK_PATH"
fi

# 2. No --pack — look for an existing extracted directory
if [[ -z "$PACK_PATH" ]]; then
  # Prefer a directory already provisioned
  FOUND=$(for d in "$SCRIPT_DIR/apim"/*/; do
    v=$(basename "$d")
    [[ "$v" == "auth-handler" ]] && continue
    [[ -f "$d/.sonicwave_configured" ]] && echo "$d" && break
  done || true)
  # Fall back to any directory with a deployment.toml
  if [[ -z "$FOUND" ]]; then
    FOUND=$(for d in "$SCRIPT_DIR/apim"/*/; do
      v=$(basename "$d")
      [[ "$v" == "auth-handler" ]] && continue
      [[ -f "$d/repository/conf/deployment.toml" ]] && echo "$d" && break
    done || true)
  fi
  if [[ -n "$FOUND" ]]; then
    PACK_PATH=""   # already extracted — skip extraction below
  else
    # 3. Nothing found — download from WSO2 internal mirror
    echo ""
    warn "No APIM pack or extracted directory found."
    echo ""
    echo "  The pack will be downloaded from the WSO2 internal mirror:"
    echo "  $APIM_DOWNLOAD_URL"
    echo ""
    echo "  ⚠  You must be connected to the WSO2 VPN before continuing."
    echo "     If you are not on VPN the download will fail."
    echo ""
    read -r -p "  Press Enter to continue or Ctrl+C to abort... "
    echo ""
    info "Downloading APIM pack..."
    mkdir -p "$SCRIPT_DIR/apim"
    if ! curl -L --fail --progress-bar -o "$APIM_DOWNLOAD_DEST" "$APIM_DOWNLOAD_URL"; then
      rm -f "$APIM_DOWNLOAD_DEST"
      die "Download failed. Check your VPN connection and try again."
    fi
    ok "Download complete."
    PACK_PATH="$APIM_DOWNLOAD_DEST"
  fi
fi

# Detect APIM version — from zip if pack provided, otherwise from found directory.
# Prefers a directory that already has the .sonicwave_configured marker.
if [[ -n "$PACK_PATH" ]]; then
  APIM_VERSION=$(python3 -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z:
    print(z.namelist()[0].split('/')[0])
" "$PACK_PATH")
else
  APIM_VERSION=$(basename "$FOUND")
fi
[[ -z "$APIM_VERSION" ]] && die "Cannot determine APIM version."

APIM_HOME="$SCRIPT_DIR/apim/$APIM_VERSION"
APIM_CONFIGURED_MARKER="$APIM_HOME/.sonicwave_configured"
DEPLOYMENT_TOML="$APIM_HOME/repository/conf/deployment.toml"
AUTH_SPEC="$SCRIPT_DIR/backend/auth_service/openapi_spec/Auth_openapi.yaml"
SONGS_SPEC="$SCRIPT_DIR/backend/webapp_backend/openapi_spec/Api_openapi.yaml"
BFF_CONFIG_TOML="$SCRIPT_DIR/bff_layer/Config.toml"
AUTH_SERVICE_DIR="$SCRIPT_DIR/backend/auth_service"
WEBAPP_BACKEND_DIR="$SCRIPT_DIR/backend/webapp_backend"
BFF_DIR="$SCRIPT_DIR/bff_layer"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

APIM_ADMIN="https://localhost:9443"
APIM_PUBLISHER="$APIM_ADMIN/api/am/publisher/v4"
APIM_DEVPORTAL="$APIM_ADMIN/api/am/devportal/v3"
DCR_ENDPOINT="$APIM_ADMIN/client-registration/v0.17/register"
TOKEN_ENDPOINT="$APIM_ADMIN/oauth2/token"

APIM_LOG="$SCRIPT_DIR/apim.log"
AUTH_LOG="$SCRIPT_DIR/auth_service.log"
WEBAPP_LOG="$SCRIPT_DIR/webapp_backend.log"
BFF_LOG="$SCRIPT_DIR/bff_layer.log"
FRONTEND_LOG="$SCRIPT_DIR/frontend.log"

AUTH_PID=""; WEBAPP_PID=""; BFF_PID=""; FRONTEND_PID=""

# ─── check required tools ─────────────────────────────────────────────────────
for cmd in curl python3 unzip bal npm lsof; do
  if ! command -v "$cmd" &>/dev/null; then
    if [[ "$cmd" == "lsof" ]]; then
      die "'lsof' is required but not found.\n  macOS: brew install lsof\n  Ubuntu/Debian: sudo apt install lsof"
    fi
    die "'$cmd' is required but not found."
  fi
done

# ─── helpers ──────────────────────────────────────────────────────────────────
json_field() {
  python3 -c "import sys,json; print(json.load(sys.stdin).get('$1','null') or 'null')"
}

curl_apim() {
  local method="$1"; local url="$2"; shift 2
  local body_file; body_file=$(mktemp)
  local status
  status=$(curl -sk -w "%{http_code}" -o "$body_file" -X "$method" "$url" "$@")
  local body; body=$(cat "$body_file"); rm -f "$body_file"
  if [[ "$status" != 2* ]]; then
    echo "$body" >&2
    die "HTTP $status from $method $url"
  fi
  echo "$body"
}

# ─── port helpers ─────────────────────────────────────────────────────────────
# check_ports <port>... — if any port is occupied show the owner and ask to kill
check_ports() {
  local busy_ports=() display_pids=()
  for port in "$@"; do
    # lsof may return multiple PIDs (one per line); take the first for display only
    local pid
    pid=$(lsof -ti tcp:"$port" 2>/dev/null | head -1 || true)
    [[ -n "$pid" ]] && busy_ports+=("$port") && display_pids+=("$pid")
  done
  [[ ${#busy_ports[@]} -eq 0 ]] && return 0

  echo ""
  warn "The following ports are already in use:"
  echo ""
  for i in "${!busy_ports[@]}"; do
    local proc
    proc=$(ps -p "${display_pids[$i]}" -o comm= 2>/dev/null | head -1 || echo "unknown")
    echo "  :${busy_ports[$i]}  →  PID ${display_pids[$i]}  ($proc)"
  done
  echo ""
  read -r -p "  Kill these processes and continue? [y/N] " answer
  echo ""
  [[ "$answer" =~ ^[Yy]$ ]] || die "Aborted. Free the ports listed above and try again."
  # Kill all PIDs on each port (handles multiple listeners per port)
  for port in "${busy_ports[@]}"; do
    lsof -ti tcp:"$port" 2>/dev/null | xargs kill -9 2>/dev/null || true
  done
  ok "Conflicting processes killed."
  sleep 1
}

# ─── stop handler ─────────────────────────────────────────────────────────────
stop_services() {
  echo ""
  echo "Stopping all services..."
  # SIGTERM tracked PIDs (exec means $! == actual process, not a wrapper shell)
  for pid in "$FRONTEND_PID" "$BFF_PID" "$AUTH_PID" "$WEBAPP_PID"; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 2
  # Force-kill anything still alive on our ports (catches child processes and npm workers)
  # Loop over ports individually — comma-separated syntax is not portable on GNU lsof
  for _port in 9090 8080 7001 3001; do
    lsof -ti tcp:"$_port" 2>/dev/null | xargs kill -9 2>/dev/null || true
  done
  # Stop APIM
  "$APIM_HOME/bin/api-manager.sh" stop 2>/dev/null || true
  echo "All services stopped."
  exit 0
}
trap stop_services INT TERM

# ─── banner ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SonicWave"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1A — FIRST-TIME APIM PROVISIONING
# Skipped on subsequent runs (marker file present).
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "$APIM_CONFIGURED_MARKER" ]]; then

  echo ""
  info "First run detected — provisioning APIM..."
  echo ""

  TMP_DIR=$(mktemp -d)
  cleanup_tmp() { rm -rf "$TMP_DIR"; }
  trap 'cleanup_tmp; stop_services' INT TERM

  # 1. Extract pack
  if [[ -d "$APIM_HOME" ]]; then
    warn "apim/$APIM_VERSION already exists — skipping extraction."
  else
    [[ -z "$PACK_PATH" ]] && die "apim/$APIM_VERSION not found. Provide --pack /path/to/wso2am-*.zip"
    [[ ! -f "$PACK_PATH" ]] && die "Pack not found: $PACK_PATH"
    info "Extracting APIM pack ($APIM_VERSION)..."
    mkdir -p "$SCRIPT_DIR/apim"
    unzip -q "$PACK_PATH" -d "$SCRIPT_DIR/apim"
    [[ -d "$APIM_HOME" ]] || die "Extraction failed — expected directory: $APIM_HOME"
    ok "Extracted to apim/$APIM_VERSION/"
    # Remove the downloaded zip if it was fetched automatically (keep user-provided packs)
    [[ "$PACK_PATH" == "$APIM_DOWNLOAD_DEST" ]] && rm -f "$APIM_DOWNLOAD_DEST"
  fi

  # 2. Patch deployment.toml CORS
  info "Patching deployment.toml..."
  CORS_HEADERS='["authorization","Access-Control-Allow-Origin","Content-Type","SOAPAction","apikey","Internal-Key","X-Sonicwave-User-Auth"]'
  if grep -q "X-Sonicwave-User-Auth" "$DEPLOYMENT_TOML" 2>/dev/null; then
    warn "CORS header already present — skipping."
  elif grep -q "^\[apim\.cors\]" "$DEPLOYMENT_TOML" 2>/dev/null; then
    sed -i.bak "s|^allow_headers = .*|allow_headers = $CORS_HEADERS|" "$DEPLOYMENT_TOML"
    rm -f "${DEPLOYMENT_TOML}.bak"
    ok "Updated allow_headers in existing [apim.cors]."
  else
    printf '\n[apim.cors]\nallow_origins = "*"\nallow_methods = ["GET","PUT","POST","DELETE","PATCH","OPTIONS"]\nallow_headers = %s\nallow_credentials = false\n' \
      "$CORS_HEADERS" >> "$DEPLOYMENT_TOML"
    ok "Appended [apim.cors] to deployment.toml."
  fi

  # 3. Start APIM and wait
  check_ports 9443 8243
  info "Starting APIM for provisioning..."
  "$APIM_HOME/bin/api-manager.sh" start > "$APIM_LOG" 2>&1
  info "Waiting for APIM REST API to be reachable (up to 5 minutes)..."
  TIMEOUT=300; ELAPSED=0; INTERVAL=10
  until curl -sk --max-time 5 "$APIM_PUBLISHER/apis" -o /dev/null 2>/dev/null; do
    sleep "$INTERVAL"; ELAPSED=$((ELAPSED + INTERVAL))
    [[ $ELAPSED -ge $TIMEOUT ]] && die "APIM not reachable after ${TIMEOUT}s. Check apim.log."
    info "  Still waiting... (${ELAPSED}s elapsed)"
  done
  ok "APIM REST API reachable."
  sleep 5

  # 4. DCR + admin token
  info "Registering DCR client..."
  dcr_resp=$(curl -sk -X POST "$DCR_ENDPOINT" -u "admin:admin" \
    -H "Content-Type: application/json" \
    -d '{"clientName":"sonicwave_setup_client","owner":"admin","grantType":"password refresh_token client_credentials","saasApp":true}')
  DCR_CLIENT_ID=$(echo "$dcr_resp" | json_field clientId)
  DCR_CLIENT_SECRET=$(echo "$dcr_resp" | json_field clientSecret)
  [[ "$DCR_CLIENT_ID" == "null" || -z "$DCR_CLIENT_ID" ]] && {
    echo "$dcr_resp" >&2; die "DCR registration failed."; }
  ok "DCR client registered."

  info "Obtaining admin token..."
  token_resp=$(curl -sk -X POST "$TOKEN_ENDPOINT" \
    -u "$DCR_CLIENT_ID:$DCR_CLIENT_SECRET" \
    -d "grant_type=password&username=admin&password=admin&scope=apim:api_create apim:api_publish apim:api_view apim:subscribe apim:app_manage apim:api_product_create apim:api_product_publish apim:api_product_view")
  ADMIN_TOKEN=$(echo "$token_resp" | json_field access_token)
  [[ "$ADMIN_TOKEN" == "null" || -z "$ADMIN_TOKEN" ]] && {
    echo "$token_resp" >&2; die "Failed to obtain admin token."; }
  ok "Admin token obtained."
  AUTH_HDR="Authorization: Bearer $ADMIN_TOKEN"

  # 5. Import SonicwaveAuth API
  info "Importing SonicwaveAuth API..."
  cat > "$TMP_DIR/auth_props.json" <<'JSON'
{
  "name": "SonicwaveAuth",
  "version": "0.1.0",
  "context": "/sonicwave-auth",
  "policies": ["Unlimited"],
  "gatewayType": "wso2/synapse",
  "transport": ["http","https"],
  "endpointConfig": {
    "endpoint_type": "http",
    "production_endpoints": {"url": "http://localhost:9090/auth"},
    "sandbox_endpoints":    {"url": "http://localhost:9090/auth"}
  }
}
JSON
  auth_api_resp=$(curl_apim POST "$APIM_PUBLISHER/apis/import-openapi" \
    -H "$AUTH_HDR" \
    -F "file=@$AUTH_SPEC" \
    -F "additionalProperties=<$TMP_DIR/auth_props.json;type=application/json")
  AUTH_API_ID=$(echo "$auth_api_resp" | json_field id)
  ok "SonicwaveAuth created: $AUTH_API_ID"

  # 6. Import SonicwaveSongs API
  info "Importing SonicwaveSongs API..."
  cat > "$TMP_DIR/songs_props.json" <<'JSON'
{
  "name": "SonicwaveSongs",
  "version": "0.1.0",
  "context": "/sonicwave-songs",
  "policies": ["Unlimited"],
  "gatewayType": "wso2/synapse",
  "transport": ["http","https"],
  "endpointConfig": {
    "endpoint_type": "http",
    "production_endpoints": {"url": "http://localhost:8080/api"},
    "sandbox_endpoints":    {"url": "http://localhost:8080/api"}
  }
}
JSON
  songs_api_resp=$(curl_apim POST "$APIM_PUBLISHER/apis/import-openapi" \
    -H "$AUTH_HDR" \
    -F "file=@$SONGS_SPEC" \
    -F "additionalProperties=<$TMP_DIR/songs_props.json;type=application/json")
  SONGS_API_ID=$(echo "$songs_api_resp" | json_field id)
  ok "SonicwaveSongs created: $SONGS_API_ID"

  # 7. Publish and deploy both APIs
  for entry in "SonicwaveAuth:$AUTH_API_ID" "SonicwaveSongs:$SONGS_API_ID"; do
    name="${entry%%:*}"; id="${entry##*:}"
    info "Publishing $name..."
    curl_apim POST "$APIM_PUBLISHER/apis/change-lifecycle?action=Publish&apiId=$id" \
      -H "$AUTH_HDR" > /dev/null
    info "Creating revision for $name..."
    rev_resp=$(curl_apim POST "$APIM_PUBLISHER/apis/$id/revisions" \
      -H "$AUTH_HDR" -H "Content-Type: application/json" \
      -d '{"description":"Initial deployment"}')
    rev_id=$(echo "$rev_resp" | json_field id)
    info "Deploying $name..."
    curl_apim POST "$APIM_PUBLISHER/apis/$id/deploy-revision?revisionId=$rev_id" \
      -H "$AUTH_HDR" -H "Content-Type: application/json" \
      -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":false}]' > /dev/null
    ok "$name published and deployed."
  done

  # 8. Create MusicLibrary API Product
  info "Creating MusicLibrary API Product at /library/0.9.0..."
  cat > "$TMP_DIR/product.json" <<JSON
{
  "name": "MusicLibrary",
  "version": "0.9.0",
  "context": "/library/0.9.0",
  "visibility": "PUBLIC",
  "policies": ["Unlimited"],
  "transport": ["http","https"],
  "apis": [
    {
      "name": "SonicwaveAuth",
      "version": "0.1.0",
      "apiId": "$AUTH_API_ID",
      "operations": [
        {"target": "/register", "verb": "POST"},
        {"target": "/login",    "verb": "POST"},
        {"target": "/validate", "verb": "GET"}
      ]
    },
    {
      "name": "SonicwaveSongs",
      "version": "0.1.0",
      "apiId": "$SONGS_API_ID",
      "operations": [
        {"target": "/songs",      "verb": "GET"},
        {"target": "/songs",      "verb": "POST"},
        {"target": "/songs/{id}", "verb": "GET"}
      ]
    }
  ]
}
JSON
  product_resp=$(curl_apim POST "$APIM_PUBLISHER/api-products" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d @"$TMP_DIR/product.json")
  PRODUCT_ID=$(echo "$product_resp" | json_field id)
  ok "MusicLibrary API Product created: $PRODUCT_ID"

  # 9. Publish and deploy API Product
  info "Publishing MusicLibrary..."
  curl_apim POST "$APIM_PUBLISHER/api-products/change-lifecycle?action=Publish&apiProductId=$PRODUCT_ID" \
    -H "$AUTH_HDR" > /dev/null
  info "Creating revision for MusicLibrary..."
  prod_rev_resp=$(curl_apim POST "$APIM_PUBLISHER/api-products/$PRODUCT_ID/revisions" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d '{"description":"Initial deployment"}')
  prod_rev_id=$(echo "$prod_rev_resp" | json_field id)
  info "Deploying MusicLibrary..."
  curl_apim POST "$APIM_PUBLISHER/api-products/$PRODUCT_ID/deploy-revision?revisionId=$prod_rev_id" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' > /dev/null
  ok "MusicLibrary published and deployed."

  # 10. Create DevPortal application
  info "Creating LibraryApplication..."
  app_resp=$(curl_apim POST "$APIM_DEVPORTAL/applications" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d '{"name":"LibraryApplication","throttlingPolicy":"Unlimited","tokenType":"JWT"}')
  APP_ID=$(echo "$app_resp" | json_field applicationId)
  ok "LibraryApplication created: $APP_ID"

  # 11. Subscribe to MusicLibrary
  info "Subscribing LibraryApplication to MusicLibrary..."
  curl_apim POST "$APIM_DEVPORTAL/subscriptions" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d "{\"applicationId\":\"$APP_ID\",\"apiId\":\"$PRODUCT_ID\",\"throttlingPolicy\":\"Unlimited\"}" > /dev/null
  ok "Subscription created."

  # 12. Generate PRODUCTION OAuth keys
  info "Generating PRODUCTION OAuth keys..."
  keys_resp=$(curl_apim POST "$APIM_DEVPORTAL/applications/$APP_ID/generate-keys" \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d '{"keyType":"PRODUCTION","grantTypesToBeSupported":["client_credentials"],"callbackUrl":"","additionalProperties":{},"keyManager":"Resident Key Manager"}')
  CONSUMER_KEY=$(echo "$keys_resp" | json_field consumerKey)
  CONSUMER_SECRET=$(echo "$keys_resp" | json_field consumerSecret)
  [[ "$CONSUMER_KEY" == "null" || -z "$CONSUMER_KEY" ]] && {
    echo "$keys_resp" >&2; die "Key generation failed."; }
  ok "OAuth keys generated."

  # 13. Write credentials to BFF config
  info "Writing credentials to bff_layer/Config.toml..."
  cat > "$BFF_CONFIG_TOML" <<TOML
serverPort       = 7001
allowedOrigin    = "http://localhost:3001"
apimGatewayUrl   = "https://localhost:8243"
apimTokenUrl     = "https://localhost:9443"
apimClientId     = "$CONSUMER_KEY"
apimClientSecret = "$CONSUMER_SECRET"
cookieMaxAge     = 86400
TOML
  ok "Credentials written."

  # Mark as provisioned so this phase is skipped on next run
  touch "$APIM_CONFIGURED_MARKER"
  cleanup_tmp

  # Restore normal trap
  trap stop_services INT TERM

  echo ""
  ok "APIM provisioning complete."
  echo "  Consumer Key    : $CONSUMER_KEY"
  echo "  Consumer Secret : $CONSUMER_SECRET"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1B — SUBSEQUENT RUN: start APIM normally
# ─────────────────────────────────────────────────────────────────────────────
else
  check_ports 9443 8243
  info "APIM already provisioned — starting..."
  "$APIM_HOME/bin/api-manager.sh" start > "$APIM_LOG" 2>&1
  ok "APIM started. (log: apim.log)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — START ALL SERVICES
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Starting services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

check_ports 9090 8080 7001 3001

info "Starting auth_service on :9090..."
(cd "$AUTH_SERVICE_DIR" && exec bal run > "$AUTH_LOG" 2>&1) &
AUTH_PID=$!
ok "auth_service   PID $AUTH_PID  (log: auth_service.log)"

info "Starting webapp_backend on :8080..."
(cd "$WEBAPP_BACKEND_DIR" && exec bal run > "$WEBAPP_LOG" 2>&1) &
WEBAPP_PID=$!
ok "webapp_backend PID $WEBAPP_PID  (log: webapp_backend.log)"

info "Starting BFF on :7001..."
(cd "$BFF_DIR" && exec bal run > "$BFF_LOG" 2>&1) &
BFF_PID=$!
ok "bff_layer      PID $BFF_PID  (log: bff_layer.log)"

echo ""
info "Waiting 10s for services to initialise..."
sleep 10

info "Starting frontend on :3001..."
(cd "$FRONTEND_DIR" && exec npm run dev > "$FRONTEND_LOG" 2>&1) &
FRONTEND_PID=$!
ok "frontend       PID $FRONTEND_PID  (log: frontend.log)"

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
