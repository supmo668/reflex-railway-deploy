#!/bin/bash
# deploy_all.sh - Unified Railway deployment script for Reflex applications
# 
# This script intelligently handles both initial deployments and subsequent redeployments:
# - For new projects: Creates PostgreSQL, frontend, and backend services, configures variables, runs migrations
# - For existing projects: Updates environment variables and deploys services with fresh configs
# - Always copies fresh Caddyfile and nixpacks.toml files before deployment
# - Automatically detects which services exist to minimize unnecessary operations
# - ALWAYS deploys at least once with updated configuration files

set -e

# Colors and logging
if [ -t 1 ]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi
log() { echo "[INFO] $1"; }
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARNING] $1"; }
error() { echo "[ERROR] $1"; exit 1; }
header() { echo "================ $1 ================"; }

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
        log "Linking to Railway project: $RAILWAY_PROJECT"
        railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -t "$RAILWAY_TEAM" || error "Failed to link to Railway project"
    fi
    success "Railway project ready"
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

# Get and cache Railway services list
get_services_list() {
    local cache_file="$DEPLOY_DIR/railway_services.json"
    railway list --json > "$cache_file" 2>/dev/null || {
        warn "Failed to get services list"
        echo "[]" > "$cache_file"
    }
    echo "$cache_file"
}

# Check if service exists in Railway project
service_exists() {
    local service_name=$1
    local cache_file="$DEPLOY_DIR/railway_services.json"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    # Find the current project and get its environment ID for the target environment
    local env_id=$(jq -r --arg project "$RAILWAY_PROJECT" --arg env "$RAILWAY_ENVIRONMENT" '
        .[] | select(.name == $project) | .environments.edges[] | .node | select(.name == $env) | .id
    ' "$cache_file" 2>/dev/null)
    
    if [ -z "$env_id" ]; then
        return 1
    fi
    
    # Check if the service exists in the current project and has an instance in this environment
    if jq -e --arg project "$RAILWAY_PROJECT" --arg service "$service_name" --arg env_id "$env_id" '
        .[] | select(.name == $project) | .services.edges[] | .node |
        select(.name == $service) |
        select(.serviceInstances.edges[] | .node | .environmentId == $env_id)
    ' "$cache_file" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Check initialization status of all services
check_services_status() {
    FRONTEND_EXISTS=false
    BACKEND_EXISTS=false
    POSTGRES_EXISTS=false
    
    if [ "$FORCE_INIT" = true ]; then
        log "Force initialization flag set, treating all services as uninitialized"
        return 0
    fi

    # Get services list once and cache it
    log "Fetching Railway services list..."
    get_services_list > /dev/null

    # Check if services exist
    if [ "$SKIP_DB" = true ]; then
        POSTGRES_EXISTS=true
        log "Skipping PostgreSQL check (--skip-db enabled)"
    elif service_exists "Postgres"; then
        POSTGRES_EXISTS=true
        success "PostgreSQL service already exists"
    else
        log "PostgreSQL service does not exist"
    fi
    
    if service_exists "$FRONTEND_NAME"; then
        FRONTEND_EXISTS=true
        success "Frontend service $FRONTEND_NAME already exists"
    else
        log "Frontend service $FRONTEND_NAME does not exist"
    fi
    
    if service_exists "$BACKEND_NAME"; then
        BACKEND_EXISTS=true
        success "Backend service $BACKEND_NAME already exists"
    else
        log "Backend service $BACKEND_NAME does not exist"
    fi
}

# Deploy PostgreSQL
deploy_postgres() {
    if [ "$SKIP_DB" = true ]; then
        success "Skipping PostgreSQL deployment (--skip-db enabled)"
        return 0
    fi
    
    if [ "$POSTGRES_EXISTS" = true ]; then
        success "PostgreSQL already exists, skipping"
        return 0
    fi
    
    log "Adding PostgreSQL service..."
    railway add -d postgres || error "Failed to add PostgreSQL service"
    sleep 15
    success "PostgreSQL deployed"
}

# Setup environment variables
setup_vars() {
    # Handle database URL configuration
    if [ "$SKIP_DB" = true ]; then
        log "Using database URL from .env file (--skip-db enabled)"
        if [ -n "$REFLEX_DB_URL" ]; then
            export REFLEX_DB_URL
            log "Database URL configured from .env"
        else
            error "REFLEX_DB_URL not found in .env file. Required when using --skip-db option."
        fi
    else
        # Get database URLs from PostgreSQL service
        log "Getting database URLs from PostgreSQL service..."
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        DATABASE_PUBLIC_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
        
        if [ -n "$DATABASE_URL" ]; then
            export REFLEX_DB_URL="$DATABASE_URL"
            update_env "REFLEX_DB_URL" "$REFLEX_DB_URL" "$ENV_FILE"
            log "Database URL configured"
        fi
        
        if [ -n "$DATABASE_PUBLIC_URL" ]; then
            export DATABASE_PUBLIC_URL
            update_env "DATABASE_PUBLIC_URL" "$DATABASE_PUBLIC_URL" "$ENV_FILE"
            log "Public database URL configured"
        fi
    fi
}

# Run database migrations
run_migrations() {
    if [ "$SKIP_DB" = true ]; then
        log "Using database URL from .env for migrations"
        MIGRATION_URL="$REFLEX_DB_URL"
    else
        # Get latest database URLs from PostgreSQL service
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        DATABASE_PUBLIC_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
        MIGRATION_URL="${DATABASE_PUBLIC_URL:-$DATABASE_URL}"
    fi
    
    if [ -z "$MIGRATION_URL" ]; then
        warn "No database URL found, skipping migrations"
        return 0
    fi
    
    log "Running database migrations..."
    export DATABASE_URL="$MIGRATION_URL"
    
    # Run migrations
    REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db init || warn "Database initialization failed or was already done"
    REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db makemigrations || warn "Database update migration failed or was already done"
    REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db migrate || error "Database migrations failed"
    
    success "Database migrations completed"
}

# Create service if it doesn't exist
create_service() {
    local service_name=$1
    
    log "Creating service: $service_name"
    railway add -s "$service_name" || error "Failed to create $service_name service"
    success "$service_name service created"
    
    # Wait for service to be ready
    sleep 5
}

# Update service variables
update_service_vars() {
    local service_name=$1
    
    if [ ! -f "$DEPLOY_DIR/set_railway_vars.sh" ]; then
        warn "set_railway_vars.sh not found, skipping variable sync"
        return 0
    fi
    
    chmod +x "$DEPLOY_DIR/set_railway_vars.sh"
    
    log "Syncing variables to $service_name"
    # Exclude variables that are derived from other Railway services
    local exclude_vars="REFLEX_DB_URL,DATABASE_PUBLIC_URL,REFLEX_API_URL,FRONTEND_DEPLOY_URL"
    
    if output=$("$DEPLOY_DIR/set_railway_vars.sh" -s "$service_name" -f "$ENV_FILE" -e "$exclude_vars" 2>&1); then
        log "Variable sync completed for $service_name"
    else
        warn "Failed to sync variables to $service_name"
    fi
    
    # Set service-specific variables
    if [ "$service_name" = "$BACKEND_NAME" ] || [ "$service_name" = "$FRONTEND_NAME" ]; then
        # Set REFLEX_DB_URL
        if [ -n "$REFLEX_DB_URL" ]; then
            railway variables --service "$service_name" --set "REFLEX_DB_URL=$REFLEX_DB_URL" >/dev/null 2>&1 || warn "Failed to set REFLEX_DB_URL"
        fi
    fi
    
    if [ "$service_name" = "$FRONTEND_NAME" ]; then
        # Set REFLEX_API_URL for frontend from backend's domain
        local backend_domain=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
        if [ -n "$backend_domain" ]; then
            local api_url="https://$backend_domain"
            railway variables --service "$service_name" --set "REFLEX_API_URL=$api_url" >/dev/null 2>&1 || warn "Failed to set REFLEX_API_URL"
            log "REFLEX_API_URL set for frontend: $api_url"
        fi
    fi
    
    # Set FRONTEND_DEPLOY_URL for both services
    local frontend_domain=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    if [ -n "$frontend_domain" ]; then
        local frontend_url="https://$frontend_domain"
        railway variables --service "$service_name" --set "FRONTEND_DEPLOY_URL=$frontend_url" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL"
    fi
}

# Deploy service with proper configuration
deploy_service() {
    local service_name=$1
    local service_type=$2  # "backend" or "frontend"
    
    header "Deploying $service_type: $service_name"
    
    # Check if service exists
    local exists=false
    if [ "$service_name" = "$FRONTEND_NAME" ] && [ "$FRONTEND_EXISTS" = true ]; then
        exists=true
    elif [ "$service_name" = "$BACKEND_NAME" ] && [ "$BACKEND_EXISTS" = true ]; then
        exists=true
    fi
    
    # Create service if it doesn't exist
    if [ "$exists" = false ]; then
        create_service "$service_name"
        log "New service created, will deploy with configuration files"
    else
        log "Service already exists, will update configuration and redeploy"
    fi
    
    # Update service variables
    update_service_vars "$service_name"
    
    # Copy correct configuration files - ALWAYS do this
    log "Copying latest configuration files for $service_type"
    cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || error "Caddyfile.$service_type not found"
    cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || error "nixpacks.$service_type.toml not found"
    log "Configuration files copied successfully"
    
    # Deploy using railway up - ALWAYS deploy to ensure latest config is used
    log "Deploying $service_name with railway up (ensuring latest configuration is applied)"
    railway up --service "$service_name" || error "Failed to deploy $service_name"
    
    success "$service_type deployed successfully with latest configuration"
}

# Main deployment function
deploy_all() {
    header "Deploying All Services"
    
    # Deploy backend first
    deploy_service "$BACKEND_NAME" "backend"
    
    # Wait for backend to be ready before deploying frontend
    pause_for_verification "Backend deployed with latest configuration. Ready to deploy frontend service."
    
    # Ensure backend domain is available for frontend's REFLEX_API_URL
    log "Ensuring backend domain is available..."
    railway domain --service "$BACKEND_NAME" >/dev/null 2>&1 || warn "Failed to generate backend domain"
    sleep 10
    
    # Update frontend variables with backend domain before deployment
    log "Updating frontend variables with backend domain..."
    local backend_domain=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    if [ -n "$backend_domain" ]; then
        local api_url="https://$backend_domain"
        railway variables --service "$FRONTEND_NAME" --set "REFLEX_API_URL=$api_url" >/dev/null 2>&1 || warn "Failed to set REFLEX_API_URL"
        log "REFLEX_API_URL updated for frontend: $api_url"
    fi
    
    # Deploy frontend
    deploy_service "$FRONTEND_NAME" "frontend"
    
    # Final URL summary
    header "Deployment Complete"
    backend_domain=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    local frontend_domain=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    [ -n "$frontend_domain" ] && echo "✓ Frontend: https://$frontend_domain"
    [ -n "$backend_domain" ] && echo "✓ Backend: https://$backend_domain"
    [ "$SKIP_DB" = false ] && echo "✓ PostgreSQL: Database running"
    
    echo ""
    echo "All services have been deployed with the latest configuration files."
    echo "Both Caddyfile and nixpacks.toml have been updated and applied."
}

# Main execution
ENV_FILE=".env"
DEPLOY_DIR="reflex-railway-deploy"
FORCE_INIT=false
SKIP_DB=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) 
            echo "Usage: $0 -p PROJECT [BACKEND_NAME] [FRONTEND_NAME] [OPTIONS]"
            echo ""
            echo "Positional Arguments:"
            echo "  BACKEND_NAME              Name of backend service (default: backend)"
            echo "  FRONTEND_NAME             Name of frontend service (default: frontend)"
            echo ""
            echo "Required Options:"
            echo "  -p, --project PROJECT     Railway project ID or name (required)"
            echo ""
            echo "Optional Options:"
            echo "  -t, --team TEAM          Railway team (default: personal)"
            echo "  -e, --environment ENV    Railway environment (default: production)"
            echo "  -f, --file FILE          Environment file to use (default: .env)"
            echo "  -d, --deploy-dir DIR     Deploy directory (default: reflex-railway-deploy)"
            echo "      --force-init         Force re-initialization even if services exist"
            echo "      --skip-db            Skip PostgreSQL initialization, use REFLEX_DB_URL from .env"
            echo ""
            echo "Examples:"
            echo "  $0 -p my-project                              # Use default service names"
            echo "  $0 -p my-project api web                      # Custom service names"
            echo "  $0 -p my-project backend frontend -t my-team  # With team"
            echo "  $0 -p my-project --skip-db                    # Skip PostgreSQL, use .env REFLEX_DB_URL"
            exit 0 ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -t|--team) RAILWAY_TEAM="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --force-init) FORCE_INIT=true; shift ;;
        --skip-db) SKIP_DB=true; shift ;;
        -*) error "Unknown option: $1" ;;
        *) 
            # Handle positional arguments
            if [ -z "$BACKEND_NAME_ARG" ]; then
                BACKEND_NAME_ARG="$1"
            elif [ -z "$FRONTEND_NAME_ARG" ]; then
                FRONTEND_NAME_ARG="$1"
            else
                error "Too many positional arguments: $1"
            fi
            shift ;;
    esac
done

# Validate required arguments
[ -z "$RAILWAY_PROJECT" ] && error "Railway project is required. Use -p PROJECT"

# Validate and load environment
[ -f "$ENV_FILE" ] || error "Environment file $ENV_FILE not found"
[ -d "$DEPLOY_DIR" ] || error "Deploy directory $DEPLOY_DIR not found"

if [ -s "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" || error "Failed to source $ENV_FILE"; set +a
fi

# Set defaults
APP_NAME=${REFLEX_APP_NAME:-$(basename "$PWD")}
BACKEND_NAME=${BACKEND_NAME_ARG:-${BACKEND_NAME:-"backend"}}
FRONTEND_NAME=${FRONTEND_NAME_ARG:-${FRONTEND_NAME:-"frontend"}}
RAILWAY_ENVIRONMENT=${RAILWAY_ENVIRONMENT:-"production"}
RAILWAY_TEAM=${RAILWAY_TEAM:-"prototype"}

# Show configuration
header "Railway Deployment for $APP_NAME"
echo "Project: $RAILWAY_PROJECT"
echo "Team: $RAILWAY_TEAM"
echo "Environment: $RAILWAY_ENVIRONMENT"
echo "Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME"
echo "Skip DB: $SKIP_DB"

# Main deployment flow
validate_env
pause_for_verification "Environment validation complete. Ready to initialize Railway project."

init_project
pause_for_verification "Railway project initialization complete. Ready to check service status."

check_services_status
pause_for_verification "Service status checked. Ready to proceed with deployment."

# Deploy PostgreSQL if needed
deploy_postgres
if [ "$POSTGRES_EXISTS" = false ] && [ "$SKIP_DB" = false ]; then
    pause_for_verification "PostgreSQL deployed. Ready to setup environment variables."
fi

# Setup environment variables
setup_vars
pause_for_verification "Environment variables configured. Ready to run database migrations."

# Run migrations
run_migrations
pause_for_verification "Database migrations complete. Ready to deploy services."

# Deploy all services
deploy_all