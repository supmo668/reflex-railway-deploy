#!/bin/bash
# deploy.sh - Streamlined Railway deployment for Reflex apps
# Usage: ./deploy.sh -p PROJECT -e ENV -b BACKEND -f FRONTEND [OPTIONS]
#
# Security: Backend is NOT publicly exposed. Frontend uses Railway's internal
# networking to communicate with backend via <service>.railway.internal:8000
#
# Deployment flow:
#   1. Link to Railway project
#   2. Get database URL from Postgres service (if not skipped)
#   3. Ensure services exist
#   4. Set ALL variables in ONE batch per service (triggers ONE redeploy)
#   5. Deploy code via 'railway up' (pushes new code)
#   6. Ensure domain exists (FRONTEND ONLY - backend stays internal)

set -e

# === LOGGING ===
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# === PARSE ARGS ===
DEPLOY_DIR="reflex-railway-deploy"
SKIP_DB=false
POSTGRES_SERVICE="Postgres"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 -p PROJECT -e ENV -b BACKEND -f FRONTEND [OPTIONS]"
            echo "  -p PROJECT    Railway project name"
            echo "  -e ENV        Railway environment (test, production)"
            echo "  -b BACKEND    Backend service name"
            echo "  -f FRONTEND   Frontend service name"
            echo "  -d DIR        Deploy directory (default: reflex-railway-deploy)"
            echo "  --env-file    Environment file (default: .env)"
            echo "  --skip-db     Skip PostgreSQL lookup (for demo mode)"
            exit 0 ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -b|--backend) BACKEND_SERVICE="$2"; shift 2 ;;
        -f|--frontend) FRONTEND_SERVICE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --env-file) ENV_FILE="$2"; shift 2 ;;
        --skip-db) SKIP_DB=true; shift ;;
        --postgres-service) POSTGRES_SERVICE="$2"; shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# === VALIDATE ===
[ -z "$RAILWAY_PROJECT" ] && error "Missing -p PROJECT"
[ -z "$RAILWAY_ENVIRONMENT" ] && error "Missing -e ENVIRONMENT"
[ -z "$BACKEND_SERVICE" ] && error "Missing -b BACKEND"
[ -z "$FRONTEND_SERVICE" ] && error "Missing -f FRONTEND"
[ -d "$DEPLOY_DIR" ] || error "Deploy dir '$DEPLOY_DIR' not found"
command -v railway &>/dev/null || error "Railway CLI not found"
railway whoami &>/dev/null || error "Not logged in. Run 'railway login'"

# Source env file
[ -f "${ENV_FILE:-.env}" ] && { set -a; source "${ENV_FILE:-.env}"; set +a; }

# =============================================================================
# URL Configuration (Security Best Practice - Internal Networking):
# =============================================================================
# Backend Service (NO public domain):
#   - No REFLEX_API_URL needed (defaults to http://localhost:8000)
#   - No REFLEX_DEPLOY_URL needed (defaults to http://localhost:8000)
#   - CORS_ALLOWED_ORIGINS = frontend public URL
#
# Frontend Service:
#   - REFLEX_API_URL = http://<backend>.railway.internal:8000 (internal URL)
#   - REFLEX_DEPLOY_URL = https://<frontend>-<env>.up.railway.app (public URL)
# =============================================================================
BACKEND_INTERNAL_URL="http://${BACKEND_SERVICE}.railway.internal:8000"
FRONTEND_PUBLIC_URL="https://${FRONTEND_SERVICE}-${RAILWAY_ENVIRONMENT}.up.railway.app"

# === HELPER FUNCTIONS ===

# Build variables array for a service
build_vars() {
    local service_type=$1  # "backend" or "frontend"
    local -n arr=$2        # nameref to output array
    
    # Database - only set if REFLEX_DB_URL is explicitly provided
    [ -n "$REFLEX_DB_URL" ] && arr+=("--set" "REFLEX_DB_URL=$REFLEX_DB_URL")
    
    # Service-specific URL configuration
    if [ "$service_type" = "frontend" ]; then
        # Frontend: REFLEX_API_URL = backend INTERNAL URL (secure, not exposed)
        arr+=("--set" "REFLEX_API_URL=$BACKEND_INTERNAL_URL")
        # Frontend: REFLEX_DEPLOY_URL = frontend's OWN public URL
        arr+=("--set" "REFLEX_DEPLOY_URL=$FRONTEND_PUBLIC_URL")
        arr+=("--set" "PORT=3000")
    else
        # Backend: No REFLEX_API_URL or REFLEX_DEPLOY_URL (defaults to localhost:8000)
        # Backend: CORS_ALLOWED_ORIGINS = frontend public URL
        arr+=("--set" "CORS_ALLOWED_ORIGINS=$FRONTEND_PUBLIC_URL")
        arr+=("--set" "PORT=8000")
    fi
    
    # App-specific vars from APP_ENV_VARS
    for var in $APP_ENV_VARS; do
        [ -n "${!var}" ] && arr+=("--set" "$var=${!var}")
    done
}

# Set all variables on a service (single command = single redeploy)
set_vars() {
    local service=$1 service_type=$2
    local vars=()
    build_vars "$service_type" vars
    
    if [ ${#vars[@]} -gt 0 ]; then
        log "Setting $((${#vars[@]}/2)) vars on $service..."
        railway variables --service "$service" "${vars[@]}" || warn "Some vars failed for $service"
    fi
}

# Deploy code to a service
deploy_service() {
    local service=$1 dockerfile=$2
    log "Deploying $service..."
    cp "$DEPLOY_DIR/$dockerfile" Dockerfile
    railway up --service "$service" || error "Failed to deploy $service"
    rm -f Dockerfile
    success "$service deployed"
}

# Ensure service exists
ensure_service() {
    local service=$1 is_frontend=${2:-false}
    if ! railway variables --service "$service" &>/dev/null; then
        log "Creating service: $service"
        railway add -s "$service" || error "Failed to create $service"
        sleep 3
    fi
    # Only add public domain for frontend (backend stays internal for security)
    if [ "$is_frontend" = true ]; then
        railway domain --service "$service" &>/dev/null || true
        log "Public domain added for $service"
    fi
}

# === MAIN ===
log "=== Railway Deployment ==="
log "Project: $RAILWAY_PROJECT | Env: $RAILWAY_ENVIRONMENT"
log "Backend: $BACKEND_SERVICE (internal only)"
log "Frontend: $FRONTEND_SERVICE (public)"

# 1. Link to project
railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" || error "Failed to link"

# 2. Get database URL (Railway Postgres provides DATABASE_URL, we map to REFLEX_DB_URL)
if [ "$SKIP_DB" = false ]; then
    REFLEX_DB_URL=$(railway variables --service "$POSTGRES_SERVICE" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' || echo "")
    [ -n "$REFLEX_DB_URL" ] && success "Database URL retrieved (REFLEX_DB_URL)" || warn "No database URL found"
fi

# 3. Ensure services exist (backend internal, frontend public)
ensure_service "$BACKEND_SERVICE" false
ensure_service "$FRONTEND_SERVICE" true

# 4. Set variables (batched - triggers ONE redeploy per service with OLD code)
set_vars "$BACKEND_SERVICE" "backend"
set_vars "$FRONTEND_SERVICE" "frontend"

# 5. Deploy code (pushes NEW code)
deploy_service "$BACKEND_SERVICE" "Dockerfile.backend"
deploy_service "$FRONTEND_SERVICE" "Dockerfile.frontend"

# 6. Summary
FRONTEND_DOMAIN=$(railway variables --service "$FRONTEND_SERVICE" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' || echo "")

echo ""
success "=== Deployment Complete ==="
echo "  Frontend: https://${FRONTEND_DOMAIN:-$FRONTEND_SERVICE-$RAILWAY_ENVIRONMENT.up.railway.app}"
echo "  Backend:  $BACKEND_INTERNAL_URL (internal only - not publicly exposed)"
[ "$SKIP_DB" = false ] && echo "  Database: PostgreSQL running"
echo ""
echo "Check status at: https://railway.app/project/$RAILWAY_PROJECT"
