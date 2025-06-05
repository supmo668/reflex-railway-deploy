#!/bin/bash
# deploy_all.sh - Deploy Reflex application to Railway

set -e

# Colors and logging
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "${BLUE}================ $1 ================${NC}"; }

# Validate environment
validate_env() {
    command -v railway &> /dev/null || error "Railway CLI not found. Install with: npm i -g @railway/cli"
    railway whoami &> /dev/null || error "Not logged in to Railway. Run 'railway login' first"
    success "Environment validated"
}

# Initialize Railway project
init_project() {
    if ! railway status &> /dev/null; then
        log "Creating Railway project..."
        railway init || error "Failed to initialize Railway project"
    fi
    success "Railway project ready"
}

# Deploy PostgreSQL
deploy_postgres() {
    [ "$ENABLE_POSTGRES" = false ] && { log "PostgreSQL skipped"; return 0; }
    
    if railway service list 2>/dev/null | grep -q "Postgres"; then
        success "PostgreSQL already exists"
        return 0
    fi
    
    log "Adding PostgreSQL service..."
    railway add -d postgres || error "Failed to add PostgreSQL service"
    sleep 15
    success "PostgreSQL deployed"
}

# Update environment variable in .env file
update_env() {
    local var_name=$1 var_value=$2 env_file=$3
    [ -z "$var_name" ] || [ -z "$var_value" ] || [ -z "$env_file" ] && { error "update_env: Missing parameters"; }
    
    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    else
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Setup Railway variables and database
setup_vars() {
    # Service configuration
    BACKEND_NAME=${BACKEND_NAME:-"backend"}
    FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
    RAILWAY_ENVIRONMENT=$(railway status --json 2>/dev/null | jq -r '.environment.name // "production"' 2>/dev/null || echo "production")
    
    # Set URLs
    export REFLEX_API_URL="http://${BACKEND_NAME}.railway.internal:8080"
    export FRONTEND_DEPLOY_URL="https://${FRONTEND_NAME}-${RAILWAY_ENVIRONMENT}.up.railway.app"
    
    # Get database URL if PostgreSQL enabled
    if [ "$ENABLE_POSTGRES" = true ]; then
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        if [ -n "$DATABASE_URL" ]; then
            export DATABASE_URL REFLEX_DB_URL="$DATABASE_URL"
            update_env "REFLEX_DB_URL" "$REFLEX_DB_URL" "$ENV_FILE"
        fi
    fi
    
    # Update .env with all variables
    update_env "REFLEX_API_URL" "$REFLEX_API_URL" "$ENV_FILE"
    update_env "FRONTEND_DEPLOY_URL" "$FRONTEND_DEPLOY_URL" "$ENV_FILE"
    
    log "Variables configured: Backend=$BACKEND_NAME, Frontend=$FRONTEND_NAME"
}

# Run database migrations
run_migrations() {
    [ "$ENABLE_POSTGRES" = false ] || [ -z "$DATABASE_URL" ] && return 0
    
    log "Running database setup..."
    export DATABASE_URL
    REFLEX_DB_URL=$DATABASE_URL reflex db init 2>/dev/null || true
    REFLEX_DB_URL=$DATABASE_URL reflex db migrate 2>/dev/null || true
    success "Database ready"
}

# Create and configure services
setup_services() {
    log "Creating Railway services..."
    
    # Create services if they don't exist
    for service in "$FRONTEND_NAME" "$BACKEND_NAME"; do
        if ! railway service list 2>/dev/null | grep -q "$service"; then
            railway add --service "$service" || error "Failed to create $service service"
        fi
    done
    
    # Sync variables to Railway services
    chmod +x "$DEPLOY_DIR/set_railway_vars.sh" 2>/dev/null || error "set_railway_vars.sh not found in $DEPLOY_DIR"
    
    for service in "$BACKEND_NAME" "$FRONTEND_NAME"; do
        "$DEPLOY_DIR/set_railway_vars.sh" -s "$service" -f "$ENV_FILE" || error "Failed to sync variables to $service"
    done
    
    success "Services configured"
}

# Deploy service
deploy_service() {
    local service_name=$1 service_type=$2
    
    log "Deploying $service_type: $service_name"
    
    # Copy config files
    cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || error "Caddyfile.$service_type not found"
    cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || error "nixpacks.$service_type.toml not found"
    
    # Deploy
    railway service "$service_name" || error "Failed to select $service_name"
    railway up || error "Failed to deploy $service_name"
    
    success "$service_type deployed"
}

# Update frontend URL after deployment
update_frontend_url() {
    sleep 5
    REFLEX_PUBLIC_DOMAIN=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.REFLEX_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    if [ -n "$REFLEX_PUBLIC_DOMAIN" ]; then
        export FRONTEND_DEPLOY_URL="https://$REFLEX_PUBLIC_DOMAIN"
        update_env "FRONTEND_DEPLOY_URL" "$FRONTEND_DEPLOY_URL" "$ENV_FILE"
        "$DEPLOY_DIR/set_railway_vars.sh" -s "$BACKEND_NAME" -f "$ENV_FILE" 2>/dev/null || warn "Failed to update backend with new frontend URL"
        success "Frontend URL updated: $FRONTEND_DEPLOY_URL"
    fi
}

# Deploy all services
deploy_all() {
    log "Deploying services..."
    deploy_service "$BACKEND_NAME" "backend"
    deploy_service "$FRONTEND_NAME" "frontend"
    update_frontend_url
    success "All services deployed"
}

# Main execution
ENV_FILE=".env" DEPLOY_DIR="reflex-railway-deploy" ENABLE_POSTGRES=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) echo "Usage: $0 [-f file] [-d dir] [--no-postgres]"; exit 0 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --no-postgres) ENABLE_POSTGRES=false; shift ;;
        --postgres) ENABLE_POSTGRES=true; shift ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Validate and load environment
[ -f "$ENV_FILE" ] || error "Environment file $ENV_FILE not found"
[ -d "$DEPLOY_DIR" ] || error "Deploy directory $DEPLOY_DIR not found"

if [ -s "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" || error "Failed to source $ENV_FILE"; set +a
fi

# Set defaults
REFLEX_APP_NAME=${REFLEX_APP_NAME:-"reflex_railway_deployment"}
FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
BACKEND_NAME=${BACKEND_NAME:-"backend"}

# Show config and deploy
header "Reflex Railway Deployment"
echo "App: $REFLEX_APP_NAME | Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME | PostgreSQL: $([ "$ENABLE_POSTGRES" = true ] && echo "Enabled" || echo "Disabled")"

validate_env
init_project
deploy_postgres
setup_vars
run_migrations
setup_services
deploy_all

# Summary
header "Deployment Complete"
echo "✓ Frontend: https://$FRONTEND_NAME.up.railway.app"
echo "✓ Backend: https://$BACKEND_NAME.up.railway.app"
[ "$ENABLE_POSTGRES" = true ] && echo "✓ PostgreSQL: Database running"
echo "Commands: railway status | railway logs --service <name> | railway variables --service <name>"
