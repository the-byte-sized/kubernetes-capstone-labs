# Day 4: Persistent Storage + Security (RBAC)

## Learning Objectives

By the end of this lab, you will be able to:
- [ ] Deploy a stateful workload with PersistentVolumeClaim (PVC)
- [ ] Verify that data survives Pod restart
- [ ] Configure applications using Secrets for credentials
- [ ] Create RBAC policies with ServiceAccount, Role, and RoleBinding
- [ ] Troubleshoot common storage and permission issues
- [ ] Explain the difference between ephemeral and persistent storage

## What We're Building

Today we're adding a **PostgreSQL database** to our Task Tracker application. This requires:
- **Persistent storage** (PVC) so data survives Pod deletions
- **Secret** for database credentials (password, user, database name)
- **New Flask API** that replaces yesterday's mock httpbin with real CRUD operations
- **RBAC controls** to demonstrate permission management

**Architecture Evolution:**
```
Day 3: [Ingress] → [nginx] + [httpbin mock]
                         ↓
Day 4: [Ingress] → [nginx] + [Flask API] → [PostgreSQL + PVC]
```

---

## Prerequisites (Self-Check)

**Run these commands before starting:**

```bash
# 1. Verify Day 3 is complete
kubectl get deploy,svc,ingress -n capstone
# Expected: web, api, capstone-ingress present

# 2. Verify StorageClass exists
kubectl get sc
# Expected: At least one StorageClass (usually 'standard')

# 3. Test Ingress works
curl http://capstone.local/api/uuid
# Expected: JSON response from httpbin
```

**If any check fails**, see `troubleshooting.md` before proceeding.

---

## Lab 4a: Persistent Database (45 minutes)

### Step 1: Understand What We're Building

We're adding PostgreSQL to store tasks persistently. The database needs:
- **Secret** for credentials (prevents passwords in YAML)
- **PVC** for persistent storage (data survives Pod deletion)
- **Service** for internal DNS (API finds DB at `postgres-service:5432`)

The API will replace yesterday's httpbin with a real Flask application that performs CRUD operations.

---

### Step 2: Apply Secret and PVC

```bash
cd day-04-storage-security/

# Create Secret first (other resources depend on it)
kubectl apply -f manifests/01-secret-postgres.yaml

# Verify Secret created
kubectl get secret postgres-secret -n capstone
# Expected: NAME=postgres-secret, TYPE=Opaque

# Create PVC (may take 10-30 seconds to bind)
kubectl apply -f manifests/02-pvc-postgres.yaml

# Watch PVC status (Ctrl+C when Bound)
kubectl get pvc -n capstone -w
# Expected: STATUS changes from Pending → Bound
```

**⚠️ If PVC stays Pending > 1 minute:**
```bash
kubectl describe pvc postgres-pvc -n capstone
# Read Events section for the cause
# Common fix: Add storageClassName to manifest (see troubleshooting.md)
```

**✅ Checkpoint 1:** Run `./verify.sh checkpoint1` (checks PVC Bound)

---

### Step 3: Deploy PostgreSQL

```bash
# Deploy Postgres Deployment and Service
kubectl apply -f manifests/03-deployment-postgres.yaml
kubectl apply -f manifests/04-service-postgres.yaml

# Wait for Pod to be Ready (may take 30-60 seconds)
kubectl get pods -n capstone -l app=postgres -w
# Expected: STATUS=Running, READY=1/1

# Check logs (should show "database system is ready")
kubectl logs -n capstone -l app=postgres --tail=20
```

**✅ Checkpoint 2:** Run `./verify.sh checkpoint2` (checks Postgres running)

---

### Step 4: Replace Mock API with Real Flask API

We're replacing yesterday's httpbin mock with a real API that connects to PostgreSQL.

```bash
# Remove old httpbin API
kubectl delete deploy api -n capstone

# Deploy new Flask API
kubectl apply -f manifests/05-deployment-api.yaml

# Service name stays the same (Ingress doesn't change)
kubectl apply -f manifests/06-service-api.yaml

# Wait for API to be Ready (may take 30s for image pull)
kubectl get pods -n capstone -l app=api -w
# Expected: READY=1/1

# Check API logs
kubectl logs -n capstone -l app=api --tail=20
# Expected: "Database schema initialized"
```

**✅ Checkpoint 3:** Run `./verify.sh checkpoint3` (checks API health)

---

### Step 5: Test CRUD Operations

```bash
# Test health endpoint
curl http://capstone.local/api/health
# Expected: {"status": "ok"}

# Create a task
curl -X POST http://capstone.local/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn Kubernetes PVC"}'
# Expected: {"id": 1, "title": "Learn Kubernetes PVC", "created_at": "..."}

# Get all tasks
curl http://capstone.local/api/tasks
# Expected: [{"id": 1, "title": "Learn Kubernetes PVC", ...}]

# Create another task
curl -X POST http://capstone.local/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Verify persistence works"}'

# Verify both tasks exist
curl http://capstone.local/api/tasks
# Expected: Array with 2 tasks
```

**⚠️ If you get 404 or 500:** See `troubleshooting.md` section "API Errors"

---

### Step 6: Verify Persistence (THE KEY TEST)

This is the most important verification: **data must survive Pod deletion**.

```bash
# Delete Postgres Pod (data should survive because of PVC)
kubectl delete pod -n capstone -l app=postgres

# Wait for new Pod to start (15-30 seconds)
kubectl get pods -n capstone -l app=postgres -w
# Watch until STATUS=Running, READY=1/1

# Query tasks again
curl http://capstone.local/api/tasks
# Expected: Same 2 tasks still there! ✅
```

**What just happened?**
- Kubernetes deleted the Pod (ephemeral)
- PVC stayed intact (persistent)
- New Pod mounted the same PVC
- Data survived → **persistence proven**

**✅ Lab 4a Complete When:**
- [ ] PVC is Bound
- [ ] You can POST and GET tasks via API
- [ ] Tasks survive Postgres Pod deletion

---

## Lab 4b: RBAC (30 minutes)

### Step 7: Create Read-Only ServiceAccount

RBAC (Role-Based Access Control) lets you define "who can do what" in Kubernetes.

We'll create a ServiceAccount with **read-only** permissions on Pods and Services.

```bash
# Apply RBAC manifest (creates SA, Role, RoleBinding)
kubectl apply -f manifests/07-rbac-readonly.yaml

# Verify resources created
kubectl get sa,role,rolebinding -n capstone
# Expected: readonly-sa, readonly-role, readonly-binding
```

**What did we just create?**
- **ServiceAccount**: An identity for processes running in Pods
- **Role**: A set of permissions (get/list on pods and services)
- **RoleBinding**: Connects the ServiceAccount to the Role

---

### Step 8: Test Permissions

```bash
# Test allowed action: get pods (should say "yes")
kubectl auth can-i get pods -n capstone \
  --as=system:serviceaccount:capstone:readonly-sa
# Expected: yes

# Test allowed action: list services (should say "yes")
kubectl auth can-i list services -n capstone \
  --as=system:serviceaccount:capstone:readonly-sa
# Expected: yes

# Test forbidden action: delete pods (should say "no")
kubectl auth can-i delete pods -n capstone \
  --as=system:serviceaccount:capstone:readonly-sa
# Expected: no ✅
```

---

### Step 9: Try a Forbidden Action (Expect 403)

Let's actually **try** to delete a Pod as this ServiceAccount (it will fail as expected).

```bash
# Get a Pod name
POD_NAME=$(kubectl get pods -n capstone -l app=api -o jsonpath='{.items[0].metadata.name}')

# Try to delete it as readonly-sa (should get 403 Forbidden)
kubectl delete pod $POD_NAME -n capstone \
  --as=system:serviceaccount:capstone:readonly-sa

# Expected error:
# Error from server (Forbidden): pods "api-xxx" is forbidden: 
# User "system:serviceaccount:capstone:readonly-sa" cannot delete resource "pods"
```

**Why is this useful?**
- The 403 error is **correct and expected**
- RBAC is working: the ServiceAccount lacks delete permission
- This is how you restrict what workloads can do

**✅ Lab 4b Complete When:**
- [ ] `can-i get pods` returns "yes"
- [ ] `can-i delete pods` returns "no"
- [ ] Actual delete attempt returns 403 Forbidden

---

## Final Verification

Run the full verification script:

```bash
./verify.sh
```

**Expected output:** All checks pass ✅

If any check fails, see `troubleshooting.md` for solutions.

---

## What You Learned (Self-Reflection)

Before moving to Day 5, make sure you can explain:

1. **What is a PVC?**  
   A claim for storage that binds to a PersistentVolume

2. **Why did PVC binding matter?**  
   Pod can't mount storage until PVC is Bound

3. **Where is the DB password stored?**  
   In a Secret, consumed as environment variable

4. **How did you verify persistence?**  
   Deleted Pod, queried DB, data survived

5. **What does the Role allow?**  
   Get/list permissions on pods and services

6. **Why did delete fail with 403?**  
   RBAC denied: delete verb not in Role

---

## Quick Debug Commands

```bash
# Storage overview
kubectl get pvc,pv,sc -n capstone

# PVC details and events
kubectl describe pvc postgres-pvc -n capstone

# Pod logs
kubectl logs -n capstone deploy/api
kubectl logs -n capstone deploy/postgres

# Service connectivity
kubectl get svc,endpoints -n capstone

# RBAC configuration
kubectl get sa,role,rolebinding -n capstone
kubectl describe rolebinding readonly-binding -n capstone

# Recent events
kubectl get events -n capstone --sort-by='.lastTimestamp'
```

---

## Troubleshooting

See `troubleshooting.md` for detailed solutions to common issues:
- PVC Pending (StorageClass missing)
- API 500 errors (DB connection issues)
- Ingress 404 (Service selector mismatch)
- RBAC 403 (RoleBinding issues)

---

## What's Next (Day 5)

Tomorrow we'll add:
- **Observability**: Logs, metrics (`kubectl top`)
- **Autoscaling**: HorizontalPodAutoscaler (HPA)
- **Deployment strategies**: Rolling updates, zero-downtime

The `resources` and `readinessProbe` we added to the API today will be crucial for autoscaling and safe deployments.

---

## Additional Resources

- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Minikube Storage](https://minikube.sigs.k8s.io/docs/handbook/persistent_volumes/)

**API Source Code:** See `docs/api-source/` for Flask implementation details (optional reading)
