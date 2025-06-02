#!/bin/bash
#!/bin/bash
# set_railway_vars.sh - Set Railway environment variables from environment file
#
# Usage:
#   ./set_railway_vars.sh [options]
#
# Options:
#   -h, --help                 Show this help message
#   -s, --service SERVICE      Service name to update in Railway
#   -f, --file FILENAME        Environment file to use [default: .env]
#   -v, --verbose              Enable verbose output
#
# Examples:
#   ./set_railway_vars.sh -s my-service           # Set variables for 'my-service' from .env
#   ./set_railway_vars.sh -s my-service -f .env.prod  # Use .env.prod file

# Default values
SERVICE=""
ENV_FILE=".env"
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -h, --help                 Show this help message"
      echo "  -s, --service SERVICE      Service name to update in Railway"
      echo "  -f, --file FILENAME        Environment file to use [default: .env]"
      echo "  -v, --verbose              Enable verbose output"
      echo ""
      echo "Examples:"
      echo "  $0 -s my-service           # Set variables for 'my-service' from .env"
      echo "  $0 -s my-service -f .env.prod  # Use .env.prod file"
      exit 0
      ;;
    -s|--service)
      SERVICE="$2"
      shift 2
      ;;
    -f|--file)
      ENV_FILE="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate service argument
if [ -z "$SERVICE" ]; then
  echo "Error: Service name is required. Use -s or --service to specify."
  exit 1
fi

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: Environment file $ENV_FILE not found"
  exit 1
fi

# Check if railway CLI is installed
if ! command -v railway &> /dev/null; then
  echo "Error: Railway CLI not found. Please install it first:"
  echo "npm i -g @railway/cli"
  exit 1
fi

# Check if logged in to Railway
if ! railway whoami &> /dev/null; then
  echo "Error: Not logged in to Railway. Please run 'railway login' first"
  exit 1
fi

# Load environment variables from file
set -a
source "$ENV_FILE"
set +a

# Function to set only variables from the .env file for a service
set_env_variables() {
  local service_name=$1
  local env_file=$2
  
  echo "Setting variables for $service_name service from $env_file..."
  
  # Check if file exists
  if [ ! -f "$env_file" ]; then
    echo "Error: Environment file $env_file not found"
    exit 1
  fi
  
  # Count variables to be set
  local var_count=$(grep -v '^\s*#' "$env_file" | grep '=' | wc -l)
  echo "Found $var_count variables to set"
  
  # Read the .env file line by line
  while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ ! "$line" =~ ^\s*# && ! "$line" =~ ^\s*$ && "$line" == *=* ]]; then
      # Extract variable name and value
      local var_name=$(echo "$line" | cut -d= -f1)
      local var_value=$(echo "$line" | cut -d= -f2-)
      
      # Remove quotes if present
      var_value=$(echo "$var_value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
      
      if $VERBOSE; then
        echo "Setting $var_name=$var_value"
      else
        echo "Setting $var_name"
      fi
      
      railway variables --service "$SERVICE" --set "$var_name=$var_value"
    fi
  done < "$env_file"
  
  echo "Variables set for $service_name service"
}

# Set variables from the env file for the specified service
set_env_variables "$SERVICE" "$ENV_FILE"

echo "Environment variables set successfully!"
echo "You can verify them in the Railway dashboard or by running:"
echo "railway variables --service $SERVICE"
echo "Done setting Railway variables"