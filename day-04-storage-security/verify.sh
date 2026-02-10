#!/bin/bash
set -e

# Day 4 Verification Script
# Checks PVC, Postgres, API, and RBAC configuration

CHECKPOINT=${1:-full}

check_pvc_bound() {
    echo "✓ Checking PVC is Bound..."
    STATUS=$(kubectl get pvc postgres-pvc -n capstone -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOTFOUND")
    if [ "$STATUS" = "Bound" ]; then
        echo "  ✅ PVC Bound"
        return 0
    elif [ "$STATUS" = "Pending" ]; then
        echo "  ❌ PVC still Pending"
        echo "  → Run: kubectl describe pvc postgres-pvc -n capstone"
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
    READY=$(kubectl get pods -n capstone -l app=postgres -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$READY" = "true" ]; then
        echo "  ✅ Postgres Pod ready"
        return 0
    else
        echo "  ❌ Postgres not ready"
        echo "  → Run: kubectl get pods -n capstone -l app=postgres"
        echo "  → Run: kubectl logs -n capstone -l app=postgres"
        return 1
    fi
}

check_api_health() {
    echo "✓ Checking API health..."
    if curl -sf http://capstone.local/api/health > /dev/null 2>&1; then
        echo "  ✅ API responding"
        return 0
    else
        echo "  ❌ API not responding"
        echo "  → Run: kubectl get pods -n capstone -l app=api"
        echo "  → Run: kubectl logs -n capstone -l app=api"
        echo "  → See troubleshooting.md section 'API Errors'"
        return 1
    fi
}

check_rbac() {
    echo "✓ Checking RBAC..."
    CAN_GET=$(kubectl auth can-i get pods -n capstone --as=system:serviceaccount:capstone:readonly-sa)
    CANNOT_DELETE=$(kubectl auth can-i delete pods -n capstone --as=system:serviceaccount:capstone:readonly-sa)
    
    if [ "$CAN_GET" = "yes" ] && [ "$CANNOT_DELETE" = "no" ]; then
        echo "  ✅ RBAC configured correctly"
        return 0
    else
        echo "  ❌ RBAC permissions incorrect"
        echo "  → Run: kubectl get role,rolebinding -n capstone"
        echo "  → Run: kubectl describe rolebinding readonly-binding -n capstone"
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
    full)
        FAILED=0
        check_pvc_bound || FAILED=1
        echo ""
        check_postgres_running || FAILED=1
        echo ""
        check_api_health || FAILED=1
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
            echo "  - Configured RBAC permissions"
            echo ""
            echo "Next: Test persistence by running:"
            echo "  curl -X POST http://capstone.local/api/tasks -H 'Content-Type: application/json' -d '{\"title\":\"Test\"}'"
            echo "  kubectl delete pod -n capstone -l app=postgres"
            echo "  # Wait 30s"
            echo "  curl http://capstone.local/api/tasks"
            echo "  # Task should still be there!"
        else
            echo "================================"
            echo "❌ Some checks failed"
            echo "================================"
            echo "See troubleshooting.md for solutions"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [checkpoint1|checkpoint2|checkpoint3|full]"
        exit 1
        ;;
esac
