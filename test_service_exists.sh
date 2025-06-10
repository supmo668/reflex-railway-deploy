#!/bin/bash

# Test script to debug service_exists function

RAILWAY_ENVIRONMENT="test"
SERVICE_NAME="Postgres"
CACHE_FILE="railway_services.json"

echo "Testing service_exists logic..."
echo "Environment: $RAILWAY_ENVIRONMENT"
echo "Service: $SERVICE_NAME"
echo "Cache file: $CACHE_FILE"
echo ""

# Step 1: Test environment ID lookup
echo "Step 1: Looking for environment ID..."
env_id=$(jq -r --arg env "$RAILWAY_ENVIRONMENT" '
    .[] | .environments.edges[] | .node | select(.name == $env) | .id
' "$CACHE_FILE" | head -n1)

echo "Found environment ID: '$env_id'"
echo ""

if [ -z "$env_id" ]; then
    echo "ERROR: No environment ID found for environment '$RAILWAY_ENVIRONMENT'"
    exit 1
fi

# Step 2: Test service lookup
echo "Step 2: Looking for service with environment match..."
result=$(jq -e --arg service "$SERVICE_NAME" --arg env_id "$env_id" '
    .[] | .services.edges[] | .node |
    select(.name == $service) |
    select(.serviceInstances.edges[] | .node | .environmentId == $env_id)
' "$CACHE_FILE" 2>&1)

if [ $? -eq 0 ]; then
    echo "SUCCESS: Service '$SERVICE_NAME' found in environment '$RAILWAY_ENVIRONMENT'"
    echo "Result: $result"
else
    echo "FAILED: Service '$SERVICE_NAME' not found in environment '$RAILWAY_ENVIRONMENT'"
    echo "Error: $result"
    
    # Debug: Show all services
    echo ""
    echo "Debug: All services in the file:"
    jq '.[] | .services.edges[] | .node | .name' "$CACHE_FILE"
    
    echo ""
    echo "Debug: All services in project with test environment:"
    jq --arg env_id "$env_id" '
        .[] | select(.environments.edges[] | .node | .id == $env_id) | .services.edges[] | .node | .name
    ' "$CACHE_FILE"
fi
