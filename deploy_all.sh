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
    DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
    DATABASE_PUBLIC_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
    REFLEX_DB_URL="$DATABASE_URL"
}

run_migrations() {
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
    
    # Add derived Railway variables
    [ -n "$REFLEX_DB_URL" ] && VAR_ARGS+=("--set" "REFLEX_DB_URL=$REFLEX_DB_URL")
    
    # Service-specific derived vars
    if [ "$service" = "$FRONTEND_NAME" ] && [ -n "$REFLEX_API_URL" ]; then
        VAR_ARGS+=("--set" "REFLEX_API_URL=$REFLEX_API_URL")
    fi
    [ -n "$FRONTEND_DEPLOY_URL" ] && VAR_ARGS+=("--set" "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL")
}

# Set vars and deploy in ONE railway up command
set_vars_and_deploy() {
    local service=$1 type=$2
    header "Deploying $service ($type)"
    
    # Copy config files
    cp "$DEPLOY_DIR/Caddyfile.$type" Caddyfile 2>/dev/null || warn "Caddyfile.$type not found"
    cp "$DEPLOY_DIR/nixpacks.$type.toml" nixpacks.toml 2>/dev/null || warn "nixpacks.$type.toml not found"
    
    # Build variable args
    build_var_args "$service"
    
    # Link to service
    railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} || error "Failed to link to $service"
    
    # Deploy with all vars in ONE command
    if [ ${#VAR_ARGS[@]} -gt 0 ]; then
        log "Setting ${#VAR_ARGS[@]} variables and deploying..."
        railway up "${VAR_ARGS[@]}" || error "Deploy failed for $service"
    else
        railway up || error "Deploy failed for $service"
    fi
    success "$service deployed"
}

# Update URL variables after deployment
update_urls() {
    local backend_domain frontend_domain
    backend_domain=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    frontend_domain=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    [ -n "$backend_domain" ] && REFLEX_API_URL="https://$backend_domain"
    [ -n "$frontend_domain" ] && FRONTEND_DEPLOY_URL="https://$frontend_domain"
}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ SERVICE CREATION (FIRST-TIME ONLY)                                 ║
# ╚═══════════════════════════════════════════════════════════════════╝
create_postgres() {
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
    if [ "$POSTGRES_EXISTS" = false ] || [ "$BACKEND_EXISTS" = false ] || [ "$FRONTEND_EXISTS" = false ]; then
        create_postgres
        get_db_url
        create_service "$BACKEND_NAME"
        create_service "$FRONTEND_NAME"
        # Refresh service list
        railway list --json > "$DEPLOY_DIR/railway_services.json" 2>/dev/null || true
        pause
    fi
    
    # Run migrations
    run_migrations
    pause
    
    # Deploy backend first (frontend needs REFLEX_API_URL from backend)
    get_db_url
    set_vars_and_deploy "$BACKEND_NAME" "backend"
    
    # Get backend URL for frontend
    update_urls
    pause
    
    # Deploy frontend with REFLEX_API_URL
    set_vars_and_deploy "$FRONTEND_NAME" "frontend"
    
    # Final URL update (frontend may have generated domain)
    update_urls
    
    # Summary
    header "Deployment Complete"
    echo "✓ Backend:  $REFLEX_API_URL"
    echo "✓ Frontend: $FRONTEND_DEPLOY_URL"
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
  -y, --yes                Auto mode (skip pauses)
  -h, --help               Show this help

Examples:
  $0 -p my-project
  $0 -p my-project -b api -n web -y
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
        -y|--yes) AUTO_MODE=true; shift ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Validate
[ -z "$RAILWAY_PROJECT" ] && error "Project required. Use: $0 -p PROJECT"
[ -d "$DEPLOY_DIR" ] || error "Deploy dir not found: $DEPLOY_DIR"

# Load env file if exists
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

# Show config
header "Railway Deployment"
echo "Project: $RAILWAY_PROJECT | Env: $RAILWAY_ENVIRONMENT"
echo "Backend: $BACKEND_NAME | Frontend: $FRONTEND_NAME"
[ -n "$RAILWAY_TEAM" ] && echo "Team: $RAILWAY_TEAM"

# Run deployment
deploy
