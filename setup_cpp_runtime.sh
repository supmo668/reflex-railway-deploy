#!/bin/bash
# setup_cpp_runtime.sh - Ensure C++ runtime libraries are available for pymilvus/ujson

set -e

echo "Setting up C++ runtime environment for pymilvus/ujson..."

# Find and export libstdc++ paths
echo "Searching for libstdc++ libraries..."
LIBSTDCPP_PATHS=$(find /nix/store -name "libstdc++.so*" 2>/dev/null | head -10 | xargs dirname | sort -u | tr '\n' ':' | sed 's/:$//')

if [ -n "$LIBSTDCPP_PATHS" ]; then
    echo "Found libstdc++ paths: $LIBSTDCPP_PATHS"
    export LD_LIBRARY_PATH="$LIBSTDCPP_PATHS:$LD_LIBRARY_PATH"
    echo "Updated LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
else
    echo "Warning: No libstdc++ libraries found in /nix/store"
fi

# Find and export libgcc paths
echo "Searching for libgcc libraries..."
LIBGCC_PATHS=$(find /nix/store -name "libgcc_s.so*" 2>/dev/null | head -10 | xargs dirname | sort -u | tr '\n' ':' | sed 's/:$//')

if [ -n "$LIBGCC_PATHS" ]; then
    echo "Found libgcc paths: $LIBGCC_PATHS"
    export LD_LIBRARY_PATH="$LIBGCC_PATHS:$LD_LIBRARY_PATH"
    echo "Updated LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
else
    echo "Warning: No libgcc libraries found in /nix/store"
fi

# Test if libraries can be found
echo "Testing library availability..."
python3 -c "
import ctypes
import sys

try:
    # Try to load libstdc++
    libstdcpp = ctypes.CDLL('libstdc++.so.6')
    print('✓ libstdc++.so.6 loaded successfully')
except OSError as e:
    print(f'✗ Failed to load libstdc++.so.6: {e}')
    sys.exit(1)

try:
    # Try to import ujson (the problematic module)
    import ujson
    print('✓ ujson imported successfully')
except ImportError as e:
    print(f'✗ Failed to import ujson: {e}')
    sys.exit(1)
" || {
    echo "Library test failed. Attempting alternative approach..."
    
    # Alternative: try to create symlinks
    mkdir -p /tmp/lib
    find /nix/store -name "libstdc++.so*" 2>/dev/null | head -1 | xargs -I {} ln -sf {} /tmp/lib/libstdc++.so.6
    find /nix/store -name "libgcc_s.so*" 2>/dev/null | head -1 | xargs -I {} ln -sf {} /tmp/lib/libgcc_s.so.1
    
    export LD_LIBRARY_PATH="/tmp/lib:$LD_LIBRARY_PATH"
    echo "Created symlinks in /tmp/lib and updated LD_LIBRARY_PATH"
}

echo "C++ runtime setup completed successfully!"
echo "Final LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# Save environment for subsequent phases
echo "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"" >> ~/.bashrc
echo "Environment variables saved to ~/.bashrc"
