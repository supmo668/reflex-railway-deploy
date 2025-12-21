#!/bin/bash
# deploy_all.sh - Streamlined Railway deployment for Reflex applications
# Usage: ./deploy_all.sh -p PROJECT [OPTIONS]
#
# This script orchestrates the deployment of a Reflex app to Railway.
# It uses modular functions from functions/ for reusability and testing.
#
# Environment files are loaded from envs/ in this order:
#   1. envs/.env.base (shared config)
#   2. envs/.env.{APP_ENV} (environment-specific)
#   3. envs/.env.secrets (API keys - gitignored)
#
# Set APP_ENV to control which environment config is loaded (default: test)

set -e

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ SCRIPT SETUP                                                       ║
# ╚═══════════════════════════════════════════════════════════════════╝

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"

# Source modular functions
source "$SCRIPT_DIR/functions/logging.sh"
source "$SCRIPT_DIR/functions/env.sh"
source "$SCRIPT_DIR/functions/railway.sh"
source "$SCRIPT_DIR/functions/deploy.sh"

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ ARGUMENT PARSING                                                   ║
# ╚═══════════════════════════════════════════════════════════════════╝

show_help() {
    cat << EOF
Usage: $0 -p PROJECT [OPTIONS]

Railway deployment for Reflex applications.
Requires RAILWAY_TOKEN environment variable (or be logged in via 'railway login').

Required:
  -p, --project PROJECT     Railway project ID/name

Optional:
  -t, --team TEAM           Railway team (default: personal)
  -e, --environment ENV     Railway environment (default: test)
  -b, --backend NAME        Backend service name (default: backend)
  -n, --frontend NAME       Frontend service name (default: frontend)
  --skip-db                 Skip PostgreSQL setup and migrations
  -h, --help                Show this help

Environment:
  APP_ENV                   Controls which .env.{APP_ENV} file is loaded (default: test)
  RAILWAY_TOKEN             Railway API token (required for CI/CD)
  APP_ENV_VARS              Comma-separated list of additional env vars to sync

Examples:
  # Local development (interactive login)
  ./deploy_all.sh -p my-project

  # CI/CD with token
  RAILWAY_TOKEN=xxx ./deploy_all.sh -p my-project -e test

  # Skip database (demo mode)
  ./deploy_all.sh -p my-project --skip-db
EOF
    exit 0
}

# Defaults - test environment by default for safety
BACKEND_NAME="backend"
FRONTEND_NAME="frontend"
RAILWAY_ENVIRONMENT="test"
RAILWAY_TEAM=""
RAILWAY_PROJECT=""
SKIP_DB=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -p|--project) RAILWAY_PROJECT="$2"; shift 2 ;;
        -t|--team) RAILWAY_TEAM="$2"; shift 2 ;;
        -e|--environment) RAILWAY_ENVIRONMENT="$2"; shift 2 ;;
        -b|--backend) BACKEND_NAME="$2"; shift 2 ;;
        -n|--frontend) FRONTEND_NAME="$2"; shift 2 ;;
        --skip-db) SKIP_DB=true; shift ;;
        -y|--yes) shift ;;  # Accepted but ignored (always non-interactive)
        *) error "Unknown option: $1. Use -h for help." ;;
    esac
done

# Validate required args
[ -z "$RAILWAY_PROJECT" ] && error "Project required. Use: $0 -p PROJECT"
[ -d "$DEPLOY_DIR" ] || error "Deploy directory not found: $DEPLOY_DIR"

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ ENVIRONMENT SETUP                                                  ║
# ╚═══════════════════════════════════════════════════════════════════╝

# Sync APP_ENV with RAILWAY_ENVIRONMENT if not explicitly set
# This ensures .env.test is loaded for test environment, .env.prod for prod
export APP_ENV="${APP_ENV:-$RAILWAY_ENVIRONMENT}"

# Load environment files (base -> env-specific -> secrets)
load_env_files "envs"

# Auto-enable SKIP_DB if IS_DEMO is true
[ "$IS_DEMO" = "true" ] && SKIP_DB=true

# Derive public URLs from service names and environment
# Railway generates: https://{service}-{environment}.up.railway.app
BACKEND_PUBLIC_URL="https://${BACKEND_NAME}-${RAILWAY_ENVIRONMENT}.up.railway.app"
FRONTEND_PUBLIC_URL="https://${FRONTEND_NAME}-${RAILWAY_ENVIRONMENT}.up.railway.app"

# Export variables needed by functions
export DEPLOY_DIR RAILWAY_PROJECT RAILWAY_ENVIRONMENT RAILWAY_TEAM
export BACKEND_NAME FRONTEND_NAME SKIP_DB
export BACKEND_PUBLIC_URL FRONTEND_PUBLIC_URL
export REFLEX_DB_URL APP_ENV IS_DEMO

# ╔═══════════════════════════════════════════════════════════════════╗
# ║ DEPLOYMENT                                                         ║
# ╚═══════════════════════════════════════════════════════════════════╝

header "Railway Deployment"
echo "Project: $RAILWAY_PROJECT | Environment: $RAILWAY_ENVIRONMENT"
echo "Backend: $BACKEND_NAME | Frontend: $FRONTEND_NAME"
echo "APP_ENV: $APP_ENV"
[ -n "$RAILWAY_TEAM" ] && echo "Team: $RAILWAY_TEAM"
[ "$SKIP_DB" = true ] && echo "Database: SKIPPED (demo mode)"
echo ""

# Run the deployment
run_deployment
