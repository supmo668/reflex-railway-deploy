#!/bin/bash

# Test script to verify cache logic
DEPLOY_DIR="$(pwd)"

# Mock get_services_list function
get_services_list() {
    local cache_file="$DEPLOY_DIR/railway_services.json"
    echo "Creating cache file at: $cache_file"
    echo '[]' > "$cache_file"
    echo "$cache_file"
}

# Mock service_exists function (simplified)
service_exists() {
    local service_name=$1
    local cache_file="$DEPLOY_DIR/railway_services.json"
    
    echo "Checking service '$service_name' using cache file: $cache_file"
    
    # Check if cache file exists and is readable
    if [ ! -f "$cache_file" ]; then
        echo "Cache file does not exist!"
        return 1
    fi
    
    echo "Cache file exists and is readable"
    return 1  # Always return false for this test
}

# Test the logic
echo "=== Testing cache logic ==="

# Create cache once
echo "Step 1: Creating cache file"
CACHE_FILE=$(get_services_list)
echo "Cache file created: $CACHE_FILE"

echo
echo "Step 2: Testing service checks (should use existing cache)"
service_exists "test-service-1"
echo

service_exists "test-service-2"
echo

service_exists "test-service-3"
echo

echo "=== Test complete ==="
ls -la railway_services.json
