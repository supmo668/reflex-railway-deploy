# Reflex Railway Deployment

Generic deployment template for Reflex applications on Railway using Docker.

## Overview

This directory contains reusable deployment scripts and Dockerfiles for deploying any Reflex application to Railway. All app-specific configuration is passed via arguments or environment variables - **no hardcoded values**.

## Files

| File | Description |
|------|-------------|
| `deploy_all.sh` | Main deployment script (no hardcoded values) |
| `Dockerfile.backend` | Backend service Dockerfile |
| `Dockerfile.frontend` | Frontend service Dockerfile |

## Quick Start

```bash
# Deploy using the generic script
./reflex-railway-deploy/deploy_all.sh \
    -p YOUR_PROJECT \
    -e YOUR_ENVIRONMENT \
    -b YOUR_BACKEND_SERVICE \
    -n YOUR_FRONTEND_SERVICE \
    --skip-db \
    -y
```

## Usage

```
Usage: deploy_all.sh [OPTIONS]

Required Options:
  -p, --project PROJECT       Railway project name
  -e, --environment ENV       Railway environment (e.g., test, production)
  -b, --backend SERVICE       Backend service name
  -n, --frontend SERVICE      Frontend service name

Optional Options:
  -d, --deploy-dir DIR        Deploy directory with Dockerfiles (default: reflex-railway-deploy)
  -t, --team TEAM             Railway team (for team projects)
      --skip-db               Skip PostgreSQL service setup (for demo mode)
  -y, --yes                   Auto mode (skip confirmation pauses)
  -h, --help                  Show this help message
```

## URL Configuration

### Railway URL Convention

Railway generates public URLs in this format:
```
https://<service-name>-<environment>.up.railway.app
```

For example with `--backend myapp-backend --frontend myapp -e test`:
- Backend: `https://myapp-backend-test.up.railway.app`
- Frontend: `https://myapp-test.up.railway.app`

### Environment Variables Per Service

The deploy script automatically sets these variables based on service names:

**Backend Service:**
| Variable | Value | Description |
|----------|-------|-------------|
| `REFLEX_API_URL` | `http://localhost:8000` | Backend talks to itself locally |
| `REFLEX_DEPLOY_URL` | `https://<backend>-<env>.up.railway.app` | Backend's public URL |
| `CORS_ALLOWED_ORIGINS` | `https://<frontend>-<env>.up.railway.app` | Frontend URL for CORS |

**Frontend Service:**
| Variable | Value | Description |
|----------|-------|-------------|
| `REFLEX_API_URL` | `https://<backend>-<env>.up.railway.app` | Backend URL for API/WebSocket |
| `REFLEX_DEPLOY_URL` | `https://<frontend>-<env>.up.railway.app` | Frontend's own public URL |

### Internal Railway Communication

For service-to-service communication within Railway, you can use the internal URL:
```
<service-name>.railway.internal
```

## Environment Files

The script loads environment files from the `envs/` directory:
```
envs/
├── .env.base      # Shared config (app name, theme, etc.)
├── .env.prod      # Production settings (loaded for Railway)
└── .env.secrets   # API keys (gitignored)
```

### App-Specific Variables

Set `APP_ENV_VARS` to a comma-separated list of variable names to sync:

```bash
export APP_ENV_VARS="APP_NAME,CLINIC_NAME,THEME_COLOR"
```

## Creating an App-Specific Wrapper

Create an app-specific script in your project's `scripts/` directory:

```bash
#!/bin/bash
# scripts/deploy_myapp.sh
set -e

RAILWAY_PROJECT="my-project"
RAILWAY_ENVIRONMENT="${1:-test}"
BACKEND_SERVICE="myapp-backend"
FRONTEND_SERVICE="myapp"

export APP_ENV_VARS="APP_NAME,SECRET_KEY"

./reflex-railway-deploy/deploy_all.sh \
    -p "$RAILWAY_PROJECT" \
    -e "$RAILWAY_ENVIRONMENT" \
    -b "$BACKEND_SERVICE" \
    -n "$FRONTEND_SERVICE" \
    --skip-db \
    -y
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
