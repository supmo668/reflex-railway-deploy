# Use Python 3.11 slim image as base
FROM python:3.11-slim

# Install system dependencies required for Reflex, pymilvus, ujson, and PostgreSQL
RUN apt-get update && apt-get install -y \
    build-essential \
    libstdc++6 \
    gcc \
    g++ \
    libpq-dev \
    postgresql-client \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN pip install uv

# Set working directory
WORKDIR /app

# Copy pyproject.toml and uv.lock for better caching
COPY pyproject.toml uv.lock* ./

# Install Python dependencies using uv
RUN uv sync --frozen

# Copy the rest of the application
COPY . .

# Set default PORT (Railway overrides this)
ENV PORT=8000

# Expose the port that Reflex backend runs on
EXPOSE 8000

# Command to run the backend
CMD ["uv", "run", "reflex", "run", "--env", "prod", "--backend-only"]
