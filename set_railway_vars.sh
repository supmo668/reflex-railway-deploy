#!/bin/bash

# set_railway_vars.sh - Set Railway environment variables from environment file
#
# Usage:
#   ./set_railway_vars.sh [options]
#
# Options:
#   -h, --help                 Show this help message
#   -s, --service SERVICE      Service to update (backend, frontend, or all) [default: backend]
#   -f, --file FILENAME        Environment file to use [default: .railway.env]
#   -p, --prefix PREFIX        Only set variables with this prefix
#   -v, --verbose              Enable verbose output
#
# Examples:
#   ./set_railway_vars.sh                     # Set backend variables from .railway.env
#   ./set_railway_vars.sh -s frontend         # Set frontend variables from .railway.env
#   ./set_railway_vars.sh -s all              # Set both backend and frontend variables
#   ./set_railway_vars.sh -f .env             # Use .env file instead of .railway.env
#   ./set_railway_vars.sh -p DATABASE_        # Only set variables starting with DATABASE_

# Default values
SERVICE="backend"
ENV_FILE=".railway.env"
PREFIX=""
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -h, --help                 Show this help message"
      echo "  -s, --service SERVICE      Service to update (backend, frontend, or all) [default: backend]"
      echo "  -f, --file FILENAME        Environment file to use [default: .railway.env]"
      echo "  -p, --prefix PREFIX        Only set variables with this prefix"
      echo "  -v, --verbose              Enable verbose output"
      echo ""
      echo "Examples:"
      echo "  $0                     # Set backend variables from .railway.env"
      echo "  $0 -s frontend         # Set frontend variables from .railway.env"
      echo "  $0 -s all              # Set both backend and frontend variables"
      echo "  $0 -f .env             # Use .env file instead of .railway.env"
      echo "  $0 -p DATABASE_        # Only set variables starting with DATABASE_"
      exit 0
      ;;
    -s|--service)
      SERVICE="$2"
      shift 2
      ;;
    -f|--file)
      ENV_FILE="$2"
      shift 2
      ;;
    -p|--prefix)
      PREFIX="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate service argument
if [[ "$SERVICE" != "backend" && "$SERVICE" != "frontend" && "$SERVICE" != "all" ]]; then
  echo "Error: Service must be 'backend', 'frontend', or 'all'"
  exit 1
fi

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
  # Try to find .env as fallback
  if [ -f ".env" ] && [ "$ENV_FILE" != ".env" ]; then
    echo "Warning: $ENV_FILE not found, using .env as fallback"
    ENV_FILE=".env"
  else
    echo "Error: Environment file $ENV_FILE not found"
    echo "Please create one from .env.template or specify a different file with -f"
    exit 1
  fi
fi

# Check if railway CLI is installed
if ! command -v railway &> /dev/null; then
  echo "Error: Railway CLI not found. Please install it first:"
  echo "npm i -g @railway/cli"
  exit 1
fi

# Check if logged in to Railway
if ! railway whoami &> /dev/null; then
  echo "Error: Not logged in to Railway. Please run 'railway login' first"
  exit 1
fi

# Load environment variables from file
set -a
source "$ENV_FILE"
set +a

# Required variables check
if [[ "$SERVICE" == "backend" || "$SERVICE" == "all" ]]; then
  if [ -z "$BACKEND_NAME" ]; then
    echo "Error: BACKEND_NAME not set in $ENV_FILE"
    exit 1
  fi
fi

if [[ "$SERVICE" == "frontend" || "$SERVICE" == "all" ]]; then
  if [ -z "$FRONTEND_NAME" ]; then
    echo "Error: FRONTEND_NAME not set in $ENV_FILE"
    exit 1
  fi
fi

# Function to set variables for a service
set_variables() {
  local service_name=$1
  local grep_pattern=$2
  local exclude_pattern=$3
  
  echo "Setting variables for $service_name service..."
  
  # Get all environment variables
  local vars=$(env)
  
  # Filter variables based on prefix if provided
  if [ -n "$PREFIX" ]; then
    vars=$(echo "$vars" | grep "^$PREFIX")
  elif [ -n "$grep_pattern" ]; then
    vars=$(echo "$vars" | grep -E "$grep_pattern")
  fi
  
  # Exclude specific variables if pattern provided
  if [ -n "$exclude_pattern" ]; then
    vars=$(echo "$vars" | grep -v -E "$exclude_pattern")
  fi
  
  # Count variables to be set
  local var_count=$(echo "$vars" | wc -l)
  echo "Found $var_count variables to set"
  
  # Set each variable
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      local var_name=$(echo "$line" | cut -d= -f1)
      local var_value=${!var_name}
      
      if $VERBOSE; then
        echo "Setting $var_name=$var_value"
      else
        echo "Setting $var_name"
      fi
      
      railway variables --service "$service_name" --set "$var_name=$var_value"
    fi
  done <<< "$vars"
  
  echo "Variables set for $service_name service"
}

# Set special variables for backend
set_backend_variables() {
  echo "Setting special backend variables..."
  railway variables --service "$BACKEND_NAME" --set "BACKEND_HOST=0.0.0.0"
  
  if [ -n "$FRONTEND_NAME" ]; then
    railway variables --service "$BACKEND_NAME" --set "FRONTEND_ORIGIN=https://${FRONTEND_NAME}.up.railway.app"
  fi
  
  if [ -n "$APP_NAME" ]; then
    railway variables --service "$BACKEND_NAME" --set "APP_NAME=$APP_NAME"
  fi
}

# Set special variables for frontend
set_frontend_variables() {
  echo "Setting special frontend variables..."
  
  if [ -n "$BACKEND_NAME" ]; then
    railway variables --service "$FRONTEND_NAME" --set "BACKEND_INTERNAL_URL=http://${BACKEND_NAME}.railway.internal:8000"
  fi
  
  if [ -n "$APP_NAME" ]; then
    railway variables --service "$FRONTEND_NAME" --set "APP_NAME=$APP_NAME"
  fi
}

# Set variables based on service argument
if [[ "$SERVICE" == "backend" || "$SERVICE" == "all" ]]; then
  set_backend_variables
  set_variables "$BACKEND_NAME" "^BACKEND_|^APP_|^DB_|^DATABASE_|^REDIS_|^CACHE_|^AUTH_|^API_" "^BACKEND_NAME$|^BACKEND_INTERNAL_URL$"
  echo ""
fi

if [[ "$SERVICE" == "frontend" || "$SERVICE" == "all" ]]; then
  set_frontend_variables
  set_variables "$FRONTEND_NAME" "^FRONTEND_|^APP_|^PUBLIC_" "^FRONTEND_NAME$|^FRONTEND_ORIGIN$"
  echo ""
fi

echo "Environment variables set successfully!"
echo "You can verify them in the Railway dashboard or by running:"

if [[ "$SERVICE" == "backend" || "$SERVICE" == "all" ]]; then
  echo "railway variables --service $BACKEND_NAME"
fi

if [[ "$SERVICE" == "frontend" || "$SERVICE" == "all" ]]; then
  echo "railway variables --service $FRONTEND_NAME"
fi

echo "Done setting Railway variables"