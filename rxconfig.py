import os
import reflex as rx

# Environment variables
backend_host = os.getenv("BACKEND_HOST", "0.0.0.0")
api_url = os.getenv("REFLEX_API_URL", "http://localhost:8000")
deploy_url = os.getenv("FRONTEND_DEPLOY_URL", os.getenv("RAILWAY_PUBLIC_DOMAIN", "http://localhost:3000"))
os.environ["FRONTEND_DEPLOY_URL"] = deploy_url

if deploy_url and not deploy_url.startswith("http"):
    deploy_url = f"https://{deploy_url}"

# CORS origins
cors_origins = [deploy_url]  # Allow the public domain for CORS
if frontend_origin := os.getenv("FRONTEND_ORIGIN"):
    cors_origins.append(frontend_origin)

# Reflex configuration
config = rx.Config(
    app_name=os.getenv("REFLEX_APP_NAME", "app"),
    api_url=api_url,  # Use root for API communication
    deploy_url=deploy_url,
    cors_allowed_origins=cors_origins,
    backend_port=int(os.getenv("PORT", "8000")),
)
