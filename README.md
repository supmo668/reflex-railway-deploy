# Video Player Template

This repository provides a template for a simple video player application using Reflex. It includes basic state management for video playback.

## Features
- Video playback with controls.

## Environment Variables

The following environment variables are used in the application:

| Variable | Description | Required for App | Required for Setup | Default | Used In |
|----------|-------------|----------------|-------------------|---------|---------|
| `APP_NAME` | Name of the application used for internal routing | No | Yes | reflex_railway_deployment | Backend, Frontend |
| `FRONTEND_NAME` | Name for frontend deployment | No | Yes | frontend | Frontend |
| `BACKEND_NAME` | Name for backend deployment | No | Yes | backend | Backend |
| `FRONTEND_DOMAIN` | Domain for frontend deployment | No | Yes | frontend-annotation | Frontend |
| `FRONTEND_DEPLOY_URL` | URL for frontend deployment | Yes | No | - | Backend |
| `API_URL` | URL for backend API (points to internal backend service name) | Yes | No | - | Frontend |


## Environment Variable Clarification

### Variables Required for Application Runtime
Only two variables are strictly necessary for the application to run properly:

- `FRONTEND_DEPLOY_URL`: The URL where your frontend is deployed (used by the backend)
- `API_URL`: The URL for your backend API (used by the frontend). it must point to the internal backend service name defined when setting up with `railway add --service backend`. For example, if your backend service is named 'backend', your API_URL would be 'http://backend:8080'.

### Variables Required for Deploymsent Setup
These variables are needed during the Railway setup process but are not required for the application to run:

- `APP_NAME`: Used for internal routing and naming
- `FRONTEND_NAME`: Used when creating the frontend service
- `BACKEND_NAME`: Used when creating the backend service
- `FRONTEND_DOMAIN`: Used for domain configuration


## Setup
1. Clone the repository.
2. Install dependencies:
```bash
pip install -r requirements.txt
```
3. Set up environment variables:
   - Copy `.env.example` to `.env`
   - Update the values in `.env` with your credentials
```bash
cp .env.example .env
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

For a typical Reflex application, you'll need both frontend and backend services:

```bash
# Add a frontend service
railway add --service frontend

# Add a backend service
railway add --service backend

# Verify the services were added
railway status

# Note: When setting up API_URL in your .env file, it should point to your backend service name
# For example, if your backend service is named 'backend', your API_URL would be 'http://backend:8080'
# This is because Railway uses the service name for internal routing
```

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

### 3. Environment Variables for Deployment

1. Create a `.env` file by copying and modifying the template:
   ```bash
   cp .env.template .env
   # Edit .env with your specific values
   ```

   > **Important**: The `.env` file should include both Railway deployment variables AND your application-specific variables. If your app already has an `.env` file, merge the contents of `.env.template` with your existing `.env` file.

2. Configure your environment variables in `.env` file (example):
   ```bash
   # Common variables
   APP_NAME=my-reflex-app
   FRONTEND_NAME=frontend
   BACKEND_NAME=backend
   
   # Your app-specific variables
   DATABASE_URL=postgresql://postgres:postgres@db.railway.internal:5432/railway
   OPENAI_API_KEY=sk-your-api-key
   ```

3. Set all variables in Railway automatically using the provided script:
   ```bash
   # Make sure you're logged in to Railway CLI first
   railway login
   
   # Make the script executable
   chmod +x set_railway_vars.sh
   
   # Run the script with your .env file for your backend service
   ./set_railway_vars.sh -s backend -f .env
   
   # Run again for your frontend service
   ./set_railway_vars.sh -s frontend -f .env
   ```

   The script supports these options:
   ```
   Options:
     -h, --help                 Show help message
     -s, --service SERVICE      Service name to update in Railway (required)
     -f, --file FILENAME        Environment file to use [default: .env]
     -v, --verbose              Enable verbose output (shows variable values)
   ```

   This script will:
   - Set only the variables defined in your .env file to the specified Railway service
   - Skip comments and empty lines in the .env file
   - Handle quoted values properly
   - Display which variables are being set (use -v to see their values)

4. Important notes about variables:
   - You'll need to run the script separately for each service
   - All variables from your .env file will be transferred to the specified service
   - Make sure your .env contains all necessary variables for both frontend and backend services
   - Remember that `API_URL` should point to your backend service name (e.g., `http://spyglass:8080`)

5. Verify your variables in the Railway dashboard or using the CLI:
   ```bash
   railway variables --service frontend
   railway variables --service backend
   ```

### Deployment Steps

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

- **Connection Issues**: Ensure that FRONTEND_ORIGIN and BACKEND_INTERNAL_URL are correctly set
- **Deployment Failures**: Check Railway logs with `railway logs --service <service-name>`
- **Environment Variables**: Verify all required variables are set with `railway variables --service <service-name>`

## Additional Resources

- [Railway Documentation](https://docs.railway.app/)
- [Reflex Documentation](https://reflex.dev/docs/)
