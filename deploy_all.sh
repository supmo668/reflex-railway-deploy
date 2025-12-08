#!/bin/bash
# deploy_all.sh - Streamlined Railway deployment for Reflex applications
# Handles both first-time and subsequent deployments with batched variable updates
set -e

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ CONFIGURATION & HELPERS                                           ║
# ╚═══════════════════════════════════════════════════════════════════╝
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header()  { echo -e "\n${BLUE}═══ $1 ═══${NC}"; }
pause()   { [ "$AUTO_MODE" = true ] || { echo -e "${YELLOW}Press ENTER to continue...${NC}"; read -r; }; }

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ SERVICE DETECTION                                                  ║
# ╚═══════════════════════════════════════════════════════════════════╝
service_exists() {
    local service=$1 cache="$DEPLOY_DIR/railway_services.json"
    [ -f "$cache" ] || return 1
    local env_id=$(jq -r --arg e "$RAILWAY_ENVIRONMENT" '.[] | .environments.edges[] | .node | select(.name == $e) | .id' "$cache" 2>/dev/null | head -1)
    [ -z "$env_id" ] && return 1
    jq -e --arg s "$service" --arg eid "$env_id" \
        '.[] | .services.edges[] | .node | select(.name == $s) | select(.serviceInstances.edges[] | .node.environmentId == $eid)' \
        "$cache" >/dev/null 2>&1
}

check_services() {
    header "Checking Services"
    railway list --json > "$DEPLOY_DIR/railway_services.json" 2>/dev/null || echo "[]" > "$DEPLOY_DIR/railway_services.json"
    
    POSTGRES_EXISTS=false; BACKEND_EXISTS=false; FRONTEND_EXISTS=false
    service_exists "Postgres" && POSTGRES_EXISTS=true
    service_exists "$BACKEND_NAME" && BACKEND_EXISTS=true  
    service_exists "$FRONTEND_NAME" && FRONTEND_EXISTS=true
    
    log "Postgres: $POSTGRES_EXISTS | Backend: $BACKEND_EXISTS | Frontend: $FRONTEND_EXISTS"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ DATABASE                                                           ║
# ╚═══════════════════════════════════════════════════════════════════╝
get_db_url() {
    # Skip if SKIP_DB is set
    [ "$SKIP_DB" = true ] && { REFLEX_DB_URL=""; return 0; }
    DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
    DATABASE_PUBLIC_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
    REFLEX_DB_URL="$DATABASE_URL"
}

run_migrations() {
    # Skip if SKIP_DB is set
    [ "$SKIP_DB" = true ] && { log "Database skipped (SKIP_DB=true)"; return 0; }
    header "Database Migrations"
    get_db_url
    local url="${DATABASE_PUBLIC_URL:-$DATABASE_URL}"
    [ -z "$url" ] && { warn "No database URL, skipping migrations"; return 0; }
    
    log "Running migrations..."
    REFLEX_DB_URL="$url" uv run reflex db init 2>/dev/null || true
    REFLEX_DB_URL="$url" uv run reflex db makemigrations 2>/dev/null || true
    REFLEX_DB_URL="$url" uv run reflex db migrate || error "Migrations failed"
    success "Migrations complete"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ VARIABLE MANAGEMENT (BATCHED)                                      ║
# ╚═══════════════════════════════════════════════════════════════════╝
# Build --set args from APP_ENV_VARS + derived vars
# =============================================================================
# URL Configuration (Single Source of Truth):
# =============================================================================
# Backend Service:
#   REFLEX_API_URL = http://localhost:8000 (backend talks to itself locally)
#   REFLEX_DEPLOY_URL = https://<backend-name>-<env>.up.railway.app (public URL)
#   CORS_ALLOWED_ORIGINS = frontend public URL (for CORS)
#
# Frontend Service:
#   REFLEX_API_URL = https://<backend-name>-<env>.up.railway.app (or internal URL)
#   REFLEX_DEPLOY_URL = https://<frontend-name>-<env>.up.railway.app (own URL)
# =============================================================================
build_var_args() {
    local service=$1
    VAR_ARGS=()
    
    # Add app environment variables from APP_ENV_VARS (comma-separated key=value pairs)
    if [ -n "$APP_ENV_VARS" ]; then
        IFS=',' read -ra vars <<< "$APP_ENV_VARS"
        for var in "${vars[@]}"; do
            local key="${var%%=*}" val="${var#*=}"
            [ -n "$key" ] && [ -n "$val" ] && VAR_ARGS+=("--set" "$key=$val")
        done
    fi
    
    # Core environment variables (both services need these)
    [ -n "$APP_ENV" ] && VAR_ARGS+=("--set" "APP_ENV=$APP_ENV")
    [ -n "$IS_DEMO" ] && VAR_ARGS+=("--set" "IS_DEMO=$IS_DEMO")
    [ -n "$OPENAI_API_KEY" ] && VAR_ARGS+=("--set" "OPENAI_API_KEY=$OPENAI_API_KEY")
    [ -n "$CALL_API_TOKEN" ] && VAR_ARGS+=("--set" "CALL_API_TOKEN=$CALL_API_TOKEN")
    [ -n "$LOGLEVEL" ] && VAR_ARGS+=("--set" "LOGLEVEL=$LOGLEVEL")
    
    # Add derived Railway variables (skip DB if SKIP_DB is set)
    [ -n "$REFLEX_DB_URL" ] && [ "$SKIP_DB" != true ] && VAR_ARGS+=("--set" "REFLEX_DB_URL=$REFLEX_DB_URL")
    
    # Service-specific URL configuration
    if [ "$service" = "$FRONTEND_NAME" ]; then
        # Frontend: REFLEX_API_URL = backend public URL (for WebSocket/API calls)
        [ -n "$BACKEND_PUBLIC_URL" ] && VAR_ARGS+=("--set" "REFLEX_API_URL=$BACKEND_PUBLIC_URL")
        # Frontend: REFLEX_DEPLOY_URL = frontend's OWN public URL
        [ -n "$FRONTEND_PUBLIC_URL" ] && VAR_ARGS+=("--set" "REFLEX_DEPLOY_URL=$FRONTEND_PUBLIC_URL")
    fi
    
    if [ "$service" = "$BACKEND_NAME" ]; then
        # Backend: REFLEX_API_URL = localhost (backend talks to itself)
        VAR_ARGS+=("--set" "REFLEX_API_URL=http://localhost:8000")
        # Backend: REFLEX_DEPLOY_URL = backend's OWN public URL
        [ -n "$BACKEND_PUBLIC_URL" ] && VAR_ARGS+=("--set" "REFLEX_DEPLOY_URL=$BACKEND_PUBLIC_URL")
        # Backend: CORS_ALLOWED_ORIGINS = frontend public URL
        [ -n "$FRONTEND_PUBLIC_URL" ] && VAR_ARGS+=("--set" "CORS_ALLOWED_ORIGINS=$FRONTEND_PUBLIC_URL")
    fi
}

# Set vars and deploy using Dockerfile
set_vars_and_deploy() {
    local service=$1 type=$2
    header "Deploying $service ($type)"
    
    # Copy the appropriate Dockerfile to root
    if [ "$type" = "backend" ]; then
        cp "$DEPLOY_DIR/Dockerfile.backend" Dockerfile 2>/dev/null || error "Dockerfile.backend not found"
    else
        cp "$DEPLOY_DIR/Dockerfile.frontend" Dockerfile 2>/dev/null || error "Dockerfile.frontend not found"
    fi
    
    # Build variable args
    build_var_args "$service"
    
    # Link to service
    railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} || error "Failed to link to $service"
    
    # Set variables first (railway variables --set)
    if [ ${#VAR_ARGS[@]} -gt 0 ]; then
        log "Setting ${#VAR_ARGS[@]} variables..."
        railway variables "${VAR_ARGS[@]}" || warn "Some variables may not have been set"
    fi
    
    # Then deploy
    log "Deploying $service..."
    railway up || error "Deploy failed for $service"
    success "$service deployed"
}

# Update URL variables after deployment (fetch from Railway if domains differ)
update_urls() {
    local backend_domain frontend_domain
    backend_domain=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    frontend_domain=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    # Update URLs if Railway provided different domains
    [ -n "$backend_domain" ] && BACKEND_PUBLIC_URL="https://$backend_domain"
    [ -n "$frontend_domain" ] && FRONTEND_PUBLIC_URL="https://$frontend_domain"
    
    log "Backend Public URL: $BACKEND_PUBLIC_URL"
    log "Frontend Public URL: $FRONTEND_PUBLIC_URL"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ SERVICE CREATION (FIRST-TIME ONLY)                                 ║
# ╚═══════════════════════════════════════════════════════════════════╝
create_postgres() {
    # Skip if SKIP_DB is set
    [ "$SKIP_DB" = true ] && { log "PostgreSQL skipped (SKIP_DB=true)"; return 0; }
    [ "$POSTGRES_EXISTS" = true ] && { success "Postgres exists"; return 0; }
    header "Creating PostgreSQL"
    railway add -d postgres -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} || error "Failed to add PostgreSQL"
    sleep 15
    success "PostgreSQL created"
}

create_service() {
    local service=$1
    service_exists "$service" && { success "$service exists"; return 0; }
    header "Creating $service"
    railway add --service "$service" -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} || error "Failed to create $service"
    railway domain --service "$service" >/dev/null 2>&1 || true
    success "$service created"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ MAIN DEPLOYMENT FLOW                                               ║
# ╚═══════════════════════════════════════════════════════════════════╝
deploy() {
    # Validate
    command -v railway &>/dev/null || error "Railway CLI not found"
    railway whoami &>/dev/null || error "Not logged in. Run: railway login"
    
    # Check what exists
    check_services
    pause
    
    # Create services if needed (first-time setup)
    local need_create=false
    [ "$SKIP_DB" != true ] && [ "$POSTGRES_EXISTS" = false ] && need_create=true
    [ "$BACKEND_EXISTS" = false ] && need_create=true  
    [ "$FRONTEND_EXISTS" = false ] && need_create=true
    
    if [ "$need_create" = true ]; then
        create_postgres
        [ "$SKIP_DB" != true ] && get_db_url
        create_service "$BACKEND_NAME"
        create_service "$FRONTEND_NAME"
        # Refresh service list
        railway list --json > "$DEPLOY_DIR/railway_services.json" 2>/dev/null || true
        pause
    fi
    
    # Run migrations (skipped if SKIP_DB=true)
    run_migrations
    pause
    
    # Deploy backend first (frontend needs backend URL)
    [ "$SKIP_DB" != true ] && get_db_url
    set_vars_and_deploy "$BACKEND_NAME" "backend"
    
    # Get backend URL for frontend (if Railway provided different domain)
    update_urls
    pause
    
    # Deploy frontend with REFLEX_API_URL pointing to backend
    set_vars_and_deploy "$FRONTEND_NAME" "frontend"
    
    # Final URL update
    update_urls
    
    # Summary
    header "Deployment Complete"
    echo "✓ Backend:  $BACKEND_PUBLIC_URL"
    echo "✓ Frontend: $FRONTEND_PUBLIC_URL"
    [ "$SKIP_DB" = true ] && echo "✓ Database: Skipped (demo mode)"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ ARGUMENT PARSING                                                   ║
# ╚═══════════════════════════════════════════════════════════════════╝
show_help() {
    cat << EOF
Usage: $0 -p PROJECT [OPTIONS]

Required:
  -p, --project PROJECT     Railway project ID/name

Optional:
  -t, --team TEAM          Railway team (default: personal)
  -e, --environment ENV    Railway environment (default: production)
  -d, --deploy-dir DIR     Deploy directory (default: reflex-railway-deploy)
  -f, --file FILE          Environment file (default: .env)
  -b, --backend NAME       Backend service name (default: backend)
  -n, --frontend NAME      Frontend service name (default: frontend)
  --skip-db                Skip PostgreSQL setup and migrations (for demo mode)
  -y, --yes                Auto mode (skip pauses)
  -h, --help               Show this help

Examples:
  $0 -p my-project
  $0 -p my-project -b api -n web -y
  $0 -p my-project --skip-db -y   # Deploy without database (demo mode)
EOF
    exit 0
}

# Defaults
DEPLOY_DIR="reflex-railway-deploy"
ENV_FILE=".env"
BACKEND_NAME="backend"
FRONTEND_NAME="frontend"
RAILWAY_ENVIRONMENT="production"
RAILWAY_TEAM=""
AUTO_MODE=false
SKIP_DB=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -t|--team) RAILWAY_TEAM="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        -b|--backend) BACKEND_NAME="$2"; shift 2 ;;
        -n|--frontend) FRONTEND_NAME="$2"; shift 2 ;;
        --skip-db) SKIP_DB=true; shift ;;
        -y|--yes) AUTO_MODE=true; shift ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Validate
[ -z "$RAILWAY_PROJECT" ] && error "Project required. Use: $0 -p PROJECT"
[ -d "$DEPLOY_DIR" ] || error "Deploy dir not found: $DEPLOY_DIR"

# Load environment files using hierarchical envs/ structure
# Order: .env.base -> .env.prod -> .env.secrets (later files override)
ENVS_DIR="envs"
if [ -d "$ENVS_DIR" ]; then
    log "Loading environment from $ENVS_DIR/"
    [ -f "$ENVS_DIR/.env.base" ] && { set -a; source "$ENVS_DIR/.env.base"; set +a; log "  ✓ Loaded .env.base"; }
    [ -f "$ENVS_DIR/.env.prod" ] && { set -a; source "$ENVS_DIR/.env.prod"; set +a; log "  ✓ Loaded .env.prod"; }
    [ -f "$ENVS_DIR/.env.secrets" ] && { set -a; source "$ENVS_DIR/.env.secrets"; set +a; log "  ✓ Loaded .env.secrets"; }
elif [ -f "$ENV_FILE" ]; then
    # Fallback to single .env file
    set -a; source "$ENV_FILE"; set +a
    log "Loaded $ENV_FILE"
fi

# Auto-enable SKIP_DB if IS_DEMO is true (no database needed for demo mode)
[ "$IS_DEMO" = "true" ] && SKIP_DB=true

# =============================================================================
# Derive public URLs from service names and environment
# Convention: https://<service-name>-<environment>.up.railway.app
# =============================================================================
BACKEND_PUBLIC_URL="https://${BACKEND_NAME}-${RAILWAY_ENVIRONMENT}.up.railway.app"
FRONTEND_PUBLIC_URL="https://${FRONTEND_NAME}-${RAILWAY_ENVIRONMENT}.up.railway.app"
# Internal Railway URL (for service-to-service communication)
BACKEND_INTERNAL_URL="${BACKEND_NAME}.railway.internal"

# Show config
header "Railway Deployment"
echo "Project: $RAILWAY_PROJECT | Env: $RAILWAY_ENVIRONMENT"
echo "Backend: $BACKEND_NAME | Frontend: $FRONTEND_NAME"
[ -n "$RAILWAY_TEAM" ] && echo "Team: $RAILWAY_TEAM"
[ "$SKIP_DB" = true ] && echo "Database: SKIPPED (demo mode)"
echo "Backend Public URL: $BACKEND_PUBLIC_URL"
echo "Backend Internal URL: $BACKEND_INTERNAL_URL"
echo "Frontend Public URL: $FRONTEND_PUBLIC_URL"

# Run deployment
deploy
