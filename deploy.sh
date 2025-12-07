#!/bin/bash
# deploy.sh - Generic Railway deployment script for Reflex applications using Dockerfiles
# 
# Usage: ./deploy.sh -p PROJECT -e ENVIRONMENT -b BACKEND_SERVICE -f FRONTEND_SERVICE [OPTIONS]
# 
# This script deploys a Reflex app to Railway using Dockerfiles.
# All app-specific parameters must be provided via arguments or environment variables.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  -p, --project PROJECT       Railway project name"
    echo "  -e, --environment ENV       Railway environment (e.g., test, production)"
    echo "  -b, --backend SERVICE       Backend service name"
    echo "  -f, --frontend SERVICE      Frontend service name"
    echo ""
    echo "Optional Options:"
    echo "  -d, --deploy-dir DIR        Deploy directory with Dockerfiles (default: reflex-railway-deploy)"
    echo "      --env-file FILE         Environment file to source (default: .env)"
    echo "      --skip-db               Skip PostgreSQL service lookup"
    echo "      --postgres-service NAME Name of PostgreSQL service (default: Postgres)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables (can be set instead of arguments):"
    echo "  RAILWAY_PROJECT             Railway project name"
    echo "  RAILWAY_ENVIRONMENT         Railway environment"
    echo "  BACKEND_SERVICE             Backend service name"
    echo "  FRONTEND_SERVICE            Frontend service name"
    echo "  DEPLOY_DIR                  Deploy directory"
    echo "  APP_ENV_VARS                Space-separated list of env vars to set on services"
    echo ""
    echo "Examples:"
    echo "  $0 -p myproject -e test -b api -f web"
    echo "  $0 -p myproject -e production -b backend -f frontend --skip-db"
    exit 0
}

# Parse arguments
DEPLOY_DIR="reflex-railway-deploy"
ENV_FILE=".env"
SKIP_DB=false
POSTGRES_SERVICE="Postgres"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -b|--backend) BACKEND_SERVICE="$2"; shift 2 ;;
        -f|--frontend) FRONTEND_SERVICE="$2"; shift 2 ;;
        -d|--deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --env-file) ENV_FILE="$2"; shift 2 ;;
        --skip-db) SKIP_DB=true; shift ;;
        --postgres-service) POSTGRES_SERVICE="$2"; shift 2 ;;
        *) error "Unknown option: $1. Use -h for help." ;;
    esac
done

# Validate required parameters
[ -z "$RAILWAY_PROJECT" ] && error "Railway project is required. Use -p PROJECT"
[ -z "$RAILWAY_ENVIRONMENT" ] && error "Railway environment is required. Use -e ENVIRONMENT"
[ -z "$BACKEND_SERVICE" ] && error "Backend service name is required. Use -b SERVICE"
[ -z "$FRONTEND_SERVICE" ] && error "Frontend service name is required. Use -f SERVICE"

# Validate deploy directory
[ -d "$DEPLOY_DIR" ] || error "Deploy directory '$DEPLOY_DIR' not found"
[ -f "$DEPLOY_DIR/Dockerfile.backend" ] || error "Dockerfile.backend not found in $DEPLOY_DIR"
[ -f "$DEPLOY_DIR/Dockerfile.frontend" ] || error "Dockerfile.frontend not found in $DEPLOY_DIR"

# Source environment file if exists
if [ -f "$ENV_FILE" ]; then
    log "Sourcing environment from $ENV_FILE"
    set -a; source "$ENV_FILE"; set +a
fi

# Validate Railway CLI
command -v railway &> /dev/null || error "Railway CLI not found. Install with: npm i -g @railway/cli"
railway whoami &> /dev/null || error "Not logged in to Railway. Run 'railway login' first"

# Construct Railway URLs based on service names and environment
# Railway URL format: <service>-<environment>.up.railway.app
BACKEND_URL="https://${BACKEND_SERVICE}-${RAILWAY_ENVIRONMENT}.up.railway.app"
FRONTEND_URL="https://${FRONTEND_SERVICE}-${RAILWAY_ENVIRONMENT}.up.railway.app"

log "=========================================="
log "Railway Deployment Configuration"
log "=========================================="
log "Project:     $RAILWAY_PROJECT"
log "Environment: $RAILWAY_ENVIRONMENT"
log "Backend:     $BACKEND_SERVICE -> $BACKEND_URL"
log "Frontend:    $FRONTEND_SERVICE -> $FRONTEND_URL"
log "=========================================="

# Link to Railway project
log "Linking to Railway project..."
railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" || error "Failed to link to Railway project"

# Get database URL from Postgres service
DB_URL=""
if [ "$SKIP_DB" = false ]; then
    log "Getting database URL from $POSTGRES_SERVICE service..."
    DB_URL=$(railway variables --service "$POSTGRES_SERVICE" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
    
    if [ -z "$DB_URL" ]; then
        warn "Could not get DATABASE_URL from $POSTGRES_SERVICE service."
    else
        log "Database URL retrieved successfully"
    fi
fi

# Function to create service if it doesn't exist
create_service_if_needed() {
    local service_name=$1
    log "Checking service: $service_name..."
    if ! railway variables --service "$service_name" &>/dev/null 2>&1; then
        log "Creating service: $service_name"
        railway add -s "$service_name" || error "Failed to create $service_name service"
        sleep 5
    else
        log "Service $service_name already exists"
    fi
}

# Function to set environment variables on a service (BATCHED to avoid rate limits)
set_service_vars() {
    local service_name=$1
    local is_frontend=$2
    
    log "Setting environment variables for $service_name..."
    
    # Build array of all variables to set in ONE command
    local var_args=()
    
    # Database URL
    if [ -n "$DB_URL" ]; then
        var_args+=("--set" "DB_URL=$DB_URL")
        var_args+=("--set" "DATABASE_URL=$DB_URL")
    fi
    
    # Deployment URLs
    var_args+=("--set" "REFLEX_API_URL=$BACKEND_URL")
    var_args+=("--set" "FRONTEND_DEPLOY_URL=$FRONTEND_URL")
    
    # Port configuration
    if [ "$is_frontend" = true ]; then
        var_args+=("--set" "PORT=3000")
    else
        var_args+=("--set" "PORT=8000")
    fi
    
    # Add app-specific variables from APP_ENV_VARS
    if [ -n "$APP_ENV_VARS" ]; then
        for var in $APP_ENV_VARS; do
            value="${!var}"
            if [ -n "$value" ]; then
                var_args+=("--set" "$var=$value")
            fi
        done
    fi
    
    # Set ALL variables in a SINGLE command to avoid triggering multiple deployments
    if [ ${#var_args[@]} -gt 0 ]; then
        local var_count=$((${#var_args[@]} / 2))
        log "Setting $var_count variables in a single command..."
        if railway variables --service "$service_name" "${var_args[@]}"; then
            log "✓ All variables set for $service_name"
        else
            warn "Failed to set some variables for $service_name"
        fi
    fi
}

# Function to deploy a service
deploy_service() {
    local service_name=$1
    local dockerfile=$2
    
    log "Preparing Dockerfile for $service_name..."
    cp "$DEPLOY_DIR/$dockerfile" Dockerfile
    
    log "Deploying $service_name..."
    railway up --service "$service_name" || error "Failed to deploy $service_name"
    success "$service_name deployed!"
    
    # Clean up
    rm -f Dockerfile
}

# Function to ensure service has a domain
ensure_domain() {
    local service_name=$1
    
    log "Ensuring domain for $service_name..."
    local domain=$(railway variables --service "$service_name" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    
    if [ -z "$domain" ]; then
        log "Generating domain for $service_name..."
        railway domain --service "$service_name" || warn "Failed to generate domain"
        sleep 5
    fi
}

# Create services if needed
create_service_if_needed "$BACKEND_SERVICE"
create_service_if_needed "$FRONTEND_SERVICE"

# Set environment variables
set_service_vars "$BACKEND_SERVICE" false
set_service_vars "$FRONTEND_SERVICE" true

# Deploy backend
deploy_service "$BACKEND_SERVICE" "Dockerfile.backend"
log "Waiting for backend to initialize..."
sleep 10

# Ensure backend has domain
ensure_domain "$BACKEND_SERVICE"

# Deploy frontend
deploy_service "$FRONTEND_SERVICE" "Dockerfile.frontend"

# Ensure frontend has domain
ensure_domain "$FRONTEND_SERVICE"

# Get final domains
BACKEND_DOMAIN=$(railway variables --service "$BACKEND_SERVICE" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
FRONTEND_DOMAIN=$(railway variables --service "$FRONTEND_SERVICE" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")

echo ""
echo "=========================================="
success "Deployment Complete!"
echo "=========================================="
echo ""
[ -n "$FRONTEND_DOMAIN" ] && echo "✓ Frontend: https://$FRONTEND_DOMAIN"
[ -n "$BACKEND_DOMAIN" ] && echo "✓ Backend:  https://$BACKEND_DOMAIN"
[ "$SKIP_DB" = false ] && echo "✓ PostgreSQL: Database running"
echo ""
echo "Check status at: https://railway.app/project/$RAILWAY_PROJECT"
