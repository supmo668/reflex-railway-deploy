FROM python:3.12 AS builder

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

# Export frontend static files
RUN reflex export --frontend-only --no-zip

FROM nginx

# Copy static files from builder stage
COPY --from=builder /app/.web/_static /usr/share/nginx/html

# Copy nginx configuration
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
