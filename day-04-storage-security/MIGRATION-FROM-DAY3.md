# Migration Guide: Day 3 → Day 4

## What Changed from Day 3?

Day 4 **maintains full continuity** with Day 3 while evolving the application.

### ✅ What Stays the Same

**Service names** (CRITICAL - Ingress depends on these):
- `web-service` (ClusterIP, port 80)
- `api-service` (ClusterIP, port 80)

**Deployment names**:
- `web-deployment` (3 replicas)
- `api-deployment` (2 replicas)

**Labels**:
- Web: `app=web tier=frontend component=capstone`
- API: `app=api tier=backend component=capstone`

**Ingress configuration**:
- Host: `capstone.local`
- Paths: `/` → web-service, `/api` → api-service
- IngressClass: `nginx`

**Namespace**: `default` (no explicit namespace in manifests)

---

### 🔄 What Evolved

**API backend implementation**:
- ❌ **Day 3**: httpbin mock container (port 80, `/get` endpoint)
- ✅ **Day 4**: Flask real API (port 8080 internally, exposed as port 80 via Service)
  - Endpoints: `/api/health`, `/api/tasks` (CRUD)
  - Connects to PostgreSQL for persistence

**New components added**:
- PostgreSQL database (new tier)
- PersistentVolumeClaim (1Gi storage)
- Secret for database credentials
- RBAC (ServiceAccount, Role, RoleBinding)
- Enhanced frontend with task management UI

---

## Clean Transition from Day 3

**Before starting Day 4**, clean up Day 3 resources to avoid conflicts:

```bash
# Remove Day 3 mock containers (keep Ingress!)
kubectl delete deployment web-deployment api-deployment

# Remove Day 3 services (they'll be recreated with correct backends)
kubectl delete service web-service api-service

# Keep Ingress - it will be reused!
# kubectl get ingress capstone-ingress  # Should still exist
```

**Why keep Ingress?**
- Day 4 uses the EXACT same Ingress configuration
- Service names unchanged: `web-service`, `api-service`
- Only the backend Pods changed (httpbin → Flask)

---

## Applying Day 4 Manifests

```bash
cd day-04-storage-security/

# Apply in order (numbered manifests)
kubectl apply -f manifests/

# Verify all resources
kubectl get all,pvc,secret,ingress
```

**Expected output**:
- ✅ Secret: `postgres-secret`
- ✅ PVC: `postgres-pvc` (Bound)
- ✅ Deployments: `postgres`, `api-deployment`, `web-deployment`
- ✅ Services: `postgres-service`, `api-service`, `web-service`
- ✅ Ingress: `capstone-ingress` (pointing to correct backends)

---

## Verifying Continuity

**Test Ingress immediately**:

```bash
# Same commands as Day 3!
curl -H "Host: capstone.local" http://$(minikube ip)/
# Expected: Frontend HTML (new Task Tracker UI)

curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Expected: {"status": "healthy", ...}
```

**In browser** (if you added `capstone.local` to /etc/hosts):
- Navigate to: `http://capstone.local`
- Expected: Full Task Tracker application

---

## Key Architecture Comparison

### Day 3 (End State)
```
[Ingress capstone.local]
      |
      ├─ / → [web-service:80] → [nginx mock, 3 pods]
      └─ /api → [api-service:80] → [httpbin mock, 2 pods]
```

### Day 4 (New State)
```
[Ingress capstone.local]  ← SAME!
      |
      ├─ / → [web-service:80] → [nginx UI, 3 pods]
      └─ /api → [api-service:80] → [Flask API, 2 pods] → [postgres:5432 + PVC]
```

**What changed**:
- Web: Mock HTML → Real Task Tracker UI
- API: httpbin → Flask with PostgreSQL
- Added: Database tier with persistent storage

**What stayed the same**:
- Ingress rules (identical!)
- Service names and ports (identical!)
- Access method: `http://capstone.local` (identical!)

---

## Common Migration Issues

### Issue: "Ingress returns 502 Bad Gateway"

**Cause**: New Pods not Ready yet

**Fix**:
```bash
# Wait for all Pods to be Ready
kubectl get pods -w

# Check API readiness specifically
kubectl get pods -l app=api -o wide
```

---

### Issue: "Service not found"

**Cause**: Service names mismatch

**Fix**: Verify service names match Ingress expectations:
```bash
kubectl get ingress capstone-ingress -o yaml | grep -A5 service
# Should show: name: web-service and name: api-service

kubectl get svc
# Should show: web-service and api-service (NOT task-web-service!)
```

---

### Issue: "API returns 500 errors"

**Cause**: Database not ready or Secret missing

**Fix**:
```bash
# Check database
kubectl get pods -l app=postgres
kubectl logs -l app=postgres --tail=20

# Check Secret
kubectl get secret postgres-secret

# Check API logs
kubectl logs -l app=api --tail=50
```

---

## Summary: Why This Matters

**Progressive learning**:
- Day 3: Learn Ingress with simple mock services
- Day 4: Keep Ingress working while adding real database and persistence
- No rework needed - just evolution

**Student experience**:
- ✅ "My Ingress still works!"
- ✅ "I just added a database to my existing app!"
- ❌ "Why did everything break? The Ingress stopped working!" ← AVOIDED

**Production mindset**:
- This mirrors real-world: evolve backends without breaking external interfaces
- Service contracts (names, ports) remain stable
- Ingress is the stable entry point

---

## Next Steps

After successful migration:
1. ✅ Verify Ingress works: `curl http://capstone.local`
2. ✅ Test persistence: Delete Postgres Pod, verify data survives
3. ✅ Explore RBAC: Test read-only ServiceAccount
4. ✅ Complete full lab: [README.md](./README.md)

**Day 5 preview**: We'll add observability (logs, metrics) and autoscaling (HPA) without breaking Ingress again!
