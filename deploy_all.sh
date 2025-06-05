#!/bin/bash
# deploy_all.sh - Deploy Reflex application to Railway
# This script should be placed in the root directory of your Reflex application (where rxconfig.py is)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if railway CLI is installed
check_railway_cli() {
    if ! command -v railway &> /dev/null; then
        print_error "Railway CLI not found. Please install it first:"
        echo "npm i -g @railway/cli"
        exit 1
    fi
    print_success "Railway CLI found"
}

# Check if logged in to Railway
check_railway_auth() {
    if ! railway whoami &> /dev/null; then
        print_error "Not logged in to Railway. Please run 'railway login' first"
        exit 1
    fi
    print_success "Railway authentication verified"
}

# Initialize Railway project
init_railway_project() {
    print_status "Checking Railway project status..."
    
    if ! railway status &> /dev/null; then
        print_status "No Railway project linked. Creating a new project..."
        railway init || { print_error "Failed to initialize Railway project"; exit 1; }
        print_success "Railway project initialized"
    else
        print_success "Railway project already linked"
    fi
}

# Deploy PostgreSQL service
deploy_postgres() {
    if [ "$ENABLE_POSTGRES" = false ]; then
        print_status "PostgreSQL deployment skipped (disabled)"
        return 0
    fi
    
    print_status "Setting up PostgreSQL service..."
    
    # Check if postgres service already exists
    if railway service list 2>/dev/null | grep -q "Postgres"; then
        print_success "PostgreSQL service already exists"
        return 0
    fi
    
    # Add PostgreSQL service using database template (automatically named "Postgres")
    print_status "Adding PostgreSQL service..."
    railway add -d postgres || { print_error "Failed to add PostgreSQL service"; exit 1; }
    
    # Wait for deployment
    print_status "Waiting for PostgreSQL deployment (this may take a minute)..."
    sleep 15
    
    # Check deployment status
    print_status "Checking PostgreSQL deployment status..."
    railway status --service "Postgres" || print_warning "Could not verify PostgreSQL status"
    
    print_success "PostgreSQL service deployed"
}

# Function to update environment variable in .env file
update_env_variable() {
    local var_name=$1
    local var_value=$2
    local env_file=$3
    
    if [ -z "$var_name" ] || [ -z "$var_value" ] || [ -z "$env_file" ]; then
        print_error "update_env_variable: Missing required parameters"
        return 1
    fi
    
    # Use sed to replace existing variable line or add it if it doesn't exist
    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        # Replace existing variable line
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
        print_success "Updated ${var_name} in $env_file"
    else
        # Add variable if it doesn't exist
        echo "${var_name}=${var_value}" >> "$env_file"
        print_success "Added ${var_name} to $env_file"
    fi
}

# Get PostgreSQL connection variables and update .env file
get_postgres_vars() {
    if [ "$ENABLE_POSTGRES" = false ]; then
        return 0
    fi
    
    print_status "Retrieving PostgreSQL connection variables..."
    
    # Get DATABASE_PUBLIC_URL from postgres service (automatically named "Postgres")
    REFLEX_DB_URL=$(railway variables --service "Postgres" --json 2>/dev/null | jq -r '.DATABASE_PUBLIC_URL // empty' 2>/dev/null || echo "")
    
    if [ -z "$REFLEX_DB_URL" ]; then
        print_warning "Could not retrieve DATABASE_PUBLIC_URL from PostgreSQL service"
        print_status "This is normal if the service is still starting up"
        print_status "DATABASE_PUBLIC_URL will be available once PostgreSQL is fully deployed"
        return 0
    fi
    
    print_success "DATABASE_PUBLIC_URL retrieved successfully"
    export REFLEX_DB_URL
    
    # Update .env file with REFLEX_DB_URL
    update_env_variable "REFLEX_DB_URL" "$REFLEX_DB_URL" "$ENV_FILE"
}

# Run database initialization and migrations
run_db_migrations() {
    if [ "$ENABLE_POSTGRES" = false ]; then
        print_status "Database initialization and migrations skipped (PostgreSQL disabled)"
        return 0
    fi
    
    if [ -z "$REFLEX_DB_URL" ]; then
        print_warning "REFLEX_DB_URL not available, skipping database initialization and migrations"
        print_status "You may need to run 'reflex db init' and 'reflex db migrate' manually after deployment"
        return 0
    fi
    
    print_status "Initializing database schema..."
    
    # Set REFLEX_DB_URL for the migration
    export REFLEX_DB_URL
    
    # Run reflex db init first
    if reflex db init; then
        print_success "Database initialization completed successfully"
    else
        print_warning "Database initialization failed or already initialized"
        print_status "This may be normal if the database is already initialized"
    fi
    
    print_status "Running database migrations..."
    
    # Run reflex db migrate
    if reflex db migrate; then
        print_success "Database migrations completed successfully"
    else
        print_warning "Database migrations failed or no migrations to run"
        print_status "This may be normal if this is the first deployment or no migrations are needed"
    fi
}

# Create Railway services
create_services() {
    print_status "Creating Railway services..."
    
    # Add frontend service
    if railway service list 2>/dev/null | grep -q "$FRONTEND_NAME"; then
        print_success "Frontend service '$FRONTEND_NAME' already exists"
    else
        print_status "Creating frontend service: $FRONTEND_NAME"
        railway add --service "$FRONTEND_NAME" || { print_error "Failed to create frontend service"; exit 1; }
        print_success "Frontend service created"
    fi
    
    # Add backend service
    if railway service list 2>/dev/null | grep -q "$BACKEND_NAME"; then
        print_success "Backend service '$BACKEND_NAME' already exists"
    else
        print_status "Creating backend service: $BACKEND_NAME"
        railway add --service "$BACKEND_NAME" || { print_error "Failed to create backend service"; exit 1; }
        print_success "Backend service created"
    fi
    
    # Verify services were created
    print_status "Verifying services..."
    railway status
}

# Set environment variables
setup_environment_variables() {
    print_status "Setting up environment variables..."
    
    # Ensure API_URL is set correctly to point to the backend service
    if [ -z "$API_URL" ]; then
        export API_URL="http://${BACKEND_NAME}.railway.internal:8080"
        print_status "Setting API_URL to $API_URL"
        # Update API_URL in .env file
        update_env_variable "API_URL" "$API_URL" "$ENV_FILE"
    fi
    
    # Note: REFLEX_DB_URL is already set in .env file by get_postgres_vars function
    
    # Check if set_railway_vars.sh exists before using it
    if [ ! -f "$DEPLOY_DIR/set_railway_vars.sh" ]; then
        print_warning "$DEPLOY_DIR/set_railway_vars.sh not found, skipping environment variable setup"
        return 0
    fi
    
    # Make the script executable
    chmod +x "$DEPLOY_DIR/set_railway_vars.sh"
    
    # Set variables for frontend service
    print_status "Setting variables for frontend service..."
    if "$DEPLOY_DIR/set_railway_vars.sh" -s "$FRONTEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v}; then
        print_success "Frontend variables set successfully"
    else
        print_warning "Failed to set some frontend variables"
    fi
    
    # Set variables for backend service
    print_status "Setting variables for backend service..."
    if "$DEPLOY_DIR/set_railway_vars.sh" -s "$BACKEND_NAME" -f "$ENV_FILE" ${VERBOSE:+-v}; then
        print_success "Backend variables set successfully"
    else
        print_warning "Failed to set some backend variables"
    fi
}

# Deploy a single service
deploy_service() {
    local service_name=$1
    local service_type=$2  # "frontend" or "backend"
    
    print_status "Deploying $service_type service: $service_name"
    
    # Check if configuration files exist before copying
    if [ ! -f "$DEPLOY_DIR/Caddyfile.$service_type" ]; then
        print_error "$DEPLOY_DIR/Caddyfile.$service_type not found"
        return 1
    fi
    
    if [ ! -f "$DEPLOY_DIR/nixpacks.$service_type.toml" ]; then
        print_error "$DEPLOY_DIR/nixpacks.$service_type.toml not found"
        return 1
    fi
    
    # Copy the appropriate Caddyfile and nixpacks.toml
    print_status "Copying $service_type configuration files..."
    cp "$DEPLOY_DIR/Caddyfile.$service_type" Caddyfile || { print_error "Failed to copy Caddyfile"; return 1; }
    cp "$DEPLOY_DIR/nixpacks.$service_type.toml" nixpacks.toml || { print_error "Failed to copy nixpacks.toml"; return 1; }
    
    # Select the service
    print_status "Selecting service: $service_name"
    railway service "$service_name" || { print_error "Failed to select service $service_name"; return 1; }
    
    # Deploy the service
    print_status "Deploying $service_name (this may take several minutes)..."
    railway up || { print_error "Failed to deploy $service_name"; return 1; }
    
    print_success "$service_type service deployed successfully!"
}

# Deploy all services
deploy_services() {
    print_status "Deploying services..."
    
    # Deploy backend service first
    if deploy_service "$BACKEND_NAME" "backend"; then
        print_success "Backend deployment completed"
    else
        print_error "Backend deployment failed"
        exit 1
    fi
    
    # Deploy frontend service
    if deploy_service "$FRONTEND_NAME" "frontend"; then
        print_success "Frontend deployment completed"
    else
        print_error "Frontend deployment failed"
        exit 1
    fi
}

# Display final status and URLs
show_deployment_summary() {
    print_header "Deployment Complete"
    echo ""
    print_success "Your Reflex application has been deployed to Railway!"
    echo ""
    echo "Services deployed:"
    echo "  • Frontend: https://$FRONTEND_NAME.up.railway.app"
    echo "  • Backend: https://$BACKEND_NAME.up.railway.app"
    if [ "$ENABLE_POSTGRES" = true ]; then
        echo "  • PostgreSQL: Database service running"
    fi
    echo ""
    echo "Useful commands:"
    echo "  • Check status: railway status"
    echo "  • View logs: railway logs --service <service-name>"
    echo "  • View variables: railway variables --service <service-name>"
    echo ""
}

# Main execution starts here

# Default values
ENV_FILE=".env"
DEPLOY_DIR="reflex-railway-deploy"
VERBOSE=false
ENABLE_POSTGRES=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -h, --help                 Show this help message"
            echo "  -f, --file FILENAME        Environment file to use [default: .env]"
            echo "  -d, --deploy-dir DIRNAME   Directory containing deployment files [default: reflex-railway-deploy]"
            echo "  -v, --verbose              Enable verbose output"
            echo "  --no-postgres              Skip PostgreSQL service deployment"
            echo "  --postgres                 Enable PostgreSQL service deployment [default]"
            echo ""
            echo "Examples:"
            echo "  $0                         Deploy with default settings"
            echo "  $0 --no-postgres           Deploy without PostgreSQL"
            echo "  $0 -f .env.prod -v         Deploy with custom env file and verbose output"
            echo ""
            exit 0
            ;;
        -f|--file)
            ENV_FILE="$2"
            shift 2
            ;;
        -d|--deploy-dir)
            DEPLOY_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-postgres)
            ENABLE_POSTGRES=false
            shift
            ;;
        --postgres)
            ENABLE_POSTGRES=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate requirements
if [ ! -f "$ENV_FILE" ]; then
    print_error "Environment file $ENV_FILE not found"
    exit 1
fi

if [ ! -d "$DEPLOY_DIR" ]; then
    print_error "Deployment directory $DEPLOY_DIR not found"
    exit 1
fi

# Load environment variables from file
if [ -s "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE" || { print_error "Failed to source $ENV_FILE"; exit 1; }
    set +a
    print_success "Environment variables loaded from $ENV_FILE"
else
    print_warning "$ENV_FILE is empty or missing, using default values"
fi

# Set default values if not provided in .env
REFLEX_APP_NAME=${REFLEX_APP_NAME:-"reflex_railway_deployment"}
FRONTEND_NAME=${FRONTEND_NAME:-"frontend"}
BACKEND_NAME=${BACKEND_NAME:-"backend"}

# Display configuration
print_header "Reflex Railway Deployment"
echo "Configuration:"
echo "  • App Name: $REFLEX_APP_NAME"
echo "  • Frontend Service: $FRONTEND_NAME"
echo "  • Backend Service: $BACKEND_NAME"
echo "  • PostgreSQL Service: Postgres (auto-named by Railway)"
echo "  • Environment File: $ENV_FILE"
echo "  • Deploy Directory: $DEPLOY_DIR"
echo "  • PostgreSQL: $([ "$ENABLE_POSTGRES" = true ] && echo "Enabled" || echo "Disabled")"
echo "  • Verbose: $([ "$VERBOSE" = true ] && echo "Enabled" || echo "Disabled")"
echo ""

# Execute deployment steps
print_header "Step 1: Validating Environment"
check_railway_cli
check_railway_auth

print_header "Step 2: Initializing Project"
init_railway_project

print_header "Step 3: Setting Up Database"
deploy_postgres

print_header "Step 4: Configuring Database Connection and Schema"
get_postgres_vars

print_header "Step 5: Initializing Database and Running Migrations"
run_db_migrations

print_header "Step 6: Creating Application Services"
create_services

print_header "Step 7: Configuring Environment Variables"
setup_environment_variables

print_header "Step 8: Deploying Services"
deploy_services

# Show final summary
show_deployment_summary
