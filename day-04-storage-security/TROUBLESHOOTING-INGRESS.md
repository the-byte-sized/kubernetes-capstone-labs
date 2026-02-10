# Troubleshooting Guide: Ingress Issues (Day 4)

## Common Ingress Problems

### Issue 1: Ingress Shows No ADDRESS

**Symptom**:
```bash
kubectl get ingress capstone-ingress
# ADDRESS column empty
```

**Cause**: Ingress controller not installed or not ready

**Fix**:
```bash
# Verify Ingress controller
kubectl -n ingress-nginx get pods

# If not found, install it:
minikube addons enable ingress

# Wait for controller to be ready (60-120 seconds)
kubectl -n ingress-nginx wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller --timeout=120s

# Re-check Ingress
kubectl get ingress capstone-ingress
```

---

### Issue 2: Ingress Returns 404 Not Found

**Symptom**:
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/
# 404 page not found
```

**Cause 1**: Service names mismatch

**Fix**:
```bash
# Verify service names match Ingress expectations
kubectl get svc web-service api-service

# If not found, check what exists:
kubectl get svc

# Expected: web-service and api-service (NOT task-web-service!)
# If wrong names, re-apply manifests:
kubectl apply -f manifests/06-service-api.yaml
kubectl apply -f manifests/09-service-web.yaml
```

**Cause 2**: Services not ready

**Fix**:
```bash
# Check if services have endpoints
kubectl get endpoints web-service api-service

# If no endpoints, Pods may not be ready:
kubectl get pods -l app=web
kubectl get pods -l app=api

# Wait for all Pods to be Ready (1/1)
```

---

### Issue 3: Ingress Returns 502 Bad Gateway

**Symptom**:
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/
# <html><body><h1>502 Bad Gateway</h1></body></html>
```

**Cause**: Backend Pods not Ready or failing health checks

**Fix**:
```bash
# Check Pod readiness
kubectl get pods -l app=web -o wide
kubectl get pods -l app=api -o wide

# If not Ready, check logs:
kubectl logs -l app=web --tail=30
kubectl logs -l app=api --tail=30

# Common issue: API can't connect to database
kubectl logs -l app=api | grep -i "database\|postgres\|error"

# Verify database is running:
kubectl get pods -l app=postgres
kubectl logs -l app=postgres --tail=20
```

---

### Issue 4: "capstone.local" Not Resolving

**Symptom**:
```bash
curl http://capstone.local
# curl: (6) Could not resolve host: capstone.local
```

**Cause**: Not added to /etc/hosts

**Fix**:
```bash
# Add entry to /etc/hosts
echo "$(minikube ip) capstone.local" | sudo tee -a /etc/hosts

# Verify:
ping -c 1 capstone.local

# Alternative: Use minikube IP directly with Host header
curl -H "Host: capstone.local" http://$(minikube ip)/
```

---

### Issue 5: Ingress /api Route Returns 404

**Symptom**:
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# 404 not found
```

**Cause**: api-service not found or wrong port

**Fix**:
```bash
# Verify api-service exists and has correct port
kubectl get svc api-service -o yaml | grep -A5 "ports:"

# Expected:
# - name: http
#   port: 80        <- Ingress routes to this
#   targetPort: 8080 <- Flask listens here

# If service missing:
kubectl apply -f manifests/06-service-api.yaml

# Test service directly (from within cluster):
kubectl run test --rm -it --image=curlimages/curl -- \
  curl http://api-service/api/health
```

---

### Issue 6: Ingress Works, But Frontend Shows "Cannot Connect to API"

**Symptom**: Browser loads frontend, but tasks don't load, console shows API errors

**Cause**: Frontend trying to reach API at wrong URL or API not responding

**Fix**:
```bash
# Test API via Ingress from command line:
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Should return: {"status": "healthy", ...}

# If that works, check browser console:
# Open http://capstone.local in browser
# Press F12 -> Console tab
# Look for errors like "Failed to fetch" or "CORS"

# Common issue: Mixed content (HTTPS page trying to call HTTP API)
# Solution: Both frontend and API should use same protocol

# Test API from within frontend pod:
kubectl exec -it deploy/web-deployment -- wget -qO- http://api-service/api/health
# Should return JSON
```

---

### Issue 7: Day 3 Ingress Stopped Working After Day 4

**Symptom**: Everything worked in Day 3, now Ingress returns 404/502

**Cause**: Service names changed (task-web-service instead of web-service)

**Fix**:
```bash
# Verify service names match Day 3:
kubectl get svc

# Should see:
# web-service      ClusterIP
# api-service      ClusterIP

# NOT:
# task-web-service  <- WRONG!
# task-api-service  <- WRONG!

# If wrong, delete and re-apply correct manifests:
kubectl delete svc task-web-service task-api-service 2>/dev/null || true
kubectl apply -f manifests/06-service-api.yaml
kubectl apply -f manifests/09-service-web.yaml

# Verify Ingress points to correct services:
kubectl get ingress capstone-ingress -o yaml | grep -A10 "backend:"

# Should show:
#   backend:
#     service:
#       name: web-service  # NOT task-web-service!
```

---

## Quick Diagnostic Commands

```bash
# Full Ingress status
kubectl describe ingress capstone-ingress

# Check Ingress controller logs
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=50

# Test from within cluster
kubectl run test --rm -it --image=curlimages/curl -- sh
# Inside pod:
curl http://web-service/
curl http://api-service/api/health

# Check service to pod mapping
kubectl get endpoints web-service api-service

# Verify Ingress rules
kubectl get ingress capstone-ingress -o yaml
```

---

## Still Not Working?

**Nuclear option** (clean slate):
```bash
# Delete everything and start fresh
kubectl delete ingress capstone-ingress
kubectl delete svc web-service api-service
kubectl delete deployment web-deployment api-deployment

# Re-apply in order:
kubectl apply -f manifests/05-deployment-api.yaml
kubectl apply -f manifests/06-service-api.yaml
kubectl apply -f manifests/08-deployment-web.yaml
kubectl apply -f manifests/09-service-web.yaml
kubectl apply -f manifests/10-ingress.yaml

# Wait for all Pods Ready:
kubectl wait --for=condition=ready pod --all --timeout=120s

# Test:
curl -H "Host: capstone.local" http://$(minikube ip)/
```

---

## See Also

- [README.md](./README.md) - Full lab guide
- [MIGRATION-FROM-DAY3.md](./MIGRATION-FROM-DAY3.md) - Day 3 to Day 4 transition
- [Official Ingress Docs](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Minikube Ingress Guide](https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/)
