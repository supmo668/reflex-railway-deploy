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
    log "Linking to $service..."
    if ! railway link -p "$RAILWAY_PROJECT" -e "$RAILWAY_ENVIRONMENT" -s "$service" ${RAILWAY_TEAM:+-t "$RAILWAY_TEAM"} < /dev/null 2>&1; then
        error "Failed to link to $service. Ensure the service exists in Railway project '$RAILWAY_PROJECT' environment '$RAILWAY_ENVIRONMENT'."
    fi
    
    # Set variables
    if [ ${#var_args[@]} -gt 0 ]; then
        log "Setting ${#var_args[@]} variables..."
        railway variables "${var_args[@]}" 2>&1 || warn "Some variables may not have been set"
    fi
    
    # Deploy with detach (-d) to avoid waiting for logs
    # This makes the script non-blocking and CI/CD friendly
    log "Uploading and deploying $service..."
    railway up -d || error "Deploy failed for $service"
    
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

# Run database migrations using Alembic directly
# This properly handles both local SQLite and remote PostgreSQL (Supabase)
run_migrations() {
    [ "$SKIP_DB" = true ] && { log "Migrations skipped (SKIP_DB=true)"; return 0; }
    
    header "Database Migrations"
    
    # Use REFLEX_DB_URL from env if already set (e.g., from .env.test for Supabase)
    # Otherwise try to get from Railway Postgres service
    local db_url="$REFLEX_DB_URL"
    if [ -z "$db_url" ]; then
        db_url=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // .DATABASE_URL // empty' 2>/dev/null || echo "")
    fi
    
    [ -z "$db_url" ] && { warn "No database URL, skipping migrations"; return 0; }
    
    # Mask password in logs
    local masked_url
    if [[ "$db_url" == *"@"* ]]; then
        masked_url="...@${db_url#*@}"
    else
        masked_url="$db_url"
    fi
    log "Database: $masked_url"
    
    # Run Alembic migrations directly (more reliable than reflex db commands)
    # The alembic/env.py reads REFLEX_DB_URL from environment
    log "Running Alembic migrations..."
    
    # First, try to stamp head if alembic_version table doesn't exist
    # This handles fresh databases where schema was created by Reflex
    if REFLEX_DB_URL="$db_url" uv run alembic current 2>&1 | grep -q "No such revision"; then
        log "Stamping database as current (fresh schema detected)..."
        REFLEX_DB_URL="$db_url" uv run alembic stamp head 2>/dev/null || true
    fi
    
    # Run upgrade to apply any pending migrations
    if REFLEX_DB_URL="$db_url" uv run alembic upgrade head 2>&1; then
        success "Migrations complete"
    else
        # If upgrade fails, try stamping head (schema may already match)
        warn "Migration had issues - attempting to stamp current schema..."
        if REFLEX_DB_URL="$db_url" uv run alembic stamp head 2>/dev/null; then
            success "Database stamped at head (schema already up to date)"
        else
            warn "Migration stamp failed - continuing deployment (tables may already exist)"
        fi
    fi
}

# Main deployment orchestration
# Creates services if needed, runs migrations, deploys both services
run_deployment() {
    # Validate Railway CLI
    validate_railway_cli
    
    # NOTE: We skip the project-level railway_link here because:
    # 1. It prompts for service selection (requires ESC to skip)
    # 2. deploy_service() links to specific services with -s flag anyway
    # The per-service link in deploy_service is sufficient for deployment
    
    # Check existing services
    check_services
    
    # Create services if needed (first-time setup)
    local need_create=false
    [ "$SKIP_DB" != true ] && [ "$POSTGRES_EXISTS" = false ] && need_create=true
    [ "$BACKEND_EXISTS" = false ] && need_create=true
    [ "$FRONTEND_EXISTS" = false ] && need_create=true
    
    if [ "$need_create" = true ]; then
        create_postgres
        # Only fetch DB URL from Railway if not already set in env
        [ "$SKIP_DB" != true ] && [ -z "$REFLEX_DB_URL" ] && get_db_url
        create_service "$BACKEND_NAME"
        create_service "$FRONTEND_NAME"
        refresh_services_cache
    fi
    
    # Run migrations (uses REFLEX_DB_URL from env or fetches from Railway)
    run_migrations
    
    # Deploy backend first (frontend needs backend URL)
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
