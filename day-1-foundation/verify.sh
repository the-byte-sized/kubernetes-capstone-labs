#!/usr/bin/env bash
# Day 1 Foundation - Verification Script
# Checks: ConfigMap exists, Pod is Running, HTML content is accessible

set -e

echo "======================================"
echo "  Day 1: Foundation - Verification"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: ConfigMap exists
echo "[1/4] Checking ConfigMap..."
if kubectl get configmap web-html &> /dev/null; then
    echo -e "${GREEN}✅ ConfigMap 'web-html' exists${NC}"
else
    echo -e "${RED}❌ FAIL: ConfigMap 'web-html' not found${NC}"
    echo "Fix: kubectl apply -f manifests/01-configmap-html.yaml"
    exit 1
fi
echo ""

# Check 2: Pod exists
echo "[2/4] Checking Pod existence..."
if kubectl get pod web &> /dev/null; then
    echo -e "${GREEN}✅ Pod 'web' exists${NC}"
else
    echo -e "${RED}❌ FAIL: Pod 'web' not found${NC}"
    echo "Fix: kubectl apply -f manifests/02-pod-web.yaml"
    exit 1
fi
echo ""

# Check 3: Pod is Running
echo "[3/4] Checking Pod status..."
POD_STATUS=$(kubectl get pod web -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$POD_STATUS" = "Running" ]; then
    echo -e "${GREEN}✅ Pod status: Running${NC}"
elif [ "$POD_STATUS" = "Pending" ] || [ "$POD_STATUS" = "ContainerCreating" ]; then
    echo -e "${YELLOW}⚠️  Pod status: $POD_STATUS (still starting, wait a few seconds)${NC}"
    echo "Run: kubectl describe pod web"
    exit 1
else
    echo -e "${RED}❌ FAIL: Pod status: $POD_STATUS${NC}"
    echo "Diagnosis:"
    echo "  kubectl describe pod web"
    echo "  kubectl logs web"
    exit 1
fi
echo ""

# Check 4: HTML content is accessible
echo "[4/4] Checking HTML content..."
echo "Starting port-forward in background..."

# Start port-forward in background
kubectl port-forward pod/web 8080:80 > /dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to be ready
sleep 3

# Test HTTP request
if curl -s -f http://localhost:8080 | grep -q "Task Tracker"; then
    echo -e "${GREEN}✅ HTML content accessible and correct${NC}"
    CONTENT_CHECK=0
else
    echo -e "${RED}❌ FAIL: HTML content not accessible or incorrect${NC}"
    echo "Diagnosis:"
    echo "  kubectl logs web"
    echo "  kubectl describe pod web"
    CONTENT_CHECK=1
fi

# Clean up port-forward
kill $PF_PID > /dev/null 2>&1 || true
wait $PF_PID 2>/dev/null || true

echo ""

if [ $CONTENT_CHECK -eq 0 ]; then
    echo "======================================"
    echo -e "${GREEN}🎉 Day 1 verification PASSED!${NC}"
    echo "======================================"
    echo ""
    echo "Next steps:"
    echo "  1. Access the app: kubectl port-forward pod/web 8080:80"
    echo "  2. Open browser: http://localhost:8080"
    echo "  3. Review: cat day-1-foundation/troubleshooting.md"
    echo "  4. When ready: cd ../day-2-replication/"
    echo ""
    exit 0
else
    echo "======================================"
    echo -e "${RED}❌ Day 1 verification FAILED${NC}"
    echo "======================================"
    echo ""
    echo "Check troubleshooting.md for common issues."
    exit 1
fi
