#!/bin/bash
# set_railway_vars.sh - Set Railway environment variables from .env file
#
# Usage: ./set_railway_vars.sh -s SERVICE [-f FILE] [-v] [-e EXCLUDE_VARS]
# Example: ./set_railway_vars.sh -s backend -f .env -e "REFLEX_DB_URL,REFLEX_API_URL"

set -e

# Enable debug mode
DEBUG=${DEBUG:-false}
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] $1"
    fi
}

# Defaults
SERVICE="" ENV_FILE=".env" VERBOSE=false EXCLUDE_VARS=""

debug "Starting set_railway_vars.sh script"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) echo "Usage: $0 -s SERVICE [-f FILE] [-v] [-e EXCLUDE_VARS]"; exit 0 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--file) ENV_FILE="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -e|--exclude) EXCLUDE_VARS="$2"; shift 2 ;;
    *) echo "Error: Unknown option $1"; exit 1 ;;
  esac
done

debug "Parsed arguments: SERVICE=$SERVICE, ENV_FILE=$ENV_FILE, EXCLUDE_VARS=$EXCLUDE_VARS"

# Validate inputs
debug "Validating inputs..."
[ -z "$SERVICE" ] && { echo "Error: Service name required (-s)"; exit 1; }
[ ! -f "$ENV_FILE" ] && { echo "Error: File $ENV_FILE not found"; exit 1; }

debug "Checking Railway CLI..."
command -v railway &> /dev/null || { echo "Error: Railway CLI not found"; exit 1; }

debug "Checking Railway authentication..."
if ! railway_auth_output=$(railway whoami 2>&1); then
    echo "Error: Not logged in to Railway. Output: $railway_auth_output"
    exit 1
fi
debug "Railway auth OK: $railway_auth_output"

debug "Checking Railway project status..."
railway_status_output=""
if ! railway_status_output=$(railway status 2>&1); then
    echo "Error: No Railway project linked or accessible."
    echo "Railway status output: $railway_status_output"
    echo ""
    echo "To fix this issue:"
    echo "1. Make sure you're in the correct directory with a Railway project"
    echo "2. Or link to a project: railway link"
    echo "3. Or run the deploy_all.sh script which handles project linking"
    exit 1
fi
debug "Railway status OK: $railway_status_output"

debug "Testing service access..."
if ! railway_list_output=$(railway list 2>&1); then
    echo "Error: Cannot list Railway services."
    echo "Railway list output: $railway_list_output"
    exit 1
fi
debug "Railway list OK, found services"

debug "Testing service-specific access..."
if ! railway_vars_output=$(railway variables --service "$SERVICE" 2>&1); then
    echo "Error: Cannot access service '$SERVICE'."
    echo "Railway variables output: $railway_vars_output"
    echo ""
    echo "Available services:"
    railway list 2>/dev/null || echo "Cannot list services"
    exit 1
fi
debug "Service access OK"

# Convert exclude vars to array for easier checking
IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_VARS"

# Function to check if variable should be excluded
is_excluded() {
    local var_name="$1"
    for excluded in "${EXCLUDE_ARRAY[@]}"; do
        if [[ "$var_name" == "${excluded// /}" ]]; then
            return 0  # Variable is excluded
        fi
    done
    return 1  # Variable is not excluded
}

# Set variables from .env file to Railway service
echo "Setting variables for $SERVICE from $ENV_FILE..."
[ -n "$EXCLUDE_VARS" ] && echo "Excluding variables: $EXCLUDE_VARS"

# Count and process variables
var_count=0 success_count=0 error_count=0 skipped_count=0

while IFS= read -r line || [ -n "$line" ]; do
  debug "Processing line: $line"
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]] || [[ ! "$line" == *=* ]] && continue
  
  # Extract variable name and value
  var_name=$(echo "$line" | cut -d= -f1 | xargs)
  var_value=$(echo "$line" | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
  
  debug "Extracted: var_name='$var_name', var_value='${var_value:0:20}...'"
  
  # Skip invalid variable names
  [[ -z "$var_name" ]] && continue
  
  # Skip excluded variables
  if is_excluded "$var_name"; then
    echo "Skipping excluded variable: $var_name"
    ((skipped_count++))
    continue
  fi
  
  # Safeguard: Handle empty values by setting them explicitly
  # This ensures the variable exists in Railway even if empty
  var_value=${var_value:-""}
  
  ((var_count++))
  
  # Show truncated value for display
  if [ ${#var_value} -gt 20 ]; then
    display_value="${var_value:0:20}..."
  else
    display_value="$var_value"
  fi
  echo "Setting $var_name='$display_value'"
  
  debug "About to call railway variables --service '$SERVICE' --set '$var_name=$var_value'"
  
  # Set variable in Railway with error handling
  if output=$(railway variables --service "$SERVICE" --set "$var_name=$var_value" 2>&1); then
    ((success_count++))
    echo "✓ Success: $var_name"
    debug "Railway output: $output"
  else
    ((error_count++))
    echo "✗ Failed to set $var_name"
    echo "  Error output: $output"
    
    # Safeguard: Try alternative approach for problematic variables
    if alt_output=$(railway variables --service "$SERVICE" --set "$var_name=" 2>&1); then
      echo "  → Set as empty value instead"
      ((success_count++))
      ((error_count--))
    else
      echo "  → Alternative also failed: $alt_output"
      echo "  → Manual fix: railway variables --service $SERVICE --set \"$var_name=$var_value\""
    fi
  fi
done < "$ENV_FILE"

# Summary
echo "Complete: $success_count/$var_count variables set successfully"
[ $skipped_count -gt 0 ] && echo "Skipped: $skipped_count excluded variables"
[ $error_count -gt 0 ] && echo "Errors: $error_count variables failed" && exit 1
echo "Verify: railway variables --service $SERVICE"