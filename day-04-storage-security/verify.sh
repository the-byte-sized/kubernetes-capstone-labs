#!/bin/bash
set -e

# Day 4 Verification Script
# Checks PVC, Postgres, API, Frontend, and RBAC configuration

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
    READY=$(kubectl get pods -l app=database -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$READY" = "true" ]; then
        echo "  ✅ Postgres Pod ready"
        return 0
    else
        echo "  ❌ Postgres not ready"
        echo "  → Run: kubectl get pods -l app=database"
        echo "  → Run: kubectl logs -l app=database"
        return 1
    fi
}

check_api_health() {
    echo "✓ Checking API health..."
    
    # Port-forward in background
    kubectl port-forward svc/task-api-service 8080:8080 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    
    # Test health endpoint
    if curl -sf http://localhost:8080/api/health > /dev/null 2>&1; then
        echo "  ✅ API responding"
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
    
    if [ "$READY_COUNT" -ge 2 ]; then
        echo "  ✅ Frontend Pods ready ($READY_COUNT/2)"
        return 0
    else
        echo "  ❌ Frontend not ready"
        echo "  → Run: kubectl get pods -l app=web"
        echo "  → Run: kubectl logs -l app=web"
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
    
    RESULT=$(kubectl exec "$POD" -- wget -qO- http://task-api-service:8080/api/health 2>/dev/null || echo "FAILED")
    if echo "$RESULT" | grep -q "healthy"; then
        echo "  ✅ Frontend can reach API"
        return 0
    else
        echo "  ❌ Frontend cannot reach API"
        echo "  → Run: kubectl get svc task-api-service"
        echo "  → Run: kubectl get endpoints task-api-service"
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
        check_pvc_bound && check_postgres_running && check_api_health && check_frontend_running && check_frontend_api_connectivity
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
            echo "  - Verified multi-tier connectivity"
            echo "  - Configured RBAC permissions"
            echo ""
            echo "Next: Test the complete stack:"
            echo "  kubectl port-forward svc/task-web-service 8081:80"
            echo "  # Open http://localhost:8081 in browser"
            echo "  # Add tasks via UI and verify they appear"
            echo ""
            echo "Then test persistence:"
            echo "  kubectl delete pod -l app=database"
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
        echo "  checkpoint4 - Frontend running and connected"
        echo "  full        - All checks (default)"
        exit 1
        ;;
esac
