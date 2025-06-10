#!/bin/bash
# deploy_all.sh - Unified Railway deployment script for Reflex applications
# 
# This script intelligently handles both initial deployments and subsequent redeployments:
# - For new projects: Creates PostgreSQL, frontend, and backend services, configures variables, runs migrations
# - For existing projects: Skips service creation and setup, only copies configs and # Show config and deploy
header "Railway Deployment for $APP_NAME"
echo "Project: $RAILWAY_PROJECT"
echo "Team: $RAILWAY_TEAM"
echo "Environment: $RAILWAY_ENVIRONMENT"
echo "Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME"
if [ "$ENABLE_POSTGRES" = true ]; then
    POSTGRES_STATUS="Enabled"
else
    POSTGRES_STATUS="Disabled"
fi
if [ "$FORCE_INIT" = true ]; then
    FORCE_STATUS="Yes"
else
    FORCE_STATUS="No"
fi
echo "PostgreSQL: $POSTGRES_STATUS | Force Init: $FORCE_STATUS"ys
# - Always copies fresh Caddyfile and nixpacks.toml files before deployment
# - Automatically detects which services exist to minimize unnecessary operations

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
    if [ "$ENABLE_POSTGRES" = false ]; then
        log "PostgreSQL deployment disabled"
        return 0
    fi
    
    if [ "$POSTGRES_NEED_INIT" = false ]; then
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

# Setup Railway variables and database
setup_vars() {
    if [ "$SERVICES_NEED_INIT" = false ]; then
        log "Services already exist, skipping variable setup"
        return 0
    fi
    
    # Service configuration
    BACKEND_NAME=${BACKEND_NAME:-"backend"}
    FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
    
    # Get database URL if PostgreSQL enabled
    if [ "$ENABLE_POSTGRES" = true ]; then
        DATABASE_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
        if [ -n "$DATABASE_URL" ]; then
            export REFLEX_DB_URL="$DATABASE_URL"
            update_env "REFLEX_DB_URL" "$REFLEX_DB_URL" "$ENV_FILE"
            log "Database URL configured: $REFLEX_DB_URL"
        else
            warn "DATABASE_URL not available yet, will be set during deployment URL update"
        fi
    fi
    
    # Note: REFLEX_API_URL and FRONTEND_DEPLOY_URL will be set later in update_deployment_urls()
    # after services are created and domains are available
    
    log "Variables configured: Backend=$BACKEND_NAME, Frontend=$FRONTEND_NAME"
}

# Run database migrations
run_migrations() {
    if [ "$ENABLE_POSTGRES" = false ]; then
        log "PostgreSQL disabled, skipping migrations"
        return 0
    fi
    
    if [ "$POSTGRES_NEED_INIT" = false ]; then
        log "PostgreSQL already exists, skipping migrations"
        return 0
    fi
    
    if [ -z "$DATABASE_URL" ]; then
        warn "No DATABASE_URL found, skipping migrations"
        return 0
    fi
    
    log "Running database setup..."
    export DATABASE_URL
    REFLEX_DB_URL=$DATABASE_URL reflex db init 2>/dev/null || true
    REFLEX_DB_URL=$DATABASE_URL reflex db migrate 2>/dev/null || true
    success "Database ready"
}

# Get and cache Railway services list
get_services_list() {
    local cache_file="$DEPLOY_DIR/railway_services.json"
    # Always create a new cache file for the run
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
    
    # Check if cache file exists and is readable
    if [ ! -f "$cache_file" ]; then
        return 1  # Failed to get service list
    fi
    
    # Parse the nested JSON structure to find services in the current environment
    # Structure: [{"name": "project", "environments": {"edges": [{"node": {"id": "env_id", "name": "env_name"}}]}, "services": {"edges": [{"node": {"name": "service", "serviceInstances": {"edges": [{"node": {"environmentId": "env_id"}}]}}}]}}]
    
    # Get all environment IDs for the target environment name across all projects
    local env_ids=$(jq -r --arg env "$RAILWAY_ENVIRONMENT" '
        .[] | .environments.edges[] | .node | select(.name == $env) | .id
    ' "$cache_file" 2>/dev/null)
    
    # If no environment ID found, service doesn't exist
    if [ -z "$env_ids" ]; then
        return 1
    fi
    
    # Check each environment ID for the service
    for env_id in $env_ids; do
        # Check if the service exists and has an instance in this environment
        if jq -e --arg service "$service_name" --arg env_id "$env_id" '
            .[] | .services.edges[] | .node |
            select(.name == $service) |
            select(.serviceInstances.edges[] | .node | .environmentId == $env_id)
        ' "$cache_file" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    return 1
}

# Check initialization status of all services
check_services_status() {
    FRONTEND_EXISTS=false
    BACKEND_EXISTS=false
    POSTGRES_EXISTS=false
    
    if [ "$FORCE_INIT" = true ]; then
        log "Force initialization flag set, treating all services as uninitialized"
        SERVICES_NEED_INIT=true
        POSTGRES_NEED_INIT=true
        return 0
    fi

    # Get services list once and cache it
    log "Fetching Railway services list..."
    get_services_list > /dev/null

    # Check if services exist
    POSTGRES_SERVICE_NAME="Postgres"
    if service_exists "$POSTGRES_SERVICE_NAME"; then
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
    
    # Set global flags for what needs initialization
    SERVICES_NEED_INIT=false
    POSTGRES_NEED_INIT=false
    
    if [ "$FRONTEND_EXISTS" = false ] || [ "$BACKEND_EXISTS" = false ]; then
        SERVICES_NEED_INIT=true
    fi
    
    if [ "$POSTGRES_EXISTS" = false ] && [ "$ENABLE_POSTGRES" = true ]; then
        POSTGRES_NEED_INIT=true
    fi
    
    # Summary of what will be done
    if [ "$SERVICES_NEED_INIT" = false ] && [ "$POSTGRES_NEED_INIT" = false ]; then
        success "All services exist. Will perform quick deployment only."
    else
        log "Some services need initialization:"
        [ "$POSTGRES_NEED_INIT" = true ] && log "  - PostgreSQL will be created"
        [ "$FRONTEND_EXISTS" = false ] && log "  - Frontend service $FRONTEND_NAME will be created"
        [ "$BACKEND_EXISTS" = false ] && log "  - Backend service $BACKEND_NAME will be created"
    fi
}

# Create and configure services (only if needed)
setup_services() {
    if [ "$SERVICES_NEED_INIT" = false ]; then
        success "All services already exist, skipping service creation and variable setup"
        return 0
    fi
    
    header "Linking Railway Project and Setting Up Services"
    
    # We need to create services, so we'll link when creating the first one
    local first_service_created=false
    local services_to_redeploy=()
    
    # Create PostgreSQL first if needed (this will establish Railway link)
    if [ "$POSTGRES_NEED_INIT" = true ]; then
        log "Adding PostgreSQL service..."
        railway add -d postgres -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -t "$RAILWAY_TEAM" || error "Failed to add PostgreSQL service"
        first_service_created=true
        sleep 15
        log "PostgreSQL service created and project linked"
    fi
    
    # Create other services if they don't exist
    for service in "$FRONTEND_NAME" "$BACKEND_NAME"; do
        if ! service_exists "$service"; then
            log "Creating service: $service"
            if [ "$first_service_created" = false ]; then
                # First service creation with Railway linking
                railway add --service "$service" -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -t "$RAILWAY_TEAM" || error "Failed to create $service service"
                first_service_created=true
                log "$service service created and project linked"
            else
                # Subsequent services (already linked)
                railway add --service "$service" || error "Failed to create $service service"
                log "$service service created"
            fi
            services_to_redeploy+=("$service")
        else
            log "Service already exists: $service"
        fi
    done
    
    # If all services existed, we need to link to one of them
    if [ "$first_service_created" = false ]; then
        local link_service=""
        if [ "$POSTGRES_EXISTS" = true ]; then
            link_service="Postgres"
        elif [ "$BACKEND_EXISTS" = true ]; then
            link_service="$BACKEND_NAME"  
        elif [ "$FRONTEND_EXISTS" = true ]; then
            link_service="$FRONTEND_NAME"
        fi
        
        if [ -n "$link_service" ]; then
            log "Linking to existing service: $link_service"
            railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -t "$RAILWAY_TEAM" -s "$link_service" || error "Failed to link to $link_service"
            log "Railway project linked successfully"
        fi
    fi
    
    # Wait for services to be ready before syncing variables
    if [ ${#services_to_redeploy[@]} -gt 0 ]; then
        log "Waiting for new services to be ready..."
        sleep 10
    fi
    
    # Sync variables to Railway services and redeploy newly created services
    if [ -f "$DEPLOY_DIR/set_railway_vars.sh" ]; then
        chmod +x "$DEPLOY_DIR/set_railway_vars.sh"
        
        for service in "$BACKEND_NAME" "$FRONTEND_NAME"; do
            log "Syncing variables to $service"
            "$DEPLOY_DIR/set_railway_vars.sh" -s "$service" -f "$ENV_FILE" || warn "Failed to sync variables to $service"
            
            # Redeploy if this service was newly created
            if [[ " ${services_to_redeploy[@]} " =~ " ${service} " ]]; then
                log "Redeploying $service with updated environment variables..."
                railway redeploy -s "$service" || warn "Failed to redeploy $service"
                success "$service redeployed with correct variables"
            fi
        done
    else
        warn "set_railway_vars.sh not found, skipping variable sync"
    fi
    
    success "Services configured"
}

# Deploy service
deploy_service() {
    local service_name=$1 service_type=$2
    
    log "Deploying $service_type: $service_name"
    
    # Copy config files
    cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || error "Caddyfile.$service_type not found"
    cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || error "nixpacks.$service_type.toml not found"
    
    # Set the service 
    railway service "$service_name" || error "Failed to set service to $service_name"

    # Deploy the service
    railway up || error "Failed to deploy $service_name"
    
    success "$service_type deployed"
}

# Update deployment URLs after services are deployed
update_deployment_urls() {
    log "Getting deployment URLs..."
    
    # Ensure backend public domain exists
    log "Ensuring backend public domain exists..."
    railway domain --service "$BACKEND_NAME" >/dev/null 2>&1 || warn "Failed to generate backend public domain"

    # Get backend domain from RAILWAY_PUBLIC_DOMAIN environment variable
    BACKEND_DOMAIN=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    if [ -z "$BACKEND_DOMAIN" ]; then
        warn "RAILWAY_PUBLIC_DOMAIN not available for backend service yet, will be set after redeployment"
        # Fallback to railway domain command as last resort
        BACKEND_DOMAIN=$(railway domain --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    fi

    # Create frontend domain if it doesn't exist
    log "Ensuring frontend domain exists..."
    railway domain --service "$FRONTEND_NAME" >/dev/null 2>&1 || warn "Failed to generate frontend domain"
    
    # Get frontend domain from RAILWAY_PUBLIC_DOMAIN environment variable
    FRONTEND_DOMAIN=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    if [ -z "$FRONTEND_DOMAIN" ]; then
        warn "RAILWAY_PUBLIC_DOMAIN not available for frontend service yet, will be set after redeployment"
        # Fallback to railway domain command as last resort
        FRONTEND_DOMAIN=$(railway domain --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.domain // empty' 2>/dev/null || echo "")
    fi
    
    # Update environment variables only if services were newly created
    if [ "$SERVICES_NEED_INIT" = true ]; then
        # If RAILWAY_PUBLIC_DOMAIN variables weren't available, redeploy services to make them available
        need_redeploy=false
        if [ -z "$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null)" ]; then
            log "RAILWAY_PUBLIC_DOMAIN not available for backend, triggering redeploy..."
            railway redeploy --service "$BACKEND_NAME" || warn "Failed to redeploy backend service"
            need_redeploy=true
        fi
        
        if [ -z "$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null)" ]; then
            log "RAILWAY_PUBLIC_DOMAIN not available for frontend, triggering redeploy..."
            railway redeploy --service "$FRONTEND_NAME" || warn "Failed to redeploy frontend service"
            need_redeploy=true
        fi
        
        # Wait for redeployment if needed
        if [ "$need_redeploy" = true ]; then
            log "Waiting for services to redeploy and RAILWAY_PUBLIC_DOMAIN to be available..."
            sleep 30
            
            # Get the domains again after redeploy
            BACKEND_DOMAIN=$(railway variables --service "$BACKEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
            FRONTEND_DOMAIN=$(railway variables --service "$FRONTEND_NAME" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
        fi
        
        if [ -n "$BACKEND_DOMAIN" ]; then
            REFLEX_API_URL="https://$BACKEND_DOMAIN"
            update_env "REFLEX_API_URL" "$REFLEX_API_URL" "$ENV_FILE"
            # Set for frontend service
            railway variables --service "$FRONTEND_NAME" --set "REFLEX_API_URL=$REFLEX_API_URL" >/dev/null 2>&1 || warn "Failed to set REFLEX_API_URL on frontend"
            log "Backend API URL set for frontend: $REFLEX_API_URL"
        fi
        
        if [ -n "$FRONTEND_DOMAIN" ]; then
            FRONTEND_DEPLOY_URL="https://$FRONTEND_DOMAIN"
            update_env "FRONTEND_DEPLOY_URL" "$FRONTEND_DEPLOY_URL" "$ENV_FILE"
            # Set for both services
            railway variables --service "$BACKEND_NAME" --set "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL on backend"
            railway variables --service "$FRONTEND_NAME" --set "FRONTEND_DEPLOY_URL=$FRONTEND_DEPLOY_URL" >/dev/null 2>&1 || warn "Failed to set FRONTEND_DEPLOY_URL on frontend"
            log "Frontend URL set: $FRONTEND_DEPLOY_URL"
        fi
    else
        log "Services already exist, getting URLs for display purposes only"
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
            echo "      --no-postgres         Skip PostgreSQL deployment"
            echo "      --postgres            Enable PostgreSQL deployment (default)"
            echo "      --force-init          Force re-initialization even if services exist"
            echo ""
            echo "Examples:"
            echo "  $0 -p my-project                              # Use default service names"
            echo "  $0 -p my-project api web                      # Custom service names"
            echo "  $0 -p my-project backend frontend -t my-team  # With team"
            exit 0 ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -t|--team) RAILWAY_TEAM="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --no-postgres) ENABLE_POSTGRES=false; shift ;;
        --postgres) ENABLE_POSTGRES=true; shift ;;
        --force-init) FORCE_INIT=true; shift ;;
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
RAILWAY_TEAM=${RAILWAY_TEAM:-"personal"}

# Show config and deploy
header "Railway Deployment for $APP_NAME"
echo "Project ID: $RAILWAY_PROJECT_ID"
echo "Frontend: $FRONTEND_NAME | Backend: $BACKEND_NAME"
echo "PostgreSQL: $([ "$ENABLE_POSTGRES" = true ] && echo "Enabled" || echo "Disabled") | Force Init: $([ "$FORCE_INIT" = true ] && echo "Yes" || echo "No")"

# Main deployment flow
validate_env
pause_for_verification "Environment validation complete. Ready to initialize Railway project."

init_project
pause_for_verification "Railway project initialization complete. Ready to check service status."

check_services_status
if [ "$SERVICES_NEED_INIT" = true ] || [ "$POSTGRES_NEED_INIT" = true ]; then
    pause_for_verification "Service status checked. Some services need initialization. Ready to deploy PostgreSQL (if needed)."
    
    deploy_postgres
    pause_for_verification "PostgreSQL deployment complete. Ready to setup environment variables."
    
    setup_vars
    pause_for_verification "Environment variables setup complete. Ready to run database migrations."
    
    run_migrations
    pause_for_verification "Database migrations complete. Ready to setup Railway services."
    
    setup_services
    pause_for_verification "Railway services setup complete. Ready to deploy all services."
else
    log "All services already exist. Skipping PostgreSQL, variables, migrations, and service setup."
    pause_for_verification "Service status checked. All services already exist. Ready to deploy services."
fi

deploy_all

# Summary
header "Deployment Complete"
echo "✓ Frontend: https://$FRONTEND_DOMAIN"
echo "✓ Backend: https://$BACKEND_DOMAIN" 
[ "$ENABLE_POSTGRES" = true ] && echo "✓ PostgreSQL: Database running"
echo "Commands: railway status | railway logs --service <name> | railway variables --service <name>"
