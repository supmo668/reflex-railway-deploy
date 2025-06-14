#!/bin/bash
# debug_vars.sh - Debug script to check environment variables and Railway service status

set -e

# Parse arguments
SERVICE=""
ENV_FILE=".env"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--service) SERVICE="$2"; shift 2 ;;
        -f|--file) ENV_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate
[ -z "$SERVICE" ] && { echo "Error: Service name required (-s)"; exit 1; }
[ ! -f "$ENV_FILE" ] && { echo "Error: File $ENV_FILE not found"; exit 1; }

echo "=== DEBUG INFO ==="
echo "Service: $SERVICE"
echo "Env file: $ENV_FILE"
echo ""

echo "=== RAILWAY CLI STATUS ==="
railway whoami 2>&1 || echo "Not logged in to Railway"
echo ""

echo "=== CURRENT SERVICE STATUS ==="
railway status 2>&1 || echo "No Railway project linked"
echo ""

echo "=== SERVICE LIST ==="
railway list 2>&1 || echo "Cannot list services"
echo ""

echo "=== CURRENT VARIABLES IN RAILWAY SERVICE ==="
railway variables --service "$SERVICE" 2>&1 || echo "Cannot get variables for service: $SERVICE"
echo ""

echo "=== VARIABLES IN .ENV FILE ==="
echo "File contents:"
cat "$ENV_FILE" | head -20
echo ""
echo "Variable count in .env:"
grep -E '^[A-Z_]+=' "$ENV_FILE" | wc -l
echo ""

echo "=== CHECKING SERVICE EXISTENCE ==="
if railway list --json 2>/dev/null | jq -e --arg service "$SERVICE" '.[] | .services.edges[] | .node | select(.name == $service)' >/dev/null 2>&1; then
    echo "✓ Service $SERVICE exists"
else
    echo "✗ Service $SERVICE does not exist or cannot be accessed"
fi
echo ""

echo "=== TESTING SIMPLE VARIABLE SET ==="
echo "Testing setting a simple variable TEST_VAR=test_value"
railway variables --service "$SERVICE" --set "TEST_VAR=test_value" 2>&1 || echo "✗ Failed to set test variable"
