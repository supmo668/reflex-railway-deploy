#!/bin/bash
# set_railway_vars.sh - Set Railway environment variables from .env file
# Usage: ./set_railway_vars.sh -s SERVICE [-f FILE] [-e EXCLUDE_VARS]

# Remove set -e to continue processing all variables even if some fail

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

echo "Setting variables for $SERVICE from $ENV_FILE..."
[ -n "$EXCLUDE_VARS" ] && echo "Excluding: $EXCLUDE_VARS"

# Process .env file line by line
success_count=0
error_count=0
skipped_count=0

while IFS= read -r line || [ -n "$line" ]; do
    # Debug: show line being processed
    # echo "DEBUG: Processing line: '$line'"
    
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
    
    # Debug: show extracted variable
    # echo "DEBUG: Extracted var_name='$var_name', var_value='${var_value:0:20}...'"
    
    # Check if variable should be excluded
    if is_excluded "$var_name"; then
        echo "Skipping: $var_name"
        ((skipped_count++))
        continue
    fi
    
    # Remove quotes from value if present
    var_value=$(echo "$var_value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    
    # Set variable in Railway
    echo "Setting: $var_name"
    if railway_output=$(railway variables --service "$SERVICE" --set "$var_name=$var_value" 2>&1); then
        echo "✓ $var_name"
        ((success_count++))
    else
        echo "✗ $var_name (Error: $railway_output)"
        ((error_count++))
        # Continue processing other variables instead of exiting
    fi
    
done < "$ENV_FILE"

# Summary
echo "Complete: $success_count set, $skipped_count skipped, $error_count failed"
[ $error_count -gt 0 ] && exit 1
exit 0