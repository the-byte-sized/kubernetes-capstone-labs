#!/bin/bash
set -e

# Day 5 Cleanup Script
# Reverts to Day 4 state (removes HPA, reverts to :latest images)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🧹 Day 5 Cleanup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  1. Remove HPA (api-hpa)"
echo "  2. Revert deployments to Day 4 state (:latest images)"
echo "  3. Optionally disable metrics-server"
echo ""
echo -e "${GREEN}Preserved (NOT deleted):${NC}"
echo "  - PVC and data"
echo "  - Secret"
echo "  - Services"
echo "  - Ingress"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Removing HPA...${NC}"
if kubectl get hpa api-hpa > /dev/null 2>&1; then
    kubectl delete hpa api-hpa
    echo -e "  ${GREEN}✅ HPA removed${NC}"
else
    echo -e "  ${YELLOW}⚠️  HPA not found (already removed?)${NC}"
fi

echo ""
echo -e "${BLUE}Step 2: Checking if Day 4 manifests exist...${NC}"
if [ -d "../day-04-storage-security/manifests" ]; then
    echo -e "  ${GREEN}✅ Day 4 manifests found${NC}"
    
    echo ""
    echo -e "${BLUE}Step 3: Reverting API deployment to Day 4...${NC}"
    kubectl apply -f ../day-04-storage-security/manifests/05-deployment-api.yaml
    echo -e "  ${GREEN}✅ API deployment reverted to :latest${NC}"
    
    echo ""
    echo -e "${BLUE}Step 4: Reverting Web deployment to Day 4...${NC}"
    kubectl apply -f ../day-04-storage-security/manifests/08-deployment-web.yaml
    echo -e "  ${GREEN}✅ Web deployment reverted to :latest${NC}"
    
    echo ""
    echo -e "${BLUE}Step 5: Waiting for rollouts...${NC}"
    kubectl rollout status deployment/api-deployment --timeout=60s
    kubectl rollout status deployment/web-deployment --timeout=60s
    echo -e "  ${GREEN}✅ Rollouts complete${NC}"
else
    echo -e "  ${RED}❌ Day 4 manifests not found${NC}"
    echo -e "  ${YELLOW}Manual revert needed:${NC}"
    echo "    kubectl set image deployment/api-deployment api=ghcr.io/the-byte-sized/task-api:latest"
    echo "    kubectl set image deployment/web-deployment nginx=ghcr.io/the-byte-sized/task-web:latest"
fi

echo ""
read -p "Disable metrics-server addon? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Disabling metrics-server...${NC}"
    minikube addons disable metrics-server
    echo -e "  ${GREEN}✅ metrics-server disabled${NC}"
else
    echo -e "  ${YELLOW}Keeping metrics-server enabled${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Current state:${NC}"
kubectl get deployment api-deployment web-deployment -o wide
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  - Your stack is back to Day 4 configuration"
echo "  - Data is preserved in PVC"
echo "  - To re-do Day 5: cd day-05-observability-autoscaling && kubectl apply -f manifests/"
echo ""
