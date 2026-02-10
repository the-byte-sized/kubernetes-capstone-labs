# Day 4: Persistent Storage + Security (RBAC) + Frontend

## Learning Objectives

By the end of this lab, you will be able to:
- [ ] Deploy a stateful workload with PersistentVolumeClaim (PVC)
- [ ] Verify that data survives Pod restart
- [ ] Configure applications using Secrets for credentials
- [ ] Create RBAC policies with ServiceAccount, Role, and RoleBinding
- [ ] Deploy a multi-tier application with web frontend via Ingress
- [ ] Test the complete stack via browser interface
- [ ] Troubleshoot common storage and permission issues
- [ ] Explain the difference between ephemeral and persistent storage

## What We're Building

Today we're completing a **full-stack Task Tracker application**:
- **Persistent storage** (PVC) so data survives Pod deletions
- **Secret** for database credentials (password, user, database name)
- **Flask API** with real CRUD operations connected to PostgreSQL
- **RBAC controls** to demonstrate permission management
- **Web Frontend** (nginx) for visual interaction via browser
- **Ingress** for external access (continuity from Day 3)

**Architecture Evolution:**
```
Day 3: [Ingress capstone.local] → [web-service] + [api-service (httpbin)]
                                       ↓
Day 4: [Ingress capstone.local] → [web-service] + [api-service (Flask)] → [postgres]
       (SAME INGRESS!)              (NEW UI)       (REAL API + PVC)          (NEW TIER)
```

---

## ⚠️ Coming from Day 3?

**READ THIS FIRST**: [MIGRATION-FROM-DAY3.md](./MIGRATION-FROM-DAY3.md)

**Quick transition**:
```bash
# Clean Day 3 mock services (Ingress stays!)
kubectl delete deployment web-deployment api-deployment
kubectl delete service web-service api-service

# Apply Day 4 (uses same service names)
cd day-04-storage-security/
kubectl apply -f manifests/

# Ingress still works!
curl -H "Host: capstone.local" http://$(minikube ip)/
```

**What changed**: Backend implementation (httpbin → Flask+DB), service names UNCHANGED.

---

## Prerequisites (Self-Check)

**Run these commands before starting:**

```bash
# 1. Verify minikube is running
minikube status
# Expected: host/kubelet/apiserver Running

# 2. Verify StorageClass exists
kubectl get sc
# Expected: At least one StorageClass (usually 'standard')

# 3. Verify you can pull images
docker pull ghcr.io/the-byte-sized/task-api:latest
# Expected: Pull complete

# 4. Verify Ingress controller from Day 3
kubectl -n ingress-nginx get pods
# Expected: ingress-nginx-controller Running
```

**If any check fails**, see `troubleshooting.md` before proceeding.

---

## Lab 4a: Persistent Database (45 minutes)

### Step 1: Understand What We're Building

We're adding PostgreSQL to store tasks persistently. The database needs:
- **Secret** for credentials (prevents passwords in YAML)
- **PVC** for persistent storage (data survives Pod deletion)
- **Service** for internal DNS (API finds DB at `postgres-service:5432`)

The API is a Flask application that performs CRUD operations on PostgreSQL.

---

### Step 2: Apply Secret and PVC

```bash
cd day-04-storage-security/

# Create Secret first (other resources depend on it)
kubectl apply -f manifests/01-secret-postgres.yaml

# Verify Secret created
kubectl get secret postgres-secret
# Expected: NAME=postgres-secret, TYPE=Opaque

# Create PVC (may take 10-30 seconds to bind)
kubectl apply -f manifests/02-pvc-postgres.yaml

# Watch PVC status (Ctrl+C when Bound)
kubectl get pvc -w
# Expected: STATUS changes from Pending → Bound
```

**⚠️ If PVC stays Pending > 1 minute:**
```bash
kubectl describe pvc postgres-pvc
# Read Events section for the cause
# Common fix: Add storageClassName to manifest (see troubleshooting.md)
```

**✅ Checkpoint 1:** PVC is Bound

---

### Step 3: Deploy PostgreSQL

```bash
# Deploy Postgres Deployment and Service
kubectl apply -f manifests/03-deployment-postgres.yaml
kubectl apply -f manifests/04-service-postgres.yaml

# Wait for Pod to be Ready (may take 30-60 seconds)
kubectl get pods -l app=postgres -w
# Expected: STATUS=Running, READY=1/1

# Check logs (should show "database system is ready")
kubectl logs -l app=postgres --tail=20
```

**✅ Checkpoint 2:** Postgres Pod is Running

---

### Step 4: Deploy Flask API

```bash
# Deploy Flask API
kubectl apply -f manifests/05-deployment-api.yaml
kubectl apply -f manifests/06-service-api.yaml

# Wait for API to be Ready (may take 30s for image pull)
kubectl get pods -l app=api -w
# Expected: READY=2/2

# Check API logs
kubectl logs -l app=api --tail=20
# Expected: "Database schema initialized"
```

**✅ Checkpoint 3:** API Pods are Running (2/2)

---

### Step 5: Test CRUD Operations via Ingress

```bash
# Test API health via Ingress
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Expected: {"status": "healthy", ...}

# Create a task
curl -X POST -H "Host: capstone.local" -H "Content-Type: application/json" \
  -d '{"title": "Learn Kubernetes PVC"}' \
  http://$(minikube ip)/api/tasks
# Expected: {"id": 1, "title": "Learn Kubernetes PVC", ...}

# Get all tasks
curl -H "Host: capstone.local" http://$(minikube ip)/api/tasks
# Expected: [{"id": 1, "title": "Learn Kubernetes PVC", ...}]
```

**Alternative (if Ingress not working)**: Use port-forward:
```bash
kubectl port-forward svc/api-service 8080:80 &
curl http://localhost:8080/api/health
kill %1
```

**✅ Checkpoint 4:** Can create and retrieve tasks

---

### Step 6: Verify Persistence (THE KEY TEST)

This is the most important verification: **data must survive Pod deletion**.

```bash
# Delete Postgres Pod (data should survive because of PVC)
kubectl delete pod -l app=postgres

# Wait for new Pod to start (15-30 seconds)
kubectl get pods -l app=postgres -w
# Watch until STATUS=Running, READY=1/1

# Query tasks again via Ingress
curl -H "Host: capstone.local" http://$(minikube ip)/api/tasks
# Expected: Same task still there! ✅
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
kubectl get sa,role,rolebinding
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
kubectl auth can-i get pods \
  --as=system:serviceaccount:default:readonly-sa
# Expected: yes

# Test allowed action: list services (should say "yes")
kubectl auth can-i list services \
  --as=system:serviceaccount:default:readonly-sa
# Expected: yes

# Test forbidden action: delete pods (should say "no")
kubectl auth can-i delete pods \
  --as=system:serviceaccount:default:readonly-sa
# Expected: no ✅
```

---

### Step 9: Try a Forbidden Action (Expect 403)

Let's actually **try** to delete a Pod as this ServiceAccount (it will fail as expected).

```bash
# Get a Pod name
POD_NAME=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

# Try to delete it as readonly-sa (should get 403 Forbidden)
kubectl delete pod $POD_NAME \
  --as=system:serviceaccount:default:readonly-sa

# Expected error:
# Error from server (Forbidden): pods "api-deployment-xxx" is forbidden: 
# User "system:serviceaccount:default:readonly-sa" cannot delete resource "pods"
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

## Lab 4c: Web Frontend + Ingress (30 minutes)

### Step 10: Deploy Frontend

Now we add a **visual interface** so you can interact with the application in a browser!

```bash
# Deploy frontend nginx + service
kubectl apply -f manifests/08-deployment-web.yaml
kubectl apply -f manifests/09-service-web.yaml

# Wait for frontend to be Ready
kubectl get pods -l app=web -w
# Expected: 3 Pods, all READY=1/1

# Verify service
kubectl get svc web-service
# Expected: TYPE=ClusterIP, PORT=80
```

---

### Step 11: Deploy Ingress (if not from Day 3)

```bash
# Apply Ingress manifest (reuses Day 3 config)
kubectl apply -f manifests/10-ingress.yaml

# Verify Ingress created
kubectl get ingress capstone-ingress
# Expected: ADDRESS column populated with minikube IP

# Wait for Ingress to be ready
kubectl wait --for=condition=ready ingress capstone-ingress --timeout=60s
```

---

### Step 12: Access Frontend via Ingress

**One-time setup** (if not done in Day 3):
```bash
# Add to /etc/hosts
echo "$(minikube ip) capstone.local" | sudo tee -a /etc/hosts
```

**Access in browser**: [http://capstone.local](http://capstone.local)

**Expected**:
- Page loads with purple gradient background
- Title: "📝 Task Tracker"
- Input field to add tasks
- List of existing tasks (from Step 5)
- Bottom shows: "Frontend (nginx) → API Service (Flask) → DB Service (PostgreSQL)"

**Alternative (if Ingress not working)**: Use port-forward:
```bash
kubectl port-forward svc/web-service 8081:80
# Then open: http://localhost:8081
```

---

### Step 13: Test Frontend Functionality

**In the browser:**

1. **Type** in input field: `Deploy frontend completato`
2. **Click** "Aggiungi" button
3. **Observe**: Task appears in list with ID and timestamp

**Add more tasks:**
- `Testare persistenza dati`
- `Preparare per KCNA`
- `Configurare autoscaling (Day 5)`

**All tasks should appear immediately with auto-refresh every 5 seconds.**

---

### Step 14: Verify Multi-Tier Communication

**Test that frontend → API → DB works:**

```bash
# Check frontend logs (nginx)
kubectl logs -l app=web --tail=20
# Expected: HTTP GET/POST requests

# Check API logs (Flask)
kubectl logs -l app=api --tail=20
# Expected: API requests with 200/201 status codes

# Check database logs
kubectl logs -l app=postgres --tail=20
# Expected: SQL INSERT/SELECT queries
```

**Key observation**: Logs show full request flow across all tiers!

---

### Step 15: Test Persistence with Frontend

**The ultimate test - data survives pod restarts:**

```bash
# Delete API pod while watching browser
kubectl delete pod -l app=api

# In browser: You'll see "⚠️ Impossibile connettersi all'API" for ~10 seconds
# Then: Tasks reappear automatically when new pod is ready

# Add a new task in browser to confirm API is back
```

**What you just proved:**
- Frontend detected API failure
- Kubernetes auto-healed (recreated pod)
- Data persisted in PostgreSQL
- Application recovered automatically

---

### Step 16: Verify Complete Stack

```bash
# See all components
kubectl get all,pvc,ingress

# Expected output:
# - deployment/postgres (1/1)
# - deployment/api-deployment (2/2)
# - deployment/web-deployment (3/3)
# - service/postgres-service (ClusterIP)
# - service/api-service (ClusterIP)
# - service/web-service (ClusterIP)
# - persistentvolumeclaim/postgres-pvc (Bound)
# - ingress/capstone-ingress (capstone.local)
```

**✅ Lab 4c Complete When:**
- [ ] Browser loads frontend at http://capstone.local
- [ ] Can add tasks via UI
- [ ] Tasks appear in real-time
- [ ] Tasks persist after deleting API/DB pods
- [ ] Logs show multi-tier communication
- [ ] Ingress routing works for / and /api paths

---

## Day 4 Definition of Done

**You have successfully built a complete multi-tier application:**

✅ **Storage Layer**: PostgreSQL with 1Gi PVC (data persists)  
✅ **Security**: Database credentials in Secret (not hardcoded)  
✅ **Access Control**: RBAC with read-only ServiceAccount  
✅ **Backend**: Flask API with health checks and resource limits  
✅ **Frontend**: nginx serving web UI with API proxy  
✅ **Networking**: Services with DNS-based discovery  
✅ **Ingress**: External access via capstone.local (Day 3 continuity)  
✅ **Observability**: Logs showing request flow across tiers  

**Skills mastered today:**
- Deployed stateful workload with persistent storage
- Configured Secrets for sensitive data
- Integrated pre-built container images from ghcr.io
- Tested multi-tier communication (web → API → DB)
- Maintained Ingress continuity from Day 3
- Verified persistence and auto-healing
- Applied RBAC for security

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

7. **How does frontend reach API?**  
   Via Ingress routing /api to api-service:80

8. **Why keep same service names as Day 3?**  
   Ingress rules unchanged, seamless transition

---

## Quick Debug Commands

```bash
# Storage overview
kubectl get pvc,pv,sc

# PVC details and events
kubectl describe pvc postgres-pvc

# Pod logs
kubectl logs deploy/api-deployment --tail=50
kubectl logs deploy/postgres --tail=50
kubectl logs deploy/web-deployment --tail=50

# Service connectivity
kubectl get svc,endpoints

# RBAC configuration
kubectl get sa,role,rolebinding
kubectl describe rolebinding readonly-binding

# Frontend to API connectivity test
kubectl exec -it deploy/web-deployment -- wget -qO- http://api-service/api/health

# Ingress status
kubectl describe ingress capstone-ingress

# Recent events
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

---

## Troubleshooting

See `troubleshooting.md` for detailed solutions to common issues:
- PVC Pending (StorageClass missing)
- API 500 errors (DB connection issues)
- Frontend "Cannot connect to API" (Service discovery issues)
- Ingress 404 / 502 errors
- RBAC 403 (RoleBinding issues)

**Quick frontend checks:**
```bash
# Is frontend running?
kubectl get pods -l app=web

# Can frontend reach API?
kubectl exec -it deploy/web-deployment -- wget -qO- http://api-service/api/tasks

# Check nginx logs
kubectl logs -l app=web --tail=30

# Test Ingress routing
curl -H "Host: capstone.local" http://$(minikube ip)/
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
```

---

## What's Next (Day 5)

Tomorrow we'll enhance the existing application:
- **Ingress evolution**: Already working! Day 5 adds TLS/HTTPS
- **Observability**: Logs aggregation, metrics (`kubectl top`)
- **Autoscaling**: HorizontalPodAutoscaler (HPA)

The `resources` and `readinessProbe` we added today will be crucial for autoscaling.

**Preview of Day 5:**
```bash
# Current:
http://capstone.local

# Day 5:
https://capstone.local  # With TLS certificate!
```

---

## Additional Resources

### Official Kubernetes Docs
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

### KCNA Alignment
- **Kubernetes Fundamentals (46%)**: Storage, Services, multi-tier apps, Ingress
- **Cloud Native Architecture (16%)**: Microservices, separation of concerns
- **Container Orchestration (22%)**: StatefulSets concepts, self-healing

### Migration Guide
- **Day 3 to Day 4**: [MIGRATION-FROM-DAY3.md](./MIGRATION-FROM-DAY3.md)

### Source Code
- **API Source**: `docs/api-source/` (Flask implementation)
- **Frontend Source**: `docs/web-source/` (HTML/CSS/JS + nginx)

### Detailed Lab Guides
- **Troubleshooting guide**: `troubleshooting.md`
