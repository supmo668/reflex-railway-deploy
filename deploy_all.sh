#!/bin/bash
# deploy_all.sh - Deploy Reflex application to Railway
# This script should be placed in the root directory of your Reflex application (where rxconfig.py is)

set -e  # Exit on any error

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

# Default values
ENV_FILE=".env"
DEPLOY_DIR="reflex-railway-deploy"
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -h, --help                 Show this help message"
      echo "  -f, --file FILENAME        Environment file to use [default: .env]"
      echo "  -d, --deploy-dir DIRNAME   Directory containing deployment files [default: reflex-railway-deploy]"
      echo "  -v, --verbose              Enable verbose output"
      echo ""
      exit 0
      ;;
    -f|--file)
      ENV_FILE="$2"
      shift 2
      ;;
    -d|--deploy-dir)
      DEPLOY_DIR="$2"
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

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: Environment file $ENV_FILE not found"
  exit 1
fi

# Check if deployment directory exists
if [ ! -d "$DEPLOY_DIR" ]; then
  echo "Error: Deployment directory $DEPLOY_DIR not found"
  exit 1
fi

# Load environment variables from file (safely handle empty or missing file)
if [ -s "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE" || { echo "Error: Failed to source $ENV_FILE"; exit 1; }
  set +a
else
  echo "Warning: $ENV_FILE is empty or missing, using default values"
fi

# Set default values if not provided in .env
APP_NAME=${APP_NAME:-"reflex_railway_deployment"}
FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
BACKEND_NAME=${BACKEND_NAME:-"backend"}

echo "=== Reflex Railway Deployment ==="
echo "App Name: $APP_NAME"
echo "Frontend Service: $FRONTEND_NAME"
echo "Backend Service: $BACKEND_NAME"
echo "================================="

# Step 1: Create services
echo "Step 1: Creating Railway services..."

# Initialize a new Railway project if not already linked
if ! railway status &> /dev/null; then
  echo "No Railway project linked. Creating a new project..."
  railway init || { echo "Error: Failed to initialize Railway project"; exit 1; }
fi

# Add frontend service
echo "Creating frontend service: $FRONTEND_NAME"
railway add --service "$FRONTEND_NAME" || { echo "Error: Failed to create frontend service"; exit 1; }

# Add backend service
echo "Creating backend service: $BACKEND_NAME"
railway add --service "$BACKEND_NAME" || { echo "Error: Failed to create backend service"; exit 1; }

# Verify services were created
echo "Verifying services..."
railway status

# Step 2: Set environment variables for both services
echo "Step 2: Setting environment variables..."

# Ensure API_URL is set correctly to point to the backend service
# This is critical for the frontend to communicate with the backend
if [ -z "$API_URL" ]; then
  export API_URL="http://${BACKEND_NAME}.railway.internal:8000"
  echo "Setting API_URL to $API_URL"
fi

# Check if set_railway_vars.sh exists before using it
if [ ! -f "$DEPLOY_DIR/set_railway_vars.sh" ]; then
  echo "Warning: $DEPLOY_DIR/set_railway_vars.sh not found, skipping environment variable setup"
else
  # Set variables for frontend service
  echo "Setting variables for frontend service..."
  "$DEPLOY_DIR/set_railway_vars.sh" -s "$FRONTEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v} || echo "Warning: Failed to set frontend variables"

  # Set variables for backend service
  echo "Setting variables for backend service..."
  "$DEPLOY_DIR/set_railway_vars.sh" -s "$BACKEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v} || echo "Warning: Failed to set backend variables"
fi

# Step 3: Deploy frontend and backend
echo "Step 3: Deploying services..."

# Get current directory
CURRENT_DIR=$(pwd)

# Function to deploy a service
deploy_service() {
  local service_name=$1
  local service_type=$2  # "frontend" or "backend"
  
  echo "Deploying $service_type service: $service_name"
  
  # Check if configuration files exist before copying
  if [ ! -f "$DEPLOY_DIR/Caddyfile.$service_type" ]; then
    echo "Error: $DEPLOY_DIR/Caddyfile.$service_type not found"
    return 1
  fi
  
  if [ ! -f "$DEPLOY_DIR/nixpacks.$service_type.toml" ]; then
    echo "Error: $DEPLOY_DIR/nixpacks.$service_type.toml not found"
    return 1
  fi
  
  # Copy the appropriate Caddyfile and nixpacks.toml
  echo "Copying $service_type configuration files..."
  cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || { echo "Error: Failed to copy Caddyfile"; return 1; }
  cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || { echo "Error: Failed to copy nixpacks.toml"; return 1; }
  
  # Select the service
  echo "Selecting service: $service_name"
  railway service "$service_name" || { echo "Error: Failed to select service $service_name"; return 1; }
  
  # Deploy the service
  echo "Deploying $service_name..."
  railway up || { echo "Error: Failed to deploy $service_name"; return 1; }
  
  echo "$service_type service deployed successfully!"
}

# Deploy backend service first
deploy_service "$BACKEND_NAME" "backend" || { echo "Backend deployment failed"; exit 1; }

# Deploy frontend service
deploy_service "$FRONTEND_NAME" "frontend" || { echo "Frontend deployment failed"; exit 1; }

echo "=== Deployment Complete ==="
echo "Your Reflex application has been deployed to Railway!"
echo "Frontend URL: https://$FRONTEND_NAME.up.railway.app"
echo "Backend URL: https://$BACKEND_NAME.up.railway.app"
echo "You can check the status of your services with: railway status"
echo "To view logs: railway logs --service <service-name>"
echo "=========================="
