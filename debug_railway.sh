#!/bin/bash
# Debug script to identify Railway CLI issues

echo "=== Railway CLI Debug Script ==="
echo "1. Checking Railway CLI installation..."
if command -v railway &> /dev/null; then
    echo "✓ Railway CLI found: $(which railway)"
    railway --version 2>&1
else
    echo "✗ Railway CLI not found"
    exit 1
fi

echo ""
echo "2. Checking login status..."
if railway whoami &> /dev/null; then
    echo "✓ Logged in as: $(railway whoami)"
else
    echo "✗ Not logged in to Railway"
    exit 1
fi

echo ""
echo "3. Checking project context..."
echo "Current directory: $(pwd)"
if [ -f "railway.json" ]; then
    echo "✓ railway.json found"
    cat railway.json
else
    echo "⚠ No railway.json found"
fi

echo ""
echo "4. Listing available projects..."
railway list 2>&1

echo ""
echo "5. Checking project status..."
railway status 2>&1

echo ""
echo "6. Testing a simple variable set..."
echo "Attempting to set TEST_VAR=hello_world for frontend service..."
railway variables --service frontend --set "TEST_VAR=hello_world" 2>&1

echo ""
echo "7. Checking variables for frontend service..."
railway variables --service frontend 2>&1

echo "=== Debug complete ==="
