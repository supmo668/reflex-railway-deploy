#!/bin/bash
# test_set_railway_vars.sh - Test version that shows what would happen

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

echo "TEST MODE: Would set variables for $SERVICE from $ENV_FILE..."

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
  var_value=${var_value:-""}
  
  ((var_count++))
  
  if $VERBOSE; then
    echo "Would set: $var_name='$var_value'"
  else
    echo "Would set: $var_name"
  fi
  
  # Simulate success for testing
  ((success_count++))
  
done < "$ENV_FILE"

# Summary
echo "TEST COMPLETE: Would set $success_count/$var_count variables"
echo "Would run: railway variables --service $SERVICE"
