# Reflex Railway Deployment Template

This template provides automated deployment of Reflex applications to Railway with minimal configuration and native Railway integration.

## Environment Variables Overview

This deployment uses three types of environment variables:

### 1. Script Arguments/Shell Variables (Set Outside .env)

These are set via terminal commands or passed as arguments to the deployment script:

| Variable | Default Value | Purpose | How to Set |
|----------|---------------|---------|------------|
| `BACKEND_NAME` | `"backend"` | Railway backend service name | `export BACKEND_NAME="my-backend"` |
| `FRONTEND_NAME` | `"frontend"` | Railway frontend service name | `export FRONTEND_NAME="my-frontend"` |
| `ENABLE_POSTGRES` | `true` | Enable/disable PostgreSQL deployment | `export ENABLE_POSTGRES=false` |

### 2. Railway-Managed Variables (Automatic)

These are automatically provided by Railway when services are deployed:

| Variable | Purpose | Managed By |
|----------|---------|------------|
| `RAILWAY_PUBLIC_DOMAIN` | Frontend public URL | Railway (automatic) |
| `DATABASE_URL` | PostgreSQL connection string | Railway PostgreSQL service |
| `PORT` | Service port | Railway (automatic) |

### 3. Deployment Script Variables (Set by deploy_all.sh)

These are calculated and set by the deployment script for Railway services:

| Variable | Purpose | Value |
|----------|---------|-------|
| `REFLEX_API_URL` | Backend internal communication | `http://{BACKEND_NAME}.railway.internal:8080` |
| `FRONTEND_DEPLOY_URL` | CORS origin configuration | Actual Railway frontend domain |
| `REFLEX_DB_URL` | Database connection for Reflex | Same as `DATABASE_URL` from PostgreSQL service |

## Quick Start

1. **Set service names** (optional, uses defaults if not set):
   ```bash
   export BACKEND_NAME="my-backend"     # Default: "backend"
   export FRONTEND_NAME="my-frontend"   # Default: "frontend"
   ```

2. **Create your .env file** for application-specific variables:
   ```bash
   # Copy the template and edit with your app's variables
   cp .env.template .env
   # Edit .env with your OPENAI_API_KEY, CLERK_SECRET_KEY, etc.
   ```

3. **Deploy everything**:
   ```bash
   chmod +x deploy_all.sh
   ./deploy_all.sh
   ```

## What the Script Does

1. **Service Setup**:
   - Creates PostgreSQL service (auto-named "Postgres")
   - Creates backend service with name from `$BACKEND_NAME`
   - Creates frontend service with name from `$FRONTEND_NAME`

2. **Variable Configuration**:
   - Sets `REFLEX_API_URL` for internal service communication
   - Configures `FRONTEND_DEPLOY_URL` for CORS using actual Railway domain
   - Sets `REFLEX_DB_URL` from PostgreSQL `DATABASE_URL`
   - Updates your `.env` file with deployment variables
   - Preserves all variables from your `.env` file

3. **Deployment Order**:
   - PostgreSQL → Backend → Frontend
   - Runs database migrations after PostgreSQL is ready
   - Updates frontend URL with actual Railway domain

## Railway Service Communication

- **Internal API calls**: Use `REFLEX_API_URL` (points to `{BACKEND_NAME}.railway.internal:8080`)
- **Public frontend**: Use `RAILWAY_PUBLIC_DOMAIN` (set by Railway automatically)
- **Database**: Use `DATABASE_URL` (provided by Railway PostgreSQL service)
- **CORS**: Configured automatically using the actual frontend domain


## Setup
1. Clone the repository.
2. Install dependencies:
```bash
pip install -r requirements.txt
```
3. Set up environment variables:
   - Copy `.env.template` to `.env`
   - Update the values in `.env` with your credentials
```bash
cp .env.template .env
```
4. Run the application.

## Configuration
- Adjust `rxconfig.py` as needed.

## Usage
- The main page features a video player component.

## Railway Deployment Configuration

### Project and Service Management

#### Link to an Existing Project

If you already have a Railway project set up:

```bash
# List all your Railway projects to find the one you want to use
railway list

# Link to an existing project (replace with your project ID)
railway link <project-id>
```

#### Create a New Project

To create a new Railway project:

```bash
# Initialize a new Railway project in the current directory
railway init

# Follow the interactive prompts to create a new project
# This will create a new project in your Railway account
```

#### Add Services to Your Project

For a typical Reflex application, you should add the PostgreSQL database first, then the application services:

```bash
# Step 1: Add PostgreSQL database service first (recommended for applications with database)
railway add -d postgres

# Step 2: Add application services
railway add --service frontend
railway add --service backend

# Verify the services were added
railway status

# Note: When setting up API_URL in your .env file, it should point to your backend service name
# For example, if your backend service is named 'backend', your API_URL would be 'http://backend:8080'
# This is because Railway uses the service name for internal routing
```

**Important:** Adding PostgreSQL first allows you to run database migrations before deploying your application services.

**Note:** Railway automatically names the PostgreSQL service "Postgres" when using the `-d postgres` flag.

#### PostgreSQL Database Setup

If your Reflex application requires a database, Railway provides managed PostgreSQL:

1. **Add PostgreSQL Service**:
   ```bash
   railway add -d postgres
   ```
   Railway automatically names the PostgreSQL service "Postgres" when using the database template.

2. **Database Connection**:
   - Railway automatically provides a `DATABASE_URL` environment variable
   - This variable is automatically available to all services in your project
   - Reflex applications typically use `DB_URL` variable name, which will be set automatically by the deployment script

3. **Database Configuration in Reflex**:
   - Your Reflex app should be configured to use the `DB_URL` environment variable
   - Example in your Reflex configuration:
   ```python
   import os
   
   DATABASE_URL = os.getenv("DB_URL", "sqlite:///reflex.db")  # fallback to SQLite for local dev
   ```

4. **Database Migrations**:
   After the PostgreSQL service is deployed and the connection is established, run database migrations:
   ```bash
   # Set the DB_URL environment variable (automatically done by deployment script)
   export DB_URL=$(railway variables --service Postgres --json | jq -r '.DATABASE_URL')
   
   # Run database migrations
   reflex db migrate
   ```

5. **Automatic Setup**:
   - The `deploy_all.sh` script can automatically set up PostgreSQL (enabled by default)
   - The script will also run `reflex db migrate` automatically after setting up the database
   - Use `--no-postgres` flag to skip PostgreSQL setup if not needed

#### Link to Specific Services

To work with a specific service in the current directory:

```bash
# List and connect to services in the current project
railway service 
```

#### Switch Between Environments

If you have multiple environments (like production and staging):

```bash
# List and switch between environments
railway environment
```

### Environment Setup
- Ensure you have the Railway CLI installed and configured.
- Have access to your Railway project where you want to deploy the services.

### Security and CORS Configuration
- The application uses `SecurityHeadersMiddleware` to enforce security headers and CORS policies.
- Set the `FRONTEND_DEPLOY_URL` environment variable to specify the allowed frontend origin for CORS.
- Security headers include:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `X-XSS-Protection: 1; mode=block`
  - `Referrer-Policy: strict-origin-when-cross-origin`
- CORS headers allow credentials and specify allowed methods and headers.

### Application-Specific Variables (.env file)

Create a `.env` file for your application-specific variables (API keys, secrets, etc.):

```bash
# Copy the template and edit with your app's variables
cp .env.template .env
```

Example `.env` file:
```bash
# Your application secrets (these will be set on Railway services)
OPENAI_API_KEY=sk-your-api-key-here
CLERK_SECRET_KEY=sk_test_your-clerk-secret
STRIPE_SECRET_KEY=sk_test_your-stripe-secret

# Other app-specific config
APP_NAME=my-reflex-app
ENVIRONMENT=production
```

**Important Notes:**
- ❌ **Do NOT** put `BACKEND_NAME`, `FRONTEND_NAME`, or `ENABLE_POSTGRES` in `.env`
- ❌ **Do NOT** put `REFLEX_API_URL` or `FRONTEND_DEPLOY_URL` in `.env`
- ✅ **Do** put your application secrets and configuration in `.env`
- ✅ The deployment script automatically reads your `.env` and sets variables on Railway services

### Manual Variable Management (Optional)

If you need to manually manage variables, you can use the Railway CLI:

```bash
# Set variables for a specific service
railway variables --service backend --set "OPENAI_API_KEY=sk-your-key"

# View all variables for a service
railway variables --service backend

# Set multiple variables from your .env file (done automatically by deploy_all.sh)
./set_railway_vars.sh -s backend -f .env
```

### Automated Deployment with deploy_all.sh

The easiest way to deploy your Reflex application is using the provided automated deployment script:

```bash
# Make the script executable
chmod +x deploy_all.sh

# Deploy with default settings (includes PostgreSQL)
./deploy_all.sh

# Deploy without PostgreSQL
./deploy_all.sh --no-postgres

# Deploy with custom environment file and verbose output
./deploy_all.sh -f .env.production -v

# View all available options
./deploy_all.sh --help
```

**What the script does automatically:**
1. ✅ Validates Railway CLI installation and authentication
2. ✅ Initializes Railway project if needed
3. ✅ Sets up PostgreSQL service first (optional, enabled by default)
4. ✅ Retrieves database connection URL
5. ✅ Runs database migrations (`reflex db migrate`)
6. ✅ Creates frontend and backend services
7. ✅ Configures environment variables for all services
8. ✅ Deploys backend and frontend services
9. ✅ Provides deployment summary with URLs

**Script Options:**
- `--help`: Show help message with all options
- `--no-postgres`: Skip PostgreSQL deployment
- `--postgres`: Enable PostgreSQL deployment (default)
- `-f, --file`: Specify custom environment file (default: .env)
- `-v, --verbose`: Enable verbose output
- `-d, --deploy-dir`: Specify deployment directory (default: reflex-railway-deploy)

### Manual Deployment Steps

If you prefer to deploy manually or need more control over the process:

#### Step 1: Deploy PostgreSQL First
```bash
# Add and deploy PostgreSQL service first (automatically named "Postgres")
railway add -d postgres

# Wait for deployment to complete and get DATABASE_URL
railway status --service Postgres

# Set DB_URL and run migrations
export DB_URL=$(railway variables --service Postgres --json | jq -r '.DATABASE_URL')
reflex db migrate
```

#### Step 2: Deploy Application Services
1. **Copy the Appropriate Caddyfile and Nixpacks Configuration**
   - For the backend service:
     - Copy the contents of `Caddyfile.backend` into `Caddyfile`.
     - Copy the contents of `nixpacks.backend.toml` into `nixpacks.toml`.
   - For the frontend service:
     - Copy the contents of `Caddyfile.frontend` into `Caddyfile`.
     - Copy the contents of `nixpacks.frontend.toml` into `nixpacks.toml`.

2. **Deploy Each Service Separately**
   - **Backend Service**:
     - Navigate to the directory containing your backend service files.
     - Use the Railway CLI to select the backend service:
       ```bash
       railway service
       ```
     - Deploy the backend service:
       ```bash
       railway up
       ```
   - **Frontend Service**:
     - Navigate to the directory containing your frontend service files.
     - Use the Railway CLI to select the frontend service:
       ```bash
       railway use <frontend-service-id>
       ```
     - Deploy the frontend service:
       ```bash
       railway up
       ```

### Private Networking
The backend service is available within Railway's private network at:
- Internal URL: `${BACKEND_NAME}.railway.internal`
- Service name: `${BACKEND_NAME}`

Railway automatically provides the internal URL, which will be used by default in the configuration. You don't need to manually set this as Railway handles the internal networking automatically.

Key points:
1. The internal URL is automatically provided by Railway as `BACKEND_INTERNAL_URL`
2. CORS is configured to allow:
   - Local development (`http://localhost:3000`)
   - Production frontend domain (set via `FRONTEND_ORIGIN`)
3. WebSocket connections are handled through the internal network

### Deployment Configuration Files

#### Caddyfile Configuration
The application uses separate Caddyfile configurations for frontend and backend services:

1. `Caddyfile.frontend`:
   - Located at: `railway_deployment/frontend/Caddyfile`
   - Purpose: Handles frontend routing and proxies API requests to the backend
   - Key features:
     - Serves static files from `.web/_static`
     - Routes all requests to the backend service
     - Manages error pages and fallbacks
   - Configuration:
     ```caddy
     {
         admin off
         auto_https off
     }

     :{$PORT} {
         root * .web/_static
         encode gzip
         file_server
         try_files {path} {path}.html /index.html
         reverse_proxy ${BACKEND_NAME}.railway.internal:8000
     }
     ```

### Access Your Deployed Application

Once deployed, you can access your application at:

```
https://<frontend-name>.up.railway.app
```

## Troubleshooting

### Common Issues

**Service Names Not Found**
- Check that `BACKEND_NAME` and `FRONTEND_NAME` are set correctly
- Verify services exist: `railway service list`

**Database Connection Issues**
- Ensure PostgreSQL service is deployed first
- Check `DATABASE_URL` is available: `railway variables --service Postgres`

**CORS/API Connection Issues**
- The deployment script automatically configures `REFLEX_API_URL` and `FRONTEND_DEPLOY_URL`
- Check internal communication: Backend should be accessible at `{BACKEND_NAME}.railway.internal:8080`

**Environment Variable Issues**
- **For app secrets**: Add them to your `.env` file (not as shell exports)
- **For service names**: Set as shell variables (`export BACKEND_NAME="my-backend"`)
- **For Railway variables**: These are automatic (`DATABASE_URL`, `RAILWAY_PUBLIC_DOMAIN`)

**Deployment Failures**
- Check Railway logs: `railway logs --service <service-name>`
- Verify all required variables: `railway variables --service <service-name>`
- Ensure Railway CLI is authenticated: `railway whoami`

### Debug Commands

```bash
# Check service status
railway status

# View service logs
railway logs --service backend
railway logs --service frontend

# List all variables for a service
railway variables --service backend

# Test internal connectivity (from within Railway)
# Backend should be accessible at: {BACKEND_NAME}.railway.internal:8080
```

## Complete Deployment Example

Here's a complete example of deploying a Reflex app with custom service names:

```bash
# 1. Navigate to your deployment directory
cd reflex-railway-deploy

# 2. Create your .env file with app secrets
cp .env.template .env
# Edit .env and add your OPENAI_API_KEY, CLERK_SECRET_KEY, etc.

# 3. Set custom service names (optional - defaults to "backend"/"frontend")
export BACKEND_NAME="myapp-api"
export FRONTEND_NAME="myapp-web"

# 4. Login to Railway (if not already logged in)
railway login

# 5. Deploy everything automatically
chmod +x deploy_all.sh
./deploy_all.sh

# 6. View your deployed app
# Frontend: https://myapp-web-production.up.railway.app
# Backend API: Internal to Railway network
```

**Result**: Your app will be deployed with:
- PostgreSQL service named "Postgres"  
- Backend service named "myapp-api"
- Frontend service named "myapp-web"
- All environment variables properly configured
- Internal service communication working
- CORS configured for the actual frontend domain

## Additional Resources

- [Railway Documentation](https://docs.railway.app/)
- [Reflex Documentation](https://reflex.dev/docs/)
