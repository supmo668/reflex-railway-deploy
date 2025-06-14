#!/bin/bash
echo "=== MINIMAL DEBUG SCRIPT ==="
echo "Current directory: $(pwd)"
echo "Railway auth:"
railway whoami || exit 1
echo "Railway status:"
railway status || exit 1
echo "Service check:"
railway variables --service spyglass-api || exit 1
echo "Env file check:"
ls -la .env || exit 1
echo "All checks passed!"
