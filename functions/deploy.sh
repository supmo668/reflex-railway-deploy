#!/bin/bash
# functions/deploy.sh - Service deployment utilities
# Usage: source functions/deploy.sh

# Set variables and deploy a service
# Usage: deploy_service "service_name" "backend|frontend"
deploy_service() {
    local service=$1
    local type=$2
    
    header "Deploying $service ($type)"
    
    # Copy the appropriate Dockerfile to root
    if [ "$type" = "backend" ]; then
        cp "$DEPLOY_DIR/Dockerfile.backend" Dockerfile 2>/dev/null || error "Dockerfile.backend not found"
    else
        cp "$DEPLOY_DIR/Dockerfile.frontend" Dockerfile 2>/dev/null || error "Dockerfile.frontend not found"
    fi
    
    # Build variable arguments
    local var_args=()
    build_var_args "$service" var_args
    
    # Link to service
    railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} || error "Failed to link to $service"
    
    # Set variables
    if [ ${#var_args[@]} -gt 0 ]; then
        log "Setting ${#var_args[@]} variables..."
        railway variables "${var_args[@]}" || warn "Some variables may not have been set"
    fi
    
    # Deploy
    log "Deploying $service..."
    railway up || error "Deploy failed for $service"
    
    # Cleanup
    rm -f Dockerfile
    
    success "$service deployed"
}

# Update URL variables after deployment
# Fetches actual domains from Railway and updates BACKEND_PUBLIC_URL, FRONTEND_PUBLIC_URL
update_service_urls() {
    local backend_url
    local frontend_url
    
    backend_url=$(get_service_url "$BACKEND_NAME")
    frontend_url=$(get_service_url "$FRONTEND_NAME")
    
    [ -n "$backend_url" ] && BACKEND_PUBLIC_URL="$backend_url"
    [ -n "$frontend_url" ] && FRONTEND_PUBLIC_URL="$frontend_url"
    
    log "Backend URL: $BACKEND_PUBLIC_URL"
    log "Frontend URL: $FRONTEND_PUBLIC_URL"
}

# Run database migrations
run_migrations() {
    [ "$SKIP_DB" = true ] && { log "Migrations skipped (SKIP_DB=true)"; return 0; }
    
    header "Database Migrations"
    
    # Get public database URL for local migrations
    local public_url
    public_url=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
    [ -z "$public_url" ] && public_url="$REFLEX_DB_URL"
    
    [ -z "$public_url" ] && { warn "No database URL, skipping migrations"; return 0; }
    
    log "Running migrations..."
    REFLEX_DB_URL="$public_url" uv run reflex db init 2>/dev/null || true
    REFLEX_DB_URL="$public_url" uv run reflex db makemigrations 2>/dev/null || true
    REFLEX_DB_URL="$public_url" uv run reflex db migrate || error "Migrations failed"
    
    success "Migrations complete"
}

# Main deployment orchestration
# Creates services if needed, runs migrations, deploys both services
run_deployment() {
    # Validate Railway CLI
    validate_railway_cli
    
    # Link to project
    railway_link "$RAILWAY_PROJECT" "$RAILWAY_ENVIRONMENT" "$RAILWAY_TEAM"
    
    # Check existing services
    check_services
    
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
        refresh_services_cache
    fi
    
    # Run migrations
    run_migrations
    
    # Deploy backend first (frontend needs backend URL)
    [ "$SKIP_DB" != true ] && get_db_url
    deploy_service "$BACKEND_NAME" "backend"
    
    # Update URLs from Railway
    update_service_urls
    
    # Deploy frontend
    deploy_service "$FRONTEND_NAME" "frontend"
    
    # Final URL update
    update_service_urls
    
    # Summary
    header "Deployment Complete"
    echo "✓ Backend:  $BACKEND_PUBLIC_URL"
    echo "✓ Frontend: $FRONTEND_PUBLIC_URL"
    [ "$SKIP_DB" = true ] && echo "✓ Database: Skipped (demo mode)" || echo "✓ Database: Connected"
}
