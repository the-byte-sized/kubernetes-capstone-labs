#!/bin/bash
set -e

# Day 5 Verification Script
# Checks metrics-server, HPA, load testing, and rolling update

CHECKPOINT=${1:-full}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_metrics_server() {
    echo "✓ Checking metrics-server..."
    POD_STATUS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "  ${GREEN}✅ metrics-server Pod is Running${NC}"
    else
        echo -e "  ${RED}❌ metrics-server not running (status: $POD_STATUS)${NC}"
        echo "  → Run: ./scripts/setup-metrics.sh"
        return 1
    fi
    
    # Check Metrics API
    if kubectl top nodes > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Metrics API is available${NC}"
    else
        echo -e "  ${RED}❌ Metrics API not available${NC}"
        echo "  → Wait 30s and try again"
        echo "  → Or run: ./scripts/setup-metrics.sh"
        return 1
    fi
    
    # Check kubectl top works
    POD_METRICS=$(kubectl top pods 2>&1)
    if echo "$POD_METRICS" | grep -q "<unknown>"; then
        echo -e "  ${YELLOW}⚠️  Some pods showing <unknown> metrics${NC}"
        echo "  → Wait 10-20 seconds for metrics to populate"
        return 1
    elif echo "$POD_METRICS" | grep -qE "[0-9]+m.*[0-9]+Mi"; then
        echo -e "  ${GREEN}✅ kubectl top pods works (metrics populated)${NC}"
    else
        echo -e "  ${RED}❌ kubectl top pods failed${NC}"
        echo "  → Run: kubectl top pods"
        return 1
    fi
    
    return 0
}

check_hpa_configured() {
    echo "✓ Checking HPA configuration..."
    
    if ! kubectl get hpa api-hpa > /dev/null 2>&1; then
        echo -e "  ${RED}❌ HPA 'api-hpa' not found${NC}"
        echo "  → Run: kubectl apply -f manifests/09-hpa-api.yaml"
        return 1
    fi
    
    echo -e "  ${GREEN}✅ HPA 'api-hpa' exists${NC}"
    
    # Check TARGETS are not <unknown>
    TARGETS=$(kubectl get hpa api-hpa -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo "unknown")
    
    if [ "$TARGETS" = "unknown" ] || [ -z "$TARGETS" ]; then
        echo -e "  ${YELLOW}⚠️  HPA TARGETS showing <unknown>${NC}"
        echo "  → Metrics may not be ready yet, wait 30s"
        echo "  → Check: kubectl get hpa api-hpa"
        return 1
    else
        echo -e "  ${GREEN}✅ HPA TARGETS populated (${TARGETS}%)${NC}"
    fi
    
    return 0
}

check_hpa_scaling() {
    echo "✓ Checking HPA can scale..."
    
    REPLICAS=$(kubectl get hpa api-hpa -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get hpa api-hpa -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "0")
    
    echo -e "  Current replicas: $REPLICAS, Desired: $DESIRED"
    
    if [ "$REPLICAS" -ge 1 ]; then
        echo -e "  ${GREEN}✅ HPA is managing replicas${NC}"
    else
        echo -e "  ${RED}❌ HPA not managing replicas correctly${NC}"
        echo "  → Check: kubectl describe hpa api-hpa"
        return 1
    fi
    
    # Check if it has ever scaled (DESIRED != minReplicas means it tried to scale)
    MIN=$(kubectl get hpa api-hpa -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "1")
    MAX=$(kubectl get hpa api-hpa -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "5")
    
    echo -e "  HPA range: ${MIN}-${MAX} replicas"
    
    if [ "$REPLICAS" -gt "$MIN" ]; then
        echo -e "  ${GREEN}✅ HPA has scaled up (replicas > minReplicas)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  HPA at minimum replicas (no scale-up event yet)${NC}"
        echo "  → This is OK if no load was generated yet"
        echo "  → To trigger scaling: ./scripts/generate-load.sh 50 120"
    fi
    
    return 0
}

check_rolling_update() {
    echo "✓ Checking deployment version..."
    
    IMAGE=$(kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
    
    if [[ "$IMAGE" == *":v1."* ]]; then
        echo -e "  ${GREEN}✅ Deployment using versioned image: $IMAGE${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Deployment not using versioned image: $IMAGE${NC}"
        echo "  → Expected: ghcr.io/the-byte-sized/task-api:v1.x.x"
    fi
    
    # Check rollout status
    if kubectl rollout status deployment/api-deployment --timeout=5s > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Deployment rollout complete${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Deployment rollout in progress or stuck${NC}"
        echo "  → Check: kubectl rollout status deployment/api-deployment"
    fi
    
    return 0
}

echo "================================"
echo "Day 5 Verification"
echo "================================"
echo ""

case $CHECKPOINT in
    checkpoint1)
        check_metrics_server
        ;;
    checkpoint2)
        check_metrics_server && check_hpa_configured
        ;;
    checkpoint3)
        check_metrics_server && check_hpa_configured && check_hpa_scaling
        ;;
    checkpoint4)
        check_metrics_server && check_hpa_configured && check_hpa_scaling && check_rolling_update
        ;;
    full)
        FAILED=0
        check_metrics_server || FAILED=1
        echo ""
        check_hpa_configured || FAILED=1
        echo ""
        check_hpa_scaling || FAILED=1
        echo ""
        check_rolling_update || FAILED=1
        echo ""
        
        if [ $FAILED -eq 0 ]; then
            echo "================================"
            echo -e "${GREEN}✅ All checks passed!${NC}"
            echo "================================"
            echo ""
            echo "You have successfully:"
            echo "  - Installed metrics-server for observability"
            echo "  - Configured HPA for automatic scaling"
            echo "  - Deployed versioned images for controlled updates"
            echo "  - Set up infrastructure for zero-downtime releases"
            echo ""
            echo "Next steps:"
            echo "  1. Generate load: ./scripts/generate-load.sh"
            echo "  2. Monitor scaling: ./scripts/monitor-hpa.sh"
            echo "  3. Perform rolling update to v1.1.0"
            echo "  4. Try bonus labs: Blue/Green or Canary deployments"
        else
            echo "================================"
            echo -e "${RED}❌ Some checks failed${NC}"
            echo "================================"
            echo "See troubleshooting.md for solutions"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [checkpoint1|checkpoint2|checkpoint3|checkpoint4|full]"
        echo ""
        echo "Checkpoints:"
        echo "  checkpoint1 - Metrics server working"
        echo "  checkpoint2 - HPA configured"
        echo "  checkpoint3 - HPA can scale"
        echo "  checkpoint4 - Rolling update ready"
        echo "  full        - All checks (default)"
        exit 1
        ;;
esac
