FROM python:3.12

# Set environment variables for Railway deployment
ENV REDIS_URL=redis://redis 
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt* ./
COPY pyproject.toml uv.lock* ./

# Install uv and dependencies
RUN pip install uv
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; else uv sync --frozen; fi

# Copy application code
COPY . .

# Copy .env file if it exists (for configuration)
COPY .env* ./

ENTRYPOINT ["reflex", "run", "--env", "prod", "--backend-only", "--loglevel", "debug"]
