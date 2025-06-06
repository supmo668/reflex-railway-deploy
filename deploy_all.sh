#!/bin/bash
# deploy_all.sh - Deploy Reflex application to Railway
# 
# This script intelligently handles both initial deployments and subsequent redeployments:
# - For new services: Creates services, sets up PostgreSQL, configures variables, runs migrations
# - For existing services: Skips initialization steps and directly deploys with updated configs
# - Always copies fresh Caddyfile and nixpacks.toml files before deployment

set -e

# Colors and logging
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "${BLUE}================ $1 ================${NC}"; }

# Interactive pause function
pause_for_verification() {
    local message="$1"
    echo -e "${YELLOW}[PAUSE]${NC} $message"
    echo -e "${YELLOW}Press ENTER to continue or Ctrl+C to exit...${NC}"
    read -r
}

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
    
    # Get database URL if PostgreSQL enabled
    if [ "$ENABLE_POSTGRES" = true ]; then
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        if [ -n "$DATABASE_URL" ]; then
            export REFLEX_DB_URL="$DATABASE_URL"
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

# Check if service is already initialized (has deployments)
is_service_initialized() {
    local service_name=$1
    local deployment_count=$(railway deployments --service "$service_name" --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
    [ "$deployment_count" -gt 0 ]
}

# Check initialization status of all services
check_services_status() {
    FRONTEND_INITIALIZED=false
    BACKEND_INITIALIZED=false
    
    if [ "$FORCE_INIT" = true ]; then
        log "Force initialization flag set, treating all services as uninitialized"
        SERVICES_NEED_INIT=true
        return 0
    fi
    
    if railway service list 2>/dev/null | grep -q "$FRONTEND_NAME"; then
        if is_service_initialized "$FRONTEND_NAME"; then
            FRONTEND_INITIALIZED=true
            success "Frontend service already initialized"
        else
            log "Frontend service exists but not deployed yet"
        fi
    fi
    
    if railway service list 2>/dev/null | grep -q "$BACKEND_NAME"; then
        if is_service_initialized "$BACKEND_NAME"; then
            BACKEND_INITIALIZED=true
            success "Backend service already initialized"
        else
            log "Backend service exists but not deployed yet"
        fi
    fi
    
    # Set global flag for whether any services need initialization
    SERVICES_NEED_INIT=false
    if [ "$FRONTEND_INITIALIZED" = false ] || [ "$BACKEND_INITIALIZED" = false ]; then
        SERVICES_NEED_INIT=true
    fi
}

# Create and configure services (only if needed)
setup_services() {
    if [ "$SERVICES_NEED_INIT" = false ]; then
        success "All services already initialized, skipping setup"
        return 0
    fi
    
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

# Function to link Railway project and set environment
setup_railway_project() {
    header "Linking Railway Project and Setting Environment"

    if [ -z "$RAILWAY_PROJECT_ID" ]; then
        error "RAILWAY_PROJECT_ID is not set. Please define it in your $ENV_FILE."
    fi

    local env_name="${RAILWAY_ENVIRONMENT_NAME:-production}"

    log "Linking to Railway project $RAILWAY_PROJECT_ID..."
    railway link "$RAILWAY_PROJECT_ID" || error "Failed to link Railway project. Make sure you are logged in (railway login) and the project ID is correct."

    log "Setting Railway environment to $env_name..."
    railway environment "$env_name" || error "Failed to set Railway environment. Make sure the environment exists or can be created."

    success "Railway project linked and environment set to $env_name."
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

# Update deployment URLs after services are deployed
update_deployment_urls() {
    log "Getting deployment URLs..."
    
    # Get backend domain
    BACKEND_DOMAIN=$(railway domain --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    if [ -z "$BACKEND_DOMAIN" ]; then
        log "Generating domain for backend service..."
        railway domain --service "$BACKEND_NAME" >/dev/null 2>&1 || warn "Failed to generate backend domain"
        sleep 3
        BACKEND_DOMAIN=$(railway domain --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    fi
    
    # Get frontend domain  
    FRONTEND_DOMAIN=$(railway domain --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    if [ -z "$FRONTEND_DOMAIN" ]; then
        log "Generating domain for frontend service..."
        railway domain --service "$FRONTEND_NAME" >/dev/null 2>&1 || warn "Failed to generate frontend domain"
        sleep 3
        FRONTEND_DOMAIN=$(railway domain --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    fi
    
    # Update environment variables only if services were newly initialized
    if [ "$SERVICES_NEED_INIT" = true ]; then
        if [ -n "$BACKEND_DOMAIN" ]; then
            REFLEX_API_URL="https://$BACKEND_DOMAIN"
            update_env "REFLEX_API_URL" "$REFLEX_API_URL" "$ENV_FILE"
            # Set for frontend service
            railway variables --service "$FRONTEND_NAME" --set "REFLEX_API_URL=$REFLEX_API_URL" >/dev/null 2>&1 || warn "Failed to set REFLEX_API_URL on frontend"
        fi
        
        if [ -n "$FRONTEND_DOMAIN" ]; then
            FRONTEND_DEPLOY_URL="https://$FRONTEND_DOMAIN"
            update_env "FRONTEND_DEPLOY_URL" "$FRONTEND_DEPLOY_URL" "$ENV_FILE"
            # Set for both services
            railway variables --service "$BACKEND_NAME" --set "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL on backend"
            railway variables --service "$FRONTEND_NAME" --set "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL on frontend"
        fi
    else
        log "Services already initialized, skipping environment variable updates"
        # Just get URLs for display purposes
        if [ -n "$BACKEND_DOMAIN" ]; then
            REFLEX_API_URL="https://$BACKEND_DOMAIN"
        fi
        if [ -n "$FRONTEND_DOMAIN" ]; then
            FRONTEND_DEPLOY_URL="https://$FRONTEND_DOMAIN"
        fi
    fi
    
    success "Deployment URLs configured"
}
        railway variables --service "$FRONTEND_NAME" --set "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL on frontend"
    fi
    
    success "Deployment URLs configured"
}

# Deploy all services
deploy_all() {
    log "Deploying services..."
    deploy_service "$BACKEND_NAME" "backend"
    deploy_service "$FRONTEND_NAME" "frontend"
    update_deployment_urls
    success "All services deployed"
}

# Main execution
ENV_FILE=".env" DEPLOY_DIR="reflex-railway-deploy" ENABLE_POSTGRES=true FORCE_INIT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) 
            echo "Usage: $0 [-f file] [-d dir] [--no-postgres] [--force-init]"
            echo "  -f, --file FILE        Environment file to use (default: .env)"
            echo "  -d, --deploy-dir DIR   Deploy directory (default: reflex-railway-deploy)"
            echo "  --no-postgres          Skip PostgreSQL deployment"
            echo "  --postgres             Enable PostgreSQL deployment (default)"
            echo "  --force-init           Force re-initialization even if services exist"
            exit 0 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --no-postgres) ENABLE_POSTGRES=false; shift ;;
        --postgres) ENABLE_POSTGRES=true; shift ;;
        --force-init) FORCE_INIT=true; shift ;;
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
echo "App: $REFLEX_APP_NAME | Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME"
echo "PostgreSQL: $([ "$ENABLE_POSTGRES" = true ] && echo "Enabled" || echo "Disabled") | Force Init: $([ "$FORCE_INIT" = true ] && echo "Yes" || echo "No")"

# Main deployment flow
setup_railway_project
pause_for_verification "Railway project linked and environment set. Ready to proceed with variable setup."

validate_env
pause_for_verification "Environment validation complete. Ready to initialize Railway project."

init_project
pause_for_verification "Railway project initialization complete. Ready to check service status."

check_services_status
if [ "$SERVICES_NEED_INIT" = true ]; then
    pause_for_verification "Service status checked. Some services need initialization. Ready to deploy PostgreSQL (if enabled)."
    
    deploy_postgres
    pause_for_verification "PostgreSQL deployment complete. Ready to setup environment variables."
    
    setup_vars
    pause_for_verification "Environment variables setup complete. Ready to run database migrations."
    
    run_migrations
    pause_for_verification "Database migrations complete. Ready to setup Railway services."
    
    setup_services
    pause_for_verification "Railway services setup complete. Ready to deploy all services."
else
    log "All services already initialized. Skipping PostgreSQL, variables, migrations, and service setup."
    pause_for_verification "Service status checked. All services already initialized. Ready to deploy services."
fi

deploy_all

# Summary
header "Deployment Complete"
echo "✓ Frontend: https://$FRONTEND_DOMAIN"
echo "✓ Backend: https://$BACKEND_DOMAIN" 
[ "$ENABLE_POSTGRES" = true ] && echo "✓ PostgreSQL: Database running"
echo "Commands: railway status | railway logs --service <name> | railway variables --service <name>"
