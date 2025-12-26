#!/bin/bash
# functions/railway.sh - Railway CLI utilities
# Usage: source functions/railway.sh

# Validate Railway CLI is installed and authenticated
# Supports both interactive login and RAILWAY_TOKEN for CI/CD
validate_railway_cli() {
    command -v railway &>/dev/null || error "Railway CLI not found. Install: npm install -g @railway/cli"
    
    # Check if RAILWAY_TOKEN is set (CI/CD mode)
    if [ -n "$RAILWAY_TOKEN" ]; then
        success "Railway CLI ready (using RAILWAY_TOKEN)"
        return 0
    fi
    
    # Fall back to checking interactive login
    railway whoami &>/dev/null || error "Not logged in to Railway. Run: railway login\nOr set RAILWAY_TOKEN for CI/CD"
    success "Railway CLI ready"
}

# Link to Railway project and environment
# Usage: railway_link "project" "environment" ["team"]
# Note: Links to project only, service linking happens in deploy_service
railway_link() {
    local project=$1
    local environment=$2
    local team=${3:-}
    
    log "Linking to project: $project ($environment)"
    # Link without service - service is specified per-deploy
    # Use /dev/null to make CLI non-interactive (auto-selects defaults)
    railway link -p "$project" -e "$environment" ${team:+-t "$team"} < /dev/null 2>/dev/null || true
}

# Check if a service exists in the Railway project
# Usage: service_exists "service_name"
service_exists() {
    local service=$1
    local cache="$DEPLOY_DIR/railway_services.json"
    
    [ -f "$cache" ] || return 1
    
    if [ -n "$RAILWAY_PROJECT" ]; then
        jq -e --arg p "$RAILWAY_PROJECT" --arg s "$service" \
            '.[] | select(.name == $p) | .services.edges[] | .node | select(.name == $s)' \
            "$cache" >/dev/null 2>&1
    else
        jq -e --arg s "$service" \
            '.[] | .services.edges[] | .node | select(.name == $s)' \
            "$cache" >/dev/null 2>&1
    fi
}

# Refresh the services cache
refresh_services_cache() {
    railway list --json > "$DEPLOY_DIR/railway_services.json" 2>/dev/null || echo "[]" > "$DEPLOY_DIR/railway_services.json"
}

# Check which services exist
# Sets: POSTGRES_EXISTS, BACKEND_EXISTS, FRONTEND_EXISTS
check_services() {
    header "Checking Services"
    refresh_services_cache
    
    POSTGRES_EXISTS=false
    BACKEND_EXISTS=false
    FRONTEND_EXISTS=false
    
    service_exists "Postgres" && POSTGRES_EXISTS=true
    service_exists "$BACKEND_NAME" && BACKEND_EXISTS=true
    service_exists "$FRONTEND_NAME" && FRONTEND_EXISTS=true
    
    log "Postgres: $POSTGRES_EXISTS | Backend: $BACKEND_EXISTS | Frontend: $FRONTEND_EXISTS"
}

# Create PostgreSQL service (Railway managed)
create_postgres() {
    [ "$SKIP_DB" = true ] && { log "PostgreSQL skipped (SKIP_DB=true)"; return 0; }
    [ "$POSTGRES_EXISTS" = true ] && { success "Postgres exists"; return 0; }
    
    header "Creating PostgreSQL"
    railway add -d postgres || error "Failed to add PostgreSQL"
    sleep 15  # Wait for provisioning
    success "PostgreSQL created"
}

# Create an application service
# Usage: create_service "service_name"
# Note: Only creates if service doesn't exist. Uses railway link to verify existence.
create_service() {
    local service=$1
    
    # Try to link to the service first - if it works, service exists
    if railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" < /dev/null 2>/dev/null; then
        success "$service exists"
        return 0
    fi
    
    # Fallback to cache check
    service_exists "$service" && { success "$service exists"; return 0; }
    
    header "Creating $service"
    # Use echo to provide empty input for interactive prompts
    echo "" | railway add --service "$service" 2>/dev/null || {
        # Service might already exist, try linking again
        if railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" < /dev/null 2>/dev/null; then
            success "$service exists (created or already existed)"
            return 0
        fi
        error "Failed to create $service"
    }
    
    # Add public domain
    railway domain --service "$service" >/dev/null 2>&1 || true
    log "Public domain added for $service"
    
    success "$service created"
}

# Get database URL from PostgreSQL service
# Sets: REFLEX_DB_URL
get_db_url() {
    [ "$SKIP_DB" = true ] && { REFLEX_DB_URL=""; return 0; }
    
    local db_url
    db_url=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_URL // empty' 2>/dev/null || echo "")
    REFLEX_DB_URL="$db_url"
    
    [ -n "$REFLEX_DB_URL" ] && success "Database URL retrieved" || warn "No database URL found"
}

# Fetch public URL for a service from Railway
# Usage: get_service_url "service_name"
get_service_url() {
    local service=$1
    local domain
    domain=$(railway variables --service "$service" --json 2>/dev/null | jq -r '.RAILWAY_PUBLIC_DOMAIN // empty' 2>/dev/null || echo "")
    [ -n "$domain" ] && echo "https://$domain" || echo ""
}
