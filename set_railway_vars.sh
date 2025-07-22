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

# Collect all variables first
set_args=()
success_count=0
error_count=0
skipped_count=0

echo "Collecting variables from $ENV_FILE..."

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
        echo "Skipping: $var_name"
        ((skipped_count++))
        continue
    fi
    
    # Remove quotes from value if present
    var_value=$(echo "$var_value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    
    # Add to set_args array
    set_args+=("--set" "$var_name=$var_value")
    echo "Collected: $var_name"
    ((success_count++))
    
done < "$ENV_FILE"

# Set all variables at once if we have any to set
if [ ${#set_args[@]} -gt 0 ]; then
    echo "Setting ${#set_args[@]}/2 variables in Railway service '$SERVICE'..."
    if railway_output=$(railway variables --service "$SERVICE" "${set_args[@]}" 2>&1); then
        echo "✓ Successfully set all variables"
    else
        echo "✗ Failed to set variables: $railway_output"
        error_count=$success_count
        success_count=0
    fi
else
    echo "No variables to set"
fi

# Summary
echo "Complete: $success_count set, $skipped_count skipped, $error_count failed"
[ $error_count -gt 0 ] && exit 1
exit 0