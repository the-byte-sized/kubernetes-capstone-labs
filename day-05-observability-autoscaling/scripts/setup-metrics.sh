#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔧 Setting up metrics-server${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check minikube is running
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: minikube is not running${NC}"
    echo "Start it with: minikube start"
    exit 1
fi

# Enable metrics-server addon
echo -e "${YELLOW}Enabling metrics-server addon...${NC}"
minikube addons enable metrics-server
echo -e "${GREEN}✅ metrics-server addon enabled${NC}"
echo ""

# Wait for metrics-server Pod to be ready
echo -e "${YELLOW}⏳ Waiting for metrics-server to be ready...${NC}"
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s > /dev/null 2>&1 || true

# Check Pod status
POD_STATUS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" = "Running" ]; then
    echo -e "${GREEN}✅ metrics-server Pod is Running${NC}"
else
    echo -e "${RED}❌ metrics-server Pod not ready (status: $POD_STATUS)${NC}"
    echo "Check with: kubectl get pods -n kube-system -l k8s-app=metrics-server"
    exit 1
fi

echo ""

# Wait for Metrics API to become available
echo -e "${YELLOW}⏳ Waiting for Metrics API to become available (can take 30-60s)...${NC}"
for i in {1..30}; do
    if kubectl top nodes > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Metrics API is available${NC}"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Metrics API still not available after 60s${NC}"
        echo "This is unusual. Try:"
        echo "  1. Wait another 30s and run: kubectl top nodes"
        echo "  2. Check logs: kubectl logs -n kube-system -l k8s-app=metrics-server"
        echo "  3. Restart metrics-server: kubectl rollout restart deployment metrics-server -n kube-system"
        exit 1
    fi
    
    echo -n "."
    sleep 2
done

echo ""
echo ""

# Verify kubectl top works
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Setup complete! Testing metrics...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Node metrics:${NC}"
kubectl top nodes
echo ""

echo -e "${CYAN}Pod metrics:${NC}"
kubectl top pods 2>/dev/null || echo -e "${YELLOW}⚠️  Pods metrics not ready yet, wait 10s and run: kubectl top pods${NC}"
echo ""

echo -e "${GREEN}🎉 metrics-server is ready!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Monitor resources: kubectl top pods"
echo "  2. Continue with Lab 5.2: HPA setup"
echo ""
