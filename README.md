# Reflex Railway Deployment

This repository contains tools and instructions for deploying Reflex applications to Railway.

## Prerequisites

- [Railway CLI](https://docs.railway.app/develop/cli) installed
- A Reflex application ready for deployment
- A Railway account

## Quick Start

1. Clone this repository alongside your Reflex app
2. Configure your environment variables
3. Run the deployment script

## Detailed Steps

### 1. Project Setup

First, initialize your Railway project:

```bash
# Navigate to your Reflex app directory
cd your-reflex-app

# Login to Railway
railway login

# Initialize a new Railway project
railway init
```

### 2. Create Services

Create the necessary services in Railway:

```bash
# Create frontend service
railway service create frontend

# Create backend service
railway service create backend

# Link your local project to these services
railway link
```

### 3. Environment Variables for Deployment

1. Create a `.env` file by copying and modifying the template:
   ```bash
   cp .env.template .env
   # Edit .env with your specific values
   ```

   > **Important**: The `.env` file should include both Railway deployment variables AND your application-specific variables. If your app already has an `.env` file, merge the contents of `.env.template` with your existing `.env` file.

2. Configure your environment variables (example):
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
   
   # Run the script to set all variables from your .env file
   chmod +x set_railway_vars.sh
   ./set_railway_vars.sh
   ```

   This script will:
   - Set all necessary Railway configuration variables
   - Automatically configure any app-specific variables
   - Set up proper communication between frontend and backend services

4. Verify your variables in the Railway dashboard or using the CLI:
   ```bash
   railway variables --service frontend
   railway variables --service backend
   ```

### 4. Deploy Your Application

Deploy your application to Railway:

```bash
# Deploy backend
railway up --service backend

# Deploy frontend
railway up --service frontend
```

### 5. Access Your Deployed Application

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
