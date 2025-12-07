#!/bin/bash
# set_railway_vars.sh - Set Railway environment variables from .env file
# Usage: ./set_railway_vars.sh -s SERVICE [-f FILE] [-e EXCLUDE_VARS]
#
# IMPORTANT: This script batches all variables into a SINGLE railway variables command
# to avoid triggering multiple deployments and hitting rate limits.

# Defaults
SERVICE="" ENV_FILE=".env" EXCLUDE_VARS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--file) ENV_FILE="$2"; shift 2 ;;
    -e|--exclude) EXCLUDE_VARS="$2"; shift 2 ;;
    *) echo "Error: Unknown option $1"; exit 1 ;;
  esac
done

# Basic validation
[ -z "$SERVICE" ] && { echo "Error: Service name required (-s)"; exit 1; }
[ ! -f "$ENV_FILE" ] && { echo "Error: File $ENV_FILE not found"; exit 1; }

# Convert exclude vars to array
IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_VARS"

# Function to check if variable should be excluded
is_excluded() {
    local var_name="$1"
    for excluded in "${EXCLUDE_ARRAY[@]}"; do
        if [[ "$var_name" == "${excluded// /}" ]]; then
            return 0
        fi
    done
    return 1
}

echo "Collecting variables for $SERVICE from $ENV_FILE..."
[ -n "$EXCLUDE_VARS" ] && echo "Excluding: $EXCLUDE_VARS"

# Collect all variables into an array for batched setting
declare -a VAR_ARGS=()
skipped_count=0

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Skip lines without '='
    [[ ! "$line" == *=* ]] && continue
    
    # Extract variable name and value using first '=' as delimiter
    var_name="${line%%=*}"
    var_value="${line#*=}"
    
    # Clean up variable name (remove spaces)
    var_name=$(echo "$var_name" | xargs)
    
    # Skip if variable name is empty
    [[ -z "$var_name" ]] && continue
    
    # Check if variable should be excluded
    if is_excluded "$var_name"; then
        echo "  Skipping: $var_name"
        ((skipped_count++))
        continue
    fi
    
    # Remove quotes from value if present
    var_value=$(echo "$var_value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    
    # Add to batch array
    VAR_ARGS+=("--set" "$var_name=$var_value")
    echo "  Collected: $var_name"
    
done < "$ENV_FILE"

# Set all variables in a single Railway command (triggers only ONE deployment)
var_count=${#VAR_ARGS[@]}
var_count=$((var_count / 2))  # Each var has --set and value

if [ ${#VAR_ARGS[@]} -gt 0 ]; then
    echo ""
    echo "Setting $var_count variables for $SERVICE in a single command..."
    if railway_output=$(railway variables --service "$SERVICE" "${VAR_ARGS[@]}" 2>&1); then
        echo "✓ Successfully set $var_count variables"
    else
        echo "✗ Failed to set variables: $railway_output"
        exit 1
    fi
else
    echo "No variables to set"
fi

# Summary
echo "Complete: $var_count set, $skipped_count skipped"
exit 0