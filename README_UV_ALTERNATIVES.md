# Alternative Nixpacks Configurations Using UV Package Manager

This directory contains alternative nixpacks configurations that use the `uv` package manager instead of pip for faster and more reliable Python dependency management.

## Files Created

- `nixpacks.frontend.alternative.toml` - Frontend configuration with uv
- `nixpacks.backend.alternative.toml` - Backend configuration with uv

## When to Use These Configurations

Use these alternative configurations when:

1. **VDSO Errors**: Getting `__vdso_gettimeofday: invalid mode for dlopen()` errors
2. **Pip Installation Issues**: Standard pip installations are failing
3. **Faster Builds**: Want faster dependency resolution and installation
4. **Better Compatibility**: Need better system library compatibility

## Key Features

### UV Package Manager Benefits:
- **10-100x faster** than pip for dependency resolution
- **Better dependency resolution** and conflict detection
- **More reliable** Git dependency handling
- **Built-in caching** for faster subsequent builds

### Configuration Features:
- **Ubuntu 22.04 base** for maximum compatibility
- **System-level installation** (`--system` flag) for proper Docker usage
- **Comprehensive system dependencies** (libstdc++6, build tools, git)
- **Automatic path configuration** for uv binary
- **Debug logging** for troubleshooting
- **Caddy integration** for reverse proxy

## How to Use

### Option 1: Replace Default Configuration
```bash
# For backend deployment
cp nixpacks.backend.alternative.toml nixpacks.toml

# For frontend deployment  
cp nixpacks.frontend.alternative.toml nixpacks.toml
```

### Option 2: Deploy Directly
```bash
# Deploy backend with alternative config
railway up --config nixpacks.backend.alternative.toml

# Deploy frontend with alternative config
railway up --config nixpacks.frontend.alternative.toml
```

### Option 3: Update Deploy Script
Modify your `deploy_all.sh` to use the alternative configurations when needed.

## Build Phases

Both configurations follow this build pipeline:

1. **python-install**: Install Python 3 and system dependencies
2. **uv-install**: Download and install uv package manager
3. **deps**: Install Python dependencies using uv
4. **reflex-setup**: Initialize Reflex application
5. **export**: Export the application (frontend-only or backend-only)
6. **caddy**: Install and configure Caddy reverse proxy

## Environment Variables

The configurations set these important variables:
- `NIXPACKS_BASE_IMAGE`: Ubuntu 22.04 for compatibility
- `DEBIAN_FRONTEND`: Non-interactive for automated installation
- `PATH`: Includes Cargo/Rust binaries for uv access

## Troubleshooting

If you still encounter issues:

1. **Check uv installation**: The build logs should show `uv --version`
2. **Verify dependencies**: Look for the Reflex version output
3. **Review system packages**: Ensure all apt packages installed successfully
4. **Check PATH**: Ensure uv is accessible in subsequent phases

## System Dependencies Included

- `python3`, `python3-pip`, `python3-venv`, `python3-dev`
- `build-essential`, `gcc`, `g++` (for compiling native extensions)
- `git` (for Git dependencies like reflex-clerk)
- `curl`, `ca-certificates` (for downloading uv and HTTPS)
- `libstdc++6` (for NumPy and scientific libraries)
- `caddy` (for reverse proxy)

## Performance Benefits

Expected improvements over standard pip:
- **Dependency resolution**: 10-100x faster
- **Download**: Parallel downloads
- **Caching**: Better build cache utilization
- **Reliability**: More robust error handling

These configurations should resolve most deployment issues while providing significantly faster build times.
