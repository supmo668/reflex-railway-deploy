#!/bin/bash
# functions/env.sh - Environment loading utilities
# Usage: source functions/env.sh

# Load environment files from envs/ directory
# Order: .env.base -> .env.{APP_ENV} -> .env.secrets
load_env_files() {
    local envs_dir="${1:-envs}"
    local app_env="${APP_ENV:-test}"
    
    if [ ! -d "$envs_dir" ]; then
        warn "envs/ directory not found at $envs_dir"
        return 1
    fi
    
    log "Loading environment files (APP_ENV=$app_env)..."
    
    # Load base config
    if [ -f "$envs_dir/.env.base" ]; then
        set -a; source "$envs_dir/.env.base"; set +a
        log "  ✓ Loaded .env.base"
    fi
    
    # Load environment-specific config
    if [ -f "$envs_dir/.env.$app_env" ]; then
        set -a; source "$envs_dir/.env.$app_env"; set +a
        log "  ✓ Loaded .env.$app_env"
    else
        warn "  ○ .env.$app_env not found"
    fi
    
    # Load secrets (gitignored)
    if [ -f "$envs_dir/.env.secrets" ]; then
        set -a; source "$envs_dir/.env.secrets"; set +a
        log "  ✓ Loaded .env.secrets"
    else
        warn "  ○ .env.secrets not found (may cause deployment issues)"
    fi
}

# Build Railway variable arguments from current environment
# Usage: build_var_args "service_name" VAR_ARGS
# Populates VAR_ARGS array with --set KEY=VALUE pairs
build_var_args() {
    local service=$1
    local -n _var_args=$2
    
    _var_args=()
    
    # Core environment variables (both services need these)
    [ -n "$APP_ENV" ] && _var_args+=("--set" "APP_ENV=$APP_ENV")
    [ -n "$IS_DEMO" ] && _var_args+=("--set" "IS_DEMO=$IS_DEMO")
    [ -n "$LOGLEVEL" ] && _var_args+=("--set" "LOGLEVEL=$LOGLEVEL")
    
    # Database (backend only, skip if SKIP_DB is set)
    if [ "$service" = "$BACKEND_NAME" ] && [ "$SKIP_DB" != true ] && [ -n "$REFLEX_DB_URL" ]; then
        _var_args+=("--set" "REFLEX_DB_URL=$REFLEX_DB_URL")
    fi
    
    # Secrets (backend only - frontend doesn't need API keys)
    if [ "$service" = "$BACKEND_NAME" ]; then
        [ -n "$OPENAI_API_KEY" ] && _var_args+=("--set" "OPENAI_API_KEY=$OPENAI_API_KEY")
        [ -n "$CALL_LOGS_API_KEY" ] && _var_args+=("--set" "CALL_LOGS_API_KEY=$CALL_LOGS_API_KEY")
    fi
    
    # App-specific variables from APP_ENV_VARS (comma-separated list of var names)
    if [ -n "$APP_ENV_VARS" ]; then
        IFS=',' read -ra vars <<< "$APP_ENV_VARS"
        for var_name in "${vars[@]}"; do
            var_name=$(echo "$var_name" | xargs)  # trim whitespace
            local val="${!var_name}"
            [ -n "$val" ] && _var_args+=("--set" "$var_name=$val")
        done
    fi
    
    # Service-specific URL configuration
    if [ "$service" = "$FRONTEND_NAME" ]; then
        # Frontend: REFLEX_API_URL = backend public URL (client-side access)
        [ -n "$BACKEND_PUBLIC_URL" ] && _var_args+=("--set" "REFLEX_API_URL=$BACKEND_PUBLIC_URL")
        # Frontend: REFLEX_DEPLOY_URL = its own public URL
        [ -n "$FRONTEND_PUBLIC_URL" ] && _var_args+=("--set" "REFLEX_DEPLOY_URL=$FRONTEND_PUBLIC_URL")
    fi
    
    if [ "$service" = "$BACKEND_NAME" ]; then
        # Backend: REFLEX_DEPLOY_URL = its own public URL
        [ -n "$BACKEND_PUBLIC_URL" ] && _var_args+=("--set" "REFLEX_DEPLOY_URL=$BACKEND_PUBLIC_URL")
        # Backend: CORS_ALLOWED_ORIGINS = frontend public URL
        [ -n "$FRONTEND_PUBLIC_URL" ] && _var_args+=("--set" "CORS_ALLOWED_ORIGINS=$FRONTEND_PUBLIC_URL")
    fi
}
