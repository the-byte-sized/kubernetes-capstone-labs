#!/bin/bash
set -e

# Day 4 Verification Script
# Checks PVC, Postgres, API, Frontend, Ingress, and RBAC configuration

CHECKPOINT=${1:-full}

check_pvc_bound() {
    echo "✓ Checking PVC is Bound..."
    STATUS=$(kubectl get pvc postgres-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOTFOUND")
    if [ "$STATUS" = "Bound" ]; then
        echo "  ✅ PVC Bound"
        return 0
    elif [ "$STATUS" = "Pending" ]; then
        echo "  ❌ PVC still Pending"
        echo "  → Run: kubectl describe pvc postgres-pvc"
        echo "  → See troubleshooting.md section 'PVC Pending'"
        return 1
    else
        echo "  ❌ PVC not found"
        echo "  → Run: kubectl apply -f manifests/02-pvc-postgres.yaml"
        return 1
    fi
}

check_postgres_running() {
    echo "✓ Checking Postgres is running..."
    READY=$(kubectl get pods -l app=postgres -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$READY" = "true" ]; then
        echo "  ✅ Postgres Pod ready"
        return 0
    else
        echo "  ❌ Postgres not ready"
        echo "  → Run: kubectl get pods -l app=postgres"
        echo "  → Run: kubectl logs -l app=postgres"
        return 1
    fi
}

check_api_health() {
    echo "✓ Checking API health..."
    
    # Try Ingress first
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")
    if [ -n "$MINIKUBE_IP" ]; then
        if curl -sf -H "Host: capstone.local" "http://$MINIKUBE_IP/api/health" > /dev/null 2>&1; then
            echo "  ✅ API responding via Ingress"
            return 0
        fi
    fi
    
    # Fallback to port-forward
    echo "  ⚠️ Ingress test failed, trying port-forward..."
    kubectl port-forward svc/api-service 8080:80 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    
    if curl -sf http://localhost:8080/api/health > /dev/null 2>&1; then
        echo "  ✅ API responding via port-forward"
        kill $PF_PID 2>/dev/null || true
        return 0
    else
        echo "  ❌ API not responding"
        echo "  → Run: kubectl get pods -l app=api"
        echo "  → Run: kubectl logs -l app=api"
        echo "  → See troubleshooting.md section 'API Errors'"
        kill $PF_PID 2>/dev/null || true
        return 1
    fi
}

check_frontend_running() {
    echo "✓ Checking Frontend is running..."
    READY=$(kubectl get pods -l app=web -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    READY_COUNT=$(echo "$READY" | grep -o "true" | wc -l)
    
    if [ "$READY_COUNT" -ge 3 ]; then
        echo "  ✅ Frontend Pods ready ($READY_COUNT/3)"
        return 0
    else
        echo "  ❌ Frontend not ready (found $READY_COUNT, expected 3)"
        echo "  → Run: kubectl get pods -l app=web"
        echo "  → Run: kubectl logs -l app=web"
        return 1
    fi
}

check_ingress() {
    echo "✓ Checking Ingress is configured..."
    ADDRESS=$(kubectl get ingress capstone-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -n "$ADDRESS" ]; then
        echo "  ✅ Ingress has ADDRESS: $ADDRESS"
        
        # Test web route
        MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "$ADDRESS")
        if curl -sf -H "Host: capstone.local" "http://$MINIKUBE_IP/" | grep -q "Task Tracker" 2>/dev/null; then
            echo "  ✅ Ingress / route works"
        else
            echo "  ⚠️ Ingress / route may not be ready yet"
        fi
        
        # Test API route
        if curl -sf -H "Host: capstone.local" "http://$MINIKUBE_IP/api/health" > /dev/null 2>&1; then
            echo "  ✅ Ingress /api route works"
        else
            echo "  ⚠️ Ingress /api route may not be ready yet"
        fi
        
        return 0
    else
        echo "  ❌ Ingress not ready (no ADDRESS)"
        echo "  → Run: kubectl get ingress capstone-ingress"
        echo "  → Run: kubectl describe ingress capstone-ingress"
        echo "  → See troubleshooting.md section 'Ingress Not Ready'"
        return 1
    fi
}

check_frontend_api_connectivity() {
    echo "✓ Checking Frontend can reach API..."
    
    # Test from within frontend pod
    POD=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD" ]; then
        echo "  ❌ No frontend pod found"
        return 1
    fi
    
    RESULT=$(kubectl exec "$POD" -- wget -qO- http://api-service/api/health 2>/dev/null || echo "FAILED")
    if echo "$RESULT" | grep -q "healthy"; then
        echo "  ✅ Frontend can reach API (internal DNS)"
        return 0
    else
        echo "  ❌ Frontend cannot reach API"
        echo "  → Run: kubectl get svc api-service"
        echo "  → Run: kubectl get endpoints api-service"
        echo "  → See troubleshooting.md section 'Frontend Cannot Connect'"
        return 1
    fi
}

check_rbac() {
    echo "✓ Checking RBAC..."
    CAN_GET=$(kubectl auth can-i get pods --as=system:serviceaccount:default:readonly-sa 2>/dev/null || echo "error")
    CANNOT_DELETE=$(kubectl auth can-i delete pods --as=system:serviceaccount:default:readonly-sa 2>/dev/null || echo "error")
    
    if [ "$CAN_GET" = "yes" ] && [ "$CANNOT_DELETE" = "no" ]; then
        echo "  ✅ RBAC configured correctly"
        return 0
    else
        echo "  ❌ RBAC permissions incorrect"
        echo "  → Run: kubectl get role,rolebinding"
        echo "  → Run: kubectl describe rolebinding readonly-binding"
        return 1
    fi
}

echo "================================"
echo "Day 4 Verification"
echo "================================"
echo ""

case $CHECKPOINT in
    checkpoint1)
        check_pvc_bound
        ;;
    checkpoint2)
        check_pvc_bound && check_postgres_running
        ;;
    checkpoint3)
        check_pvc_bound && check_postgres_running && check_api_health
        ;;
    checkpoint4)
        check_pvc_bound && check_postgres_running && check_api_health && check_frontend_running && check_ingress && check_frontend_api_connectivity
        ;;
    full)
        FAILED=0
        check_pvc_bound || FAILED=1
        echo ""
        check_postgres_running || FAILED=1
        echo ""
        check_api_health || FAILED=1
        echo ""
        check_frontend_running || FAILED=1
        echo ""
        check_ingress || FAILED=1
        echo ""
        check_frontend_api_connectivity || FAILED=1
        echo ""
        check_rbac || FAILED=1
        echo ""
        
        if [ $FAILED -eq 0 ]; then
            echo "================================"
            echo "✅ All checks passed!"
            echo "================================"
            echo ""
            echo "You have successfully:"
            echo "  - Deployed persistent storage with PVC"
            echo "  - Connected API to Postgres database"
            echo "  - Deployed web frontend with nginx"
            echo "  - Configured Ingress for external access"
            echo "  - Verified multi-tier connectivity"
            echo "  - Configured RBAC permissions"
            echo ""
            MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "<minikube-ip>")
            echo "Next: Test the complete stack via Ingress:"
            echo "  # Add to /etc/hosts if not already done:"
            echo "  echo \"$MINIKUBE_IP capstone.local\" | sudo tee -a /etc/hosts"
            echo ""
            echo "  # Open in browser:"
            echo "  http://capstone.local"
            echo ""
            echo "  # Or test via curl:"
            echo "  curl -H \"Host: capstone.local\" http://$MINIKUBE_IP/"
            echo "  curl -H \"Host: capstone.local\" http://$MINIKUBE_IP/api/tasks"
            echo ""
            echo "Then test persistence:"
            echo "  kubectl delete pod -l app=postgres"
            echo "  # Wait 30s, refresh browser"
            echo "  # Tasks should still be there!"
        else
            echo "================================"
            echo "❌ Some checks failed"
            echo "================================"
            echo "See troubleshooting.md for solutions"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [checkpoint1|checkpoint2|checkpoint3|checkpoint4|full]"
        echo ""
        echo "Checkpoints:"
        echo "  checkpoint1 - PVC bound"
        echo "  checkpoint2 - Postgres running"
        echo "  checkpoint3 - API healthy"
        echo "  checkpoint4 - Frontend, Ingress, and connectivity"
        echo "  full        - All checks (default)"
        exit 1
        ;;
esac
