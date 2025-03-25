#!/bin/bash

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi

# Load environment variables from .env
set -a
source .env
set +a

# Set backend variables
echo "Setting backend variables..."
railway variables --service backend --set "HUGGINGFACE_TOKEN=$HUGGINGFACE_TOKEN"
railway variables --service backend --set "BACKEND_HOST=0.0.0.0"
railway variables --service backend --set "FRONTEND_ORIGIN=https://${FRONTEND_NAME}.up.railway.app"
railway variables --service backend --set "APP_NAME=$APP_NAME"
railway variables --service backend --set "FRONTEND_NAME=$FRONTEND_NAME"
railway variables --service backend --set "BACKEND_NAME=$BACKEND_NAME"

# Set frontend variables
echo "Setting frontend variables..."
railway variables --service frontend --set "BACKEND_INTERNAL_URL=http://${BACKEND_NAME}.railway.internal:8000"
railway variables --service frontend --set "RAILWAY_PUBLIC_DOMAIN=${FRONTEND_NAME}.up.railway.app"

echo "Done setting Railway variables"