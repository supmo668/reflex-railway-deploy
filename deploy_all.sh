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

# Load environment variables from file
set -a
source "$ENV_FILE"
set +a

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
  railway init
fi

# Add frontend service
echo "Creating frontend service: $FRONTEND_NAME"
railway add --service "$FRONTEND_NAME"

# Add backend service
echo "Creating backend service: $BACKEND_NAME"
railway add --service "$BACKEND_NAME"

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

# Set variables for frontend service
echo "Setting variables for frontend service..."
"$DEPLOY_DIR/set_railway_vars.sh" -s "$FRONTEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v}

# Set variables for backend service
echo "Setting variables for backend service..."
"$DEPLOY_DIR/set_railway_vars.sh" -s "$BACKEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v}

# Step 3: Deploy frontend and backend
echo "Step 3: Deploying services..."

# Get current directory
CURRENT_DIR=$(pwd)

# Function to deploy a service
deploy_service() {
  local service_name=$1
  local service_type=$2  # "frontend" or "backend"
  
  echo "Deploying $service_type service: $service_name"
  
  # Copy the appropriate Caddyfile and nixpacks.toml
  echo "Copying $service_type configuration files..."
  cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile
  cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml
  
  # Select the service
  echo "Selecting service: $service_name"
  railway service "$service_name"
  
  # Deploy the service
  echo "Deploying $service_name..."
  railway up
  
  echo "$service_type service deployed successfully!"
}

# Deploy backend service first
deploy_service "$BACKEND_NAME" "backend"

# Deploy frontend service
deploy_service "$FRONTEND_NAME" "frontend"

echo "=== Deployment Complete ==="
echo "Your Reflex application has been deployed to Railway!"
echo "Frontend URL: https://$FRONTEND_NAME.up.railway.app"
echo "Backend URL: https://$BACKEND_NAME.up.railway.app"
echo "You can check the status of your services with: railway status"
echo "To view logs: railway logs --service <service-name>"
echo "=========================="
