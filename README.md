# Reflex Railway Deployment

Generic deployment template for Reflex applications on Railway using Docker.

## Overview

This directory contains reusable deployment scripts and Dockerfiles for deploying any Reflex application to Railway. All app-specific configuration is passed via arguments or environment variables - **no hardcoded values**.

## Files

| File | Description |
|------|-------------|
| `deploy.sh` | Generic deployment script (no hardcoded values) |
| `Dockerfile.backend` | Backend service Dockerfile |
| `Dockerfile.frontend` | Frontend service Dockerfile |

## Quick Start

```bash
# Deploy using the generic script
./reflex-railway-deploy/deploy.sh \
    -p YOUR_PROJECT \
    -e YOUR_ENVIRONMENT \
    -b YOUR_BACKEND_SERVICE \
    -f YOUR_FRONTEND_SERVICE
```

## Usage

```
Usage: deploy.sh [OPTIONS]

Required Options:
  -p, --project PROJECT       Railway project name
  -e, --environment ENV       Railway environment (e.g., test, production)
  -b, --backend SERVICE       Backend service name
  -f, --frontend SERVICE      Frontend service name

Optional Options:
  -d, --deploy-dir DIR        Deploy directory with Dockerfiles (default: reflex-railway-deploy)
      --env-file FILE         Environment file to source (default: .env)
      --skip-db               Skip PostgreSQL service lookup
      --postgres-service NAME Name of PostgreSQL service (default: Postgres)
  -h, --help                  Show this help message
```

## Environment Variables

### Automatic Variables

The deployment script automatically sets these on Railway services:

| Variable | Description |
|----------|-------------|
| `DB_URL` | PostgreSQL connection URL (from Railway Postgres service) |
| `DATABASE_URL` | Same as DB_URL (for compatibility) |
| `REFLEX_API_URL` | Backend URL for frontend to call API |
| `FRONTEND_DEPLOY_URL` | Frontend URL for CORS configuration |
| `PORT` | Service port (8000 for backend, 3000 for frontend) |

### App-Specific Variables

Set `APP_ENV_VARS` to a space-separated list of environment variable names to sync to Railway:

```bash
export APP_ENV_VARS="APP_NAME CLINIC_NAME SECRET_KEY"
export APP_NAME="My App"
export CLINIC_NAME="My Clinic"
export SECRET_KEY="super-secret"

./reflex-railway-deploy/deploy.sh -p myproject -e test -b api -f web
```

## Railway URL Convention

Railway generates public URLs in this format:
```
https://<service-name>-<environment>.up.railway.app
```

For example:
- Backend: `https://myapp-backend-test.up.railway.app`
- Frontend: `https://myapp-test.up.railway.app`

## Creating an App-Specific Wrapper

For convenience, create an app-specific script in your project's `scripts/` directory:

```bash
#!/bin/bash
# scripts/deploy_myapp.sh

export APP_ENV_VARS="APP_NAME SECRET_KEY"
export APP_NAME="My Application"

./reflex-railway-deploy/deploy.sh \
    -p myproject \
    -e "${1:-test}" \
    -b myapp-backend \
    -f myapp
```

Then deploy with:
```bash
./scripts/deploy_myapp.sh              # Deploy to test
./scripts/deploy_myapp.sh production   # Deploy to production
```

## Dockerfiles

### Backend Dockerfile

Runs `reflex run --env prod --backend-only` on port 8000.

Includes:
- Python 3.11
- Build essentials (gcc, g++)
- PostgreSQL client libraries
- unzip, curl (for Reflex/bun)
- uv package manager

### Frontend Dockerfile

Runs `reflex run --env prod --frontend-only` on port 3000.

Same dependencies as backend.

## Prerequisites

1. **Railway CLI**: Install with `npm i -g @railway/cli`
2. **Railway Login**: Run `railway login`
3. **PostgreSQL Service**: Create a Postgres service named "Postgres" in your Railway project
4. **jq**: Required for JSON parsing (`apt install jq` or `brew install jq`)

## Troubleshooting

### Service Creation Fails
- Ensure you're logged into Railway: `railway whoami`
- Check project exists: `railway list`

### Database URL Not Found
- Ensure PostgreSQL service is named "Postgres" (or use `--postgres-service NAME`)
- Check service is deployed and running

### Build Fails
- Check Dockerfile has all required system dependencies
- Ensure `pyproject.toml` and `uv.lock` exist in project root
- Check Railway logs: `railway logs --service <service-name>`

## Additional Resources

- [Railway Documentation](https://docs.railway.app/)
- [Reflex Documentation](https://reflex.dev/docs/)
