# Video Player Template

This repository provides a template for a simple video player application using Reflex. It includes basic state management for video playback.

## Features
- Video playback with controls.

## Environment Variables

The following environment variables are used in the application:

| Variable | Description | Required | Default | Used In |
|----------|-------------|----------|---------|---------|
| `APP_NAME` | Name of the application used for internal routing | Yes | reflex_railway_deployment | Backend, Frontend |
| `FRONTEND_NAME` | Name for frontend deployment | Yes | frontend | Frontend |
| `BACKEND_NAME` | Name for backend deployment | Yes | backend | Backend |
| `FRONTEND_DEPLOY_URL` | URL for frontend deployment | Yes | - | Backend |
| `API_URL` | URL for backend API | Yes | - | Frontend |
| `FRONTEND_DOMAIN` | Domain for frontend deployment | Yes | frontend-annotation | Frontend |

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
       railway use <backend-service-id>
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

### Environment Variables for Deployment

1. Create a `.env` file with your configuration:
```bash
# Common variables
HUGGINGFACE_TOKEN=your_token_here
APP_NAME=your_app_name
FRONTEND_NAME=frontend
BACKEND_NAME=backend

# Frontend service variables
BACKEND_INTERNAL_URL=http://${BACKEND_NAME}.railway.internal:8000
RAILWAY_PUBLIC_DOMAIN=${FRONTEND_NAME}.up.railway.app  # Railway sets this automatically

# Backend service variables
BACKEND_HOST=0.0.0.0
FRONTEND_ORIGIN=https://${FRONTEND_NAME}.up.railway.app
```

2. Set variables in Railway using the CLI:
```bash
# For backend service
railway variables --service backend --set "HUGGINGFACE_TOKEN=your_token_here"
railway variables --service backend --set "BACKEND_HOST=0.0.0.0"
railway variables --service backend --set "FRONTEND_ORIGIN=https://${FRONTEND_NAME}.up.railway.app"
railway variables --service backend --set "APP_NAME=your_app_name"
railway variables --service backend --set "FRONTEND_NAME=frontend"
railway variables --service backend --set "BACKEND_NAME=backend"

# For frontend service
# Note: BACKEND_INTERNAL_URL and RAILWAY_PUBLIC_DOMAIN are automatically set by Railway
# But if needed, you can set them manually:
railway variables --service frontend --set "BACKEND_INTERNAL_URL=http://${BACKEND_NAME}.railway.internal:8000"
railway variables --service frontend --set "RAILWAY_PUBLIC_DOMAIN=${FRONTEND_NAME}.up.railway.app"
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

This template is ideal for building more complex video applications.
