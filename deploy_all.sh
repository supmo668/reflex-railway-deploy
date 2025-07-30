#!/bin/bash
# deploy_all.sh - Unified Railway deployment script for Reflex applications
# 
# This script intelligently handles both initial deployments and subsequent redeployments:
# - For new projects: Creates PostgreSQL, frontend, and backend services, configures variables, runs migrations
# - For existing projects: Runs migrations and deploys services with fresh configs
# - Always copies fresh Caddyfile and nixpacks.toml files before deployment
# - Automatically detects which services exist to minimize unnecessary operations

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

# Build environment variable string for Railway service creation
build_env_vars() {
    local service_type=$1
    local env_vars=""
    
    # Add ALL variables from .env file
    if [ -f "$ENV_FILE" ]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Skip Railway-derived variables that will be set later
            case "$key" in
                REFLEX_DB_URL|DATABASE_PUBLIC_URL|REFLEX_API_URL|FRONTEND_DEPLOY_URL)
                    continue
                    ;;
            esac
            
            # Remove quotes if present and add to env_vars
            clean_value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//')
            if [ -n "$clean_value" ]; then
                env_vars="${env_vars} --variables \"${key}=${clean_value}\""
            fi
        done < "$ENV_FILE"
    fi
    
    # Clean up any leading/trailing spaces
    env_vars=$(echo "$env_vars" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$env_vars"
}

# Setup Railway variables and database
setup_vars() {
    # Service configuration
    BACKEND_NAME=${BACKEND_NAME:-"backend"}
    FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
    
    # Handle database URL configuration
    if [ "$SKIP_DB" = true ]; then
        # Use REFLEX_DB_URL from .env file when --skip-db is enabled
        log "Using database URL from .env file (--skip-db enabled)"
        if [ -n "$REFLEX_DB_URL" ]; then
            export REFLEX_DB_URL
            log "Database URL configured from .env: $REFLEX_DB_URL"
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
            log "Database URL configured: $REFLEX_DB_URL"
        else
            warn "DATABASE_URL not available yet, will be retrieved after PostgreSQL setup"
        fi
        
        if [ -n "$DATABASE_PUBLIC_URL" ]; then
            export DATABASE_PUBLIC_URL
            update_env "DATABASE_PUBLIC_URL" "$DATABASE_PUBLIC_URL" "$ENV_FILE"
            log "Public database URL configured for migrations"
        else
            warn "DATABASE_PUBLIC_URL not available yet, will be retrieved after PostgreSQL setup"
        fi
    fi
    
    log "Variables configured: Backend=$BACKEND_NAME, Frontend=$FRONTEND_NAME"
}

# Run database migrations
run_migrations() {
    log "Running database migrations..."
    
    if [ "$SKIP_DB" = false ]; then
        # Always get the latest database URLs from PostgreSQL service
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        DATABASE_PUBLIC_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
        
        # Update .env file with latest database URLs
        if [ -n "$DATABASE_URL" ]; then
            update_env "REFLEX_DB_URL" "$DATABASE_URL" "$ENV_FILE"
        fi
        if [ -n "$DATABASE_PUBLIC_URL" ]; then
            update_env "DATABASE_PUBLIC_URL" "$DATABASE_PUBLIC_URL" "$ENV_FILE"
        fi
    fi
    
    # Use DATABASE_PUBLIC_URL for migrations if available, otherwise fall back to DATABASE_URL or REFLEX_DB_URL
    MIGRATION_URL="${DATABASE_PUBLIC_URL:-${DATABASE_URL:-$REFLEX_DB_URL}}"
    
    if [ -z "$MIGRATION_URL" ]; then
        warn "No database URL found, skipping migrations"
        return 0
    fi
    
    log "Running database setup with URL: ${MIGRATION_URL:0:20}..."
    export DATABASE_URL="$MIGRATION_URL"
    
    # Run migrations
    log "Initializing database..."
    if REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db init; then
        success "Database initialization completed"
    else
        warn "Database initialization failed or was already done"
    fi
    log "Updating database migrations..."
    if REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db makemigrations; then
        success "Database update migration completed"
    else
        warn "Database update migration failed or was already done"
    fi    
    log "Running database migrations..."
    if REFLEX_DB_URL="$MIGRATION_URL" uv run reflex db migrate; then
        success "Database migrations completed successfully"
    else
        error "Database migrations failed"
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

# Check if service exists in Railway project using cached list for the current environment
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

    # Get services list once and cache it
    log "Fetching Railway services list..."
    get_services_list > /dev/null

    # Check if services exist
    POSTGRES_SERVICE_NAME="Postgres"
    if [ "$SKIP_DB" = true ]; then
        POSTGRES_EXISTS=true
        log "Skipping PostgreSQL check (--skip-db enabled), using REFLEX_DB_URL from .env"
    elif service_exists "$POSTGRES_SERVICE_NAME"; then
        POSTGRES_EXISTS=true
        success "PostgreSQL service $POSTGRES_SERVICE_NAME already exists"
    else
        log "PostgreSQL service $POSTGRES_SERVICE_NAME does not exist"
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
    
    # Summary of what will be done
    if [ "$POSTGRES_EXISTS" = true ] && [ "$FRONTEND_EXISTS" = true ] && [ "$BACKEND_EXISTS" = true ]; then
        success "All services exist. Will update and deploy with latest configuration."
    else
        log "Some services need to be created:"
        [ "$POSTGRES_EXISTS" = false ] && log "  - PostgreSQL will be created"
        [ "$FRONTEND_EXISTS" = false ] && log "  - Frontend service $FRONTEND_NAME will be created"
        [ "$BACKEND_EXISTS" = false ] && log "  - Backend service $BACKEND_NAME will be created"
    fi
}

# Create service with environment variables
create_service() {
    local service_name=$1
    local service_type=$2
    
    log "Creating service: $service_name"
    
    # Build environment variables string
    local env_vars=$(build_env_vars "$service_type")
    
    # Create service with all variables in one command
    if [ -n "$env_vars" ]; then
        eval "railway add -s \"$service_name\" $env_vars" || error "Failed to create $service_name service"
    else
        railway add -s "$service_name" || error "Failed to create $service_name service"
    fi
    
    log "$service_name service created"
}

# Deploy service
deploy_service() {
    local service_name=$1 service_type=$2
    
    log "Deploying $service_type: $service_name"
    
    # Copy config files from deployment directory to current application directory
    cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || error "Caddyfile.$service_type not found"
    cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || error "nixpacks.$service_type.toml not found"
    
    # Check if service exists
    local service_exists_flag=false
    if [ "$service_name" = "$FRONTEND_NAME" ] && [ "$FRONTEND_EXISTS" = true ]; then
        service_exists_flag=true
    elif [ "$service_name" = "$BACKEND_NAME" ] && [ "$BACKEND_EXISTS" = true ]; then
        service_exists_flag=true
    fi
    
    # Deploy the service
    if [ "$service_exists_flag" = true ]; then
        log "Service already exists, setting service context and deploying..."
        railway service "$service_name" || error "Failed to set service to $service_name"
        railway up || error "Failed to deploy existing service $service_name"
    else
        # For new services, create and deploy in one go
        log "Creating new service $service_name and deploying..."
        railway up --service "$service_name" || error "Failed to create and deploy new service $service_name"
    fi
    
    success "$service_type deployed"
}

# Get deployment URLs
get_deployment_urls() {
    log "Getting deployment URLs..."
    
    # Ensure domains exist
    railway domain --service "$BACKEND_NAME" >/dev/null 2>&1 || warn "Failed to generate backend public domain"
    railway domain --service "$FRONTEND_NAME" >/dev/null 2>&1 || warn "Failed to generate frontend public domain"

    # Get domains from RAILWAY_PUBLIC_DOMAIN environment variable
    BACKEND_DOMAIN=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    FRONTEND_DOMAIN=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    # Update URLs if available
    if [ -n "$BACKEND_DOMAIN" ]; then
        REFLEX_API_URL="https://$BACKEND_DOMAIN"
        update_env "REFLEX_API_URL" "$REFLEX_API_URL" "$ENV_FILE"
        log "Backend API URL: $REFLEX_API_URL"
    fi
    
    if [ -n "$FRONTEND_DOMAIN" ]; then
        FRONTEND_DEPLOY_URL="https://$FRONTEND_DOMAIN"
        update_env "FRONTEND_DEPLOY_URL" "$FRONTEND_DEPLOY_URL" "$ENV_FILE"
        log "Frontend URL: $FRONTEND_DEPLOY_URL"
    fi
}

# Set Railway-derived variables for services
set_railway_variables() {
    local service_name=$1
    local variables=""
    
    # Always set REFLEX_DB_URL from PostgreSQL service
    if [ "$SKIP_DB" = false ] && [ -n "$DATABASE_URL" ]; then
        variables="${variables} \"REFLEX_DB_URL=$DATABASE_URL\""
    fi
    
    # Set REFLEX_API_URL for frontend service
    if [ "$service_name" = "$FRONTEND_NAME" ] && [ -n "$BACKEND_DOMAIN" ]; then
        REFLEX_API_URL="https://$BACKEND_DOMAIN"
        variables="${variables} \"REFLEX_API_URL=$REFLEX_API_URL\""
    fi
    
    # Set FRONTEND_DEPLOY_URL for both services
    if [ -n "$FRONTEND_DOMAIN" ]; then
        FRONTEND_DEPLOY_URL="https://$FRONTEND_DOMAIN"
        variables="${variables} \"FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL\""
    fi
    
    # Set all variables in one command if any exist
    if [ -n "$variables" ]; then
        eval "railway variables --service \"$service_name\" --set $variables" || warn "Failed to set variables for $service_name"
    fi
}

# Deploy all services
deploy_all() {
    header "Deploying Services"
    
    # Create services if they don't exist
    if [ "$FRONTEND_EXISTS" = false ]; then
        create_service "$FRONTEND_NAME" "frontend"
    fi
    
    if [ "$BACKEND_EXISTS" = false ]; then
        create_service "$BACKEND_NAME" "backend"
    fi
    
    # Wait for services to be ready
    if [ "$FRONTEND_EXISTS" = false ] || [ "$BACKEND_EXISTS" = false ]; then
        log "Waiting for new services to be ready..."
        sleep 10
    fi
    
    # Get deployment URLs
    get_deployment_urls
    
    # Set Railway-derived variables for all services
    log "Setting Railway-derived variables..."
    set_railway_variables "$BACKEND_NAME"
    set_railway_variables "$FRONTEND_NAME"
    
    # Deploy backend
    deploy_service "$BACKEND_NAME" "backend"
    
    # Pause before frontend deployment
    pause_for_verification "Backend deployed. Ready to deploy frontend service."
    
    # Deploy frontend
    deploy_service "$FRONTEND_NAME" "frontend"
    
    success "All services deployed"
}

# Main execution
ENV_FILE=".env" DEPLOY_DIR="reflex-railway-deploy" SKIP_DB=false

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
            echo "  -p, --project PROJECT      Railway project ID or name (required)"
            echo ""
            echo "Optional Options:"
            echo "  -t, --team TEAM           Railway team (default: personal)"
            echo "  -e, --environment ENV     Railway environment (default: production)"
            echo "  -f, --file FILE           Environment file to use (default: .env)"
            echo "  -d, --deploy-dir DIR      Deploy directory (default: reflex-railway-deploy)"
            echo "      --skip-db             Skip PostgreSQL initialization, use REFLEX_DB_URL from .env"
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

# Set defaults (after loading .env)
APP_NAME=${REFLEX_APP_NAME:-$(basename "$PWD")}
BACKEND_NAME=${BACKEND_NAME_ARG:-${BACKEND_NAME:-"backend"}}
FRONTEND_NAME=${FRONTEND_NAME_ARG:-${FRONTEND_NAME:-"frontend"}}
RAILWAY_ENVIRONMENT=${RAILWAY_ENVIRONMENT:-"production"}
RAILWAY_TEAM=${RAILWAY_TEAM:-"prototype"}

# Show config and deploy
header "Railway Deployment for $APP_NAME"
echo "Project: $RAILWAY_PROJECT"
echo "Team: $RAILWAY_TEAM"
echo "Environment: $RAILWAY_ENVIRONMENT"
echo "Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME"

# Main deployment flow
validate_env
pause_for_verification "Environment validation complete. Ready to initialize Railway project."

init_project
pause_for_verification "Railway project initialization complete. Ready to check service status."

check_services_status

if [ "$POSTGRES_EXISTS" = false ]; then
    pause_for_verification "PostgreSQL service needs to be created. Ready to deploy PostgreSQL."
    deploy_postgres
fi

pause_for_verification "Ready to setup environment variables."
setup_vars

pause_for_verification "Environment variables setup complete. Ready to run database migrations."
run_migrations

pause_for_verification "Database migrations complete. Ready to deploy all services."
deploy_all

# Summary
header "Deployment Complete"
echo "✓ Frontend: https://$FRONTEND_DOMAIN"
echo "✓ Backend: https://$BACKEND_DOMAIN" 
if [ "$SKIP_DB" = false ]; then
    echo "✓ PostgreSQL: Database running"
fi
echo ""
echo "Commands used: railway list | railway status | railway add | railway up | railway variables --service <name> --set"