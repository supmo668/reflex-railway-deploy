# Reflex Railway Deployment

Generic deployment template for Reflex applications on Railway using Docker.

## Overview

This directory contains modular, reusable deployment scripts for deploying any Reflex application to Railway. The scripts are designed for CI/CD pipelines with no human interaction required.

**Key Features:**
- Modular shell functions in `functions/` for testability
- Hierarchical environment loading (base → env-specific → secrets)
- Automatic URL configuration for frontend/backend communication
- Backend-only secret syncing (API keys never sent to frontend)
- Default to `test` environment for safety

## Directory Structure

```
reflex-railway-deploy/
├── deploy_all.sh              # Main deployment orchestrator
├── Dockerfile.backend         # Backend service Dockerfile
├── Dockerfile.frontend        # Frontend service Dockerfile
└── functions/
    ├── logging.sh             # Color logging utilities
    ├── env.sh                 # Environment loading & variable building
    ├── railway.sh             # Railway CLI wrappers
    └── deploy.sh              # Service deployment logic
```

## Quick Start

```bash
# Deploy to test environment (default)
./reflex-railway-deploy/deploy_all.sh -p my-project

# Deploy to production
APP_ENV=prod ./reflex-railway-deploy/deploy_all.sh -p my-project -e prod

# CI/CD with token
RAILWAY_TOKEN=xxx ./reflex-railway-deploy/deploy_all.sh -p my-project -e test
```

## Usage

```
Usage: deploy_all.sh -p PROJECT [OPTIONS]

Required:
  -p, --project PROJECT     Railway project ID/name

Optional:
  -t, --team TEAM           Railway team (default: personal)
  -e, --environment ENV     Railway environment (default: test)
  -b, --backend NAME        Backend service name (default: backend)
  -n, --frontend NAME       Frontend service name (default: frontend)
  --skip-db                 Skip PostgreSQL setup and migrations
  -h, --help                Show this help

Environment:
  APP_ENV                   Controls which .env.{APP_ENV} file is loaded (default: test)
  RAILWAY_TOKEN             Railway API token (required for CI/CD)
  APP_ENV_VARS              Comma-separated list of additional env vars to sync
```

## Environment Files

The script loads environment files from `envs/` in this order:

```
envs/
├── .env.base      # Shared config (app name, theme, etc.)
├── .env.test      # Test environment settings
├── .env.prod      # Production environment settings
└── .env.secrets   # API keys (gitignored, never committed)
```

**Load order:** `.env.base` → `.env.{APP_ENV}` → `.env.secrets`

### Environment Variables Synced to Railway

**Backend Service (receives secrets):**
- `APP_ENV`, `IS_DEMO`, `LOGLEVEL`
- `REFLEX_DB_URL` (if not skipped)
- `OPENAI_API_KEY`, `CALL_LOGS_API_KEY` (from .env.secrets)
- `REFLEX_DEPLOY_URL`, `CORS_ALLOWED_ORIGINS`
- Custom vars from `APP_ENV_VARS`

**Frontend Service (no secrets):**
- `APP_ENV`, `IS_DEMO`, `LOGLEVEL`
- `REFLEX_API_URL` (backend URL)
- `REFLEX_DEPLOY_URL`
- Custom vars from `APP_ENV_VARS`

## URL Configuration

Railway automatically generates public URLs: `https://{service}-{environment}.up.railway.app`

| Service | Variable | Value |
|---------|----------|-------|
| Backend | `REFLEX_DEPLOY_URL` | `https://{backend}-{env}.up.railway.app` |
| Backend | `CORS_ALLOWED_ORIGINS` | `https://{frontend}-{env}.up.railway.app` |
| Frontend | `REFLEX_API_URL` | `https://{backend}-{env}.up.railway.app` |
| Frontend | `REFLEX_DEPLOY_URL` | `https://{frontend}-{env}.up.railway.app` |

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

# Map Railway environment to APP_ENV
case "$RAILWAY_ENVIRONMENT" in
    prod|production) export APP_ENV="prod" ;;
    *)               export APP_ENV="test" ;;
esac

# Additional app-specific variables to sync
export APP_ENV_VARS="APP_NAME,THEME_COLOR"

exec ./reflex-railway-deploy/deploy_all.sh \
    -p "$RAILWAY_PROJECT" \
    -e "$RAILWAY_ENVIRONMENT" \
    -b "$BACKEND_SERVICE" \
    -n "$FRONTEND_SERVICE"
```

## GitHub Actions Integration

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Railway

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'test'
        type: choice
        options:
          - test
          - prod

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Railway CLI
        run: npm install -g @railway/cli

      - uses: astral-sh/setup-uv@v4

      - name: Install dependencies
        run: uv sync

      - name: Make scripts executable
        run: chmod +x scripts/*.sh reflex-railway-deploy/**/*.sh

      - name: Create secrets file
        run: |
          cat > envs/.env.secrets << EOF
          OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}
          CALL_LOGS_API_KEY=${{ secrets.CALL_LOGS_API_KEY }}
          EOF

      - name: Deploy
        run: ./scripts/deploy_myapp.sh ${{ inputs.environment }}
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

## Prerequisites

1. **Railway CLI**: Install with `npm i -g @railway/cli`
2. **Railway Login**: Run `railway login` (or set `RAILWAY_TOKEN` for CI/CD)
3. **jq**: Required for JSON parsing (`apt install jq` or `brew install jq`)
4. **uv**: Python package manager (`pip install uv`)

## Troubleshooting

### Service Creation Fails
- Ensure you're logged into Railway: `railway whoami`
- Check project exists: `railway list`

### WebSocket Connection Fails
- Ensure frontend's `REFLEX_API_URL` points to backend public URL
- Check backend is running: `railway logs --service <backend-name>`

### Build Fails
- Check Dockerfile has all required system dependencies
- Ensure `pyproject.toml` and `uv.lock` exist in project root
- Check Railway logs: `railway logs --service <service-name>`

### Secrets Not Working
- Verify `.env.secrets` exists and has correct values
- Check backend logs for missing env vars
- Secrets are only synced to backend service

## Additional Resources

- [Railway Documentation](https://docs.railway.app/)
- [Railway CLI Reference](https://docs.railway.app/reference/cli-api)
- [Reflex Documentation](https://reflex.dev/docs/)
