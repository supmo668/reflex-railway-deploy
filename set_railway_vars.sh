#!/bin/bash
# set_railway_vars.sh - Set Railway environment variables from .env file
#
# Usage: ./set_railway_vars.sh -s SERVICE [-f FILE] [-v]
# Example: ./set_railway_vars.sh -s backend -f .env

set -e

# Defaults
SERVICE="" ENV_FILE=".env" VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) echo "Usage: $0 -s SERVICE [-f FILE] [-v]"; exit 0 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--file) ENV_FILE="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    *) echo "Error: Unknown option $1"; exit 1 ;;
  esac
done

# Validate inputs
[ -z "$SERVICE" ] && { echo "Error: Service name required (-s)"; exit 1; }
[ ! -f "$ENV_FILE" ] && { echo "Error: File $ENV_FILE not found"; exit 1; }
command -v railway &> /dev/null || { echo "Error: Railway CLI not found"; exit 1; }
railway whoami &> /dev/null || { echo "Error: Not logged in to Railway"; exit 1; }

# Set variables from .env file to Railway service
echo "Setting variables for $SERVICE from $ENV_FILE..."

# Count and process variables
var_count=0 success_count=0 error_count=0

while IFS= read -r line || [ -n "$line" ]; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]] || [[ ! "$line" == *=* ]] && continue
  
  # Extract variable name and value
  var_name=$(echo "$line" | cut -d= -f1 | xargs)
  var_value=$(echo "$line" | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
  
  # Skip invalid variable names
  [[ -z "$var_name" ]] && continue
  
  # Safeguard: Handle empty values by setting them explicitly
  # This ensures the variable exists in Railway even if empty
  var_value=${var_value:-""}
  
  ((var_count++))
  
  $VERBOSE && echo "Setting $var_name='$var_value'" || echo "Setting $var_name"
  
  # Set variable in Railway with error handling
  if railway variables --service "$SERVICE" --set "$var_name=$var_value" 2>/dev/null; then
    ((success_count++))
    $VERBOSE && echo "✓ Success"
  else
    ((error_count++))
    echo "✗ Failed to set $var_name"
    
    # Safeguard: Try alternative approach for problematic variables
    if railway variables --service "$SERVICE" --set "$var_name=" 2>/dev/null; then
      echo "  → Set as empty value instead"
      ((success_count++))
      ((error_count--))
    else
      echo "  → Manual fix: railway variables --service $SERVICE --set \"$var_name=$var_value\""
    fi
  fi
done < "$ENV_FILE"

# Summary
echo "Complete: $success_count/$var_count variables set"
[ $error_count -gt 0 ] && echo "Errors: $error_count variables failed" && exit 1
echo "Verify: railway variables --service $SERVICE"