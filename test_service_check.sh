#!/bin/bash
# test_service_check.sh - Test the service checking functionality

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m' NC='\033[0m'
log() { echo -e "${BLUE}[TEST]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }

# Check if service exists in Railway project
service_exists() {
    local service_name=$1
    # If service exists, railway service <name> produces no output
    # If service doesn't exist, it produces error message
    local output=$(railway service "$service_name" 2>&1)
    [ -z "$output" ]
}

log "Testing service existence check..."

# Test with a service that definitely doesn't exist
if service_exists "nonexistent-service-123456"; then
    error "service_exists incorrectly reported that 'nonexistent-service-123456' exists"
else
    success "service_exists correctly reported that 'nonexistent-service-123456' does not exist"
fi

# Note: To test with real services, you would need to be in a Railway project
log "To test with real services, run this in a Railway project directory with known services"

echo "Test complete."
