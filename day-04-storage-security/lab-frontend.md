# Lab 4.4: Deploy Frontend Web Interface

## 🎯 Goal

Deploy a **web frontend** to visualize and interact with the Task Tracker application in the browser. This completes the multi-tier architecture:

```
Browser → Frontend (nginx) → API (Flask) → Database (PostgreSQL)
```

**Key concepts demonstrated**:
- Multi-tier application completion
- Frontend-to-backend communication via nginx proxy
- Service discovery across tiers
- Visual validation of entire stack
- Preparation for Ingress (Day 5)

---

## 📋 Prerequisites

**Must have completed**:
- ✅ Lab 4.1: PostgreSQL with PVC (persistent storage)
- ✅ Lab 4.2: Task API with Secret (database credentials)
- ✅ Lab 4.3: RBAC configuration (optional but recommended)

**Verify current state**:
```bash
# Check all components are running
kubectl get deployments
kubectl get services
kubectl get pvc

# Expected:
# - postgres-service (ClusterIP, port 5432)
# - task-api-service (ClusterIP, port 8080)
# - postgres-data PVC (Bound)
```

**Test API is working**:
```bash
# Port-forward API
kubectl port-forward svc/task-api-service 8080:8080 &

# Test endpoints
curl http://localhost:8080/api/tasks
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Test task"}'

# Kill port-forward
kill %1
```

If API doesn't respond, troubleshoot before proceeding.

---

## 🏛️ Architecture Overview

### Current State (Lab 4.3)

```
┌────────────────────────┐
│   task-api (Flask)       │
│   Port 8080              │
└───────┬────────────────┘
        │ SQL
        ▼
┌────────────────────────┐
│   postgres (DB)          │
│   Port 5432              │
│   + PVC (1Gi)            │
└────────────────────────┘
```

### Target State (Lab 4.4)

```
┌────────────────────────┐
│   Browser              │
│   http://localhost:8080│
└───────┬─────────────────┘
        │ port-forward
        ▼
┌────────────────────────┐  ← NEW!
│   task-web (nginx)     │
│   - Serves HTML/CSS/JS │
│   - Proxies /api/*     │
│   Port 80              │
└───────┬─────────────────┘
        │ /api/* → http://task-api-service:8080
        ▼
┌────────────────────────┐
│   task-api (Flask)     │
│   Port 8080            │
└───────┬─────────────────┘
        │ SQL
        ▼
┌────────────────────────┐
│   postgres (DB)        │
│   Port 5432            │
│   + PVC (1Gi)          │
└────────────────────────┘
```

**Traffic flow**:
1. User opens browser → `http://localhost:8080`
2. kubectl port-forward → `task-web-service:80`
3. nginx serves HTML page
4. JavaScript calls `/api/tasks`
5. nginx proxies to `task-api-service:8080/api/tasks`
6. API queries PostgreSQL
7. API returns JSON
8. Browser renders tasks

---

## 🧪 Lab Steps

### Step 1: Review Frontend Image

The frontend image is pre-built and public:

**Image**: `ghcr.io/the-byte-sized/task-web:latest`

**What's inside**:
- nginx 1.27-alpine (lightweight web server)
- Single HTML page with embedded CSS/JavaScript
- nginx config that proxies `/api/*` to backend

**View source** (optional):
```bash
# See frontend code
open https://github.com/the-byte-sized/kubernetes-capstone-labs/tree/day-4-storage-security/docs/web-source
```

### Step 2: Deploy Frontend

**Apply manifests**:
```bash
# Deploy frontend deployment
kubectl apply -f manifests/08-deployment-web.yaml

# Deploy frontend service
kubectl apply -f manifests/09-service-web.yaml
```

**Expected output**:
```
deployment.apps/task-web created
service/task-web-service created
```

### Step 3: Verify Deployment

**Check deployment**:
```bash
kubectl get deployment task-web
```

**Expected**:
```
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
task-web   2/2     2            2           30s
```

**Check pods**:
```bash
kubectl get pods -l app=web
```

**Expected**:
```
NAME                        READY   STATUS    RESTARTS   AGE
task-web-7f8c9d5b6f-abc12   1/1     Running   0          35s
task-web-7f8c9d5b6f-def34   1/1     Running   0          35s
```

**Check service**:
```bash
kubectl get svc task-web-service
```

**Expected**:
```
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
task-web-service   ClusterIP   10.96.123.456   <none>        80/TCP    40s
```

### Step 4: Check Endpoints

**Verify service routing**:
```bash
kubectl get endpoints task-web-service
```

**Expected**:
```
NAME               ENDPOINTS                     AGE
task-web-service   10.244.0.20:80,10.244.0.21:80  45s
```

**Important**: Endpoints must match pod IPs from Step 3!

### Step 5: Test Frontend Health

**Test health endpoint**:
```bash
kubectl run test-web-health --rm -it --image=curlimages/curl:8.11.1 --restart=Never -- \
  curl -s http://task-web-service/health
```

**Expected output**:
```
OK
pod "test-web-health" deleted
```

### Step 6: Port-Forward to Browser

**Start port-forward**:
```bash
kubectl port-forward svc/task-web-service 8080:80
```

**Expected output**:
```
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

**Keep this terminal open!**

### Step 7: Open in Browser

**Open URL**: [http://localhost:8080](http://localhost:8080)

**Expected**:
- Page loads with gradient purple background
- Title: "📝 Task Tracker"
- Subtitle: "Kubernetes Multi-Tier Application Demo"
- Input field: "Inserisci una nuova task..."
- Button: "Aggiungi"
- Bottom info: "Frontend (nginx) → API Service (Flask) → DB Service (PostgreSQL)"

**If page doesn't load**, see [Troubleshooting](#troubleshooting) below.

### Step 8: Test Task Creation

**In the browser**:

1. **Type** in input field: `Deploy frontend completato`
2. **Click** "Aggiungi" button
3. **Observe**:
   - Green success message: "✅ Task creata con successo!"
   - Task appears in list below:
     ```
     #1  Deploy frontend completato  10/02 20:35
     ```

**Add more tasks**:
```
Configurare Ingress
Testare autoscaling
Preparare per KCNA
```

**Expected**: All tasks appear in list, numbered sequentially.

### Step 9: Verify Persistence

**Delete API pod** (to test DB persistence):
```bash
# In a NEW terminal (keep port-forward running)
kubectl delete pod -l app=api
```

**Wait 10-15 seconds** for pod to recreate.

**Check browser**: Tasks should still be visible (page auto-refreshes every 5 seconds).

**Key insight**: Data persists in PostgreSQL PVC, survives pod restarts!

### Step 10: Test Auto-Refresh

**Add task via curl** (in new terminal):
```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Task aggiunta via curl"}'
```

**Check browser**: Within 5 seconds, new task appears automatically.

**Key insight**: Frontend polls API every 5 seconds for updates.

### Step 11: Inspect Logs

**Frontend logs**:
```bash
kubectl logs -l app=web --tail=20
```

**Expected** (nginx access logs):
```
10.244.0.1 - - [10/Feb/2026:20:35:12 +0000] "GET / HTTP/1.1" 200
10.244.0.1 - - [10/Feb/2026:20:35:15 +0000] "GET /api/tasks HTTP/1.1" 200
10.244.0.1 - - [10/Feb/2026:20:35:18 +0000] "POST /api/tasks HTTP/1.1" 200
```

**API logs**:
```bash
kubectl logs -l app=api --tail=20
```

**Expected** (Flask logs):
```
INFO:werkzeug:10.244.0.20 - - [10/Feb/2026 20:35:15] "GET /api/tasks HTTP/1.1" 200
INFO:werkzeug:10.244.0.20 - - [10/Feb/2026 20:35:18] "POST /api/tasks HTTP/1.1" 201
```

---

## ✅ Verification Checklist

**Pass criteria**:

- [ ] `kubectl get deployment task-web` shows `2/2 READY`
- [ ] `kubectl get svc task-web-service` returns ClusterIP with port 80
- [ ] `kubectl get endpoints task-web-service` shows 2 pod IPs
- [ ] Health check works: `curl http://task-web-service/health` returns "OK"
- [ ] Browser loads page at `http://localhost:8080` (via port-forward)
- [ ] Can add tasks via UI, they appear in list
- [ ] Tasks persist after deleting API pod
- [ ] Auto-refresh works (tasks added via curl appear automatically)
- [ ] nginx logs show HTTP requests
- [ ] API logs show requests from nginx pod IP

**If any check fails, see [Troubleshooting](#troubleshooting)**

---

## 🛠️ Troubleshooting

### Frontend pod not starting

**Symptom**: `kubectl get pods -l app=web` shows `ImagePullBackOff` or `ErrImagePull`.

**Cause**: Cannot pull image from ghcr.io.

**Fix**:
```bash
# Verify image exists and is public
docker pull ghcr.io/the-byte-sized/task-web:latest

# If fails, check image visibility on GitHub
# https://github.com/orgs/the-byte-sized/packages/container/task-web/settings
```

### Browser shows "Cannot connect to API"

**Symptom**: Frontend loads but displays error: "⚠️ Impossibile connettersi all'API".

**Cause**: nginx cannot reach `task-api-service`.

**Fix**:
```bash
# 1. Verify API service exists
kubectl get svc task-api-service

# 2. Test from frontend pod
FRONTEND_POD=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $FRONTEND_POD -- wget -qO- http://task-api-service:8080/api/tasks

# Should return JSON array

# 3. Check nginx config
kubectl exec -it $FRONTEND_POD -- cat /etc/nginx/conf.d/default.conf | grep proxy_pass

# Should show: proxy_pass http://task-api-service:8080/api/;
```

### Port-forward fails with "address already in use"

**Symptom**: `kubectl port-forward` errors: "bind: address already in use".

**Cause**: Port 8080 is occupied.

**Fix**:
```bash
# Option 1: Use different port
kubectl port-forward svc/task-web-service 8081:80
# Then open http://localhost:8081

# Option 2: Kill existing port-forward
pkill -f "port-forward.*task-web"

# Option 3: Find and kill process on port 8080
lsof -ti:8080 | xargs kill -9
```

### Tasks don't appear after adding

**Symptom**: Click "Aggiungi" but task doesn't show.

**Cause**: API or DB issue.

**Fix**:
```bash
# 1. Check browser console (F12) for errors

# 2. Test API directly
kubectl port-forward svc/task-api-service 8082:8080 &
curl -X POST http://localhost:8082/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Test"}'

# 3. Check API logs
kubectl logs -l app=api --tail=50

# 4. Verify DB connection
kubectl exec -it deployment/task-api -- env | grep POSTGRES
```

### Page loads but is blank/white

**Symptom**: Browser shows blank page, no errors.

**Cause**: JavaScript error or wrong content type.

**Fix**:
```bash
# 1. Open browser console (F12) and check for errors

# 2. Verify nginx is serving correct file
kubectl exec -it deployment/task-web -- ls -la /usr/share/nginx/html/

# Should show: index.html

# 3. Test direct HTML access
kubectl exec -it deployment/task-web -- cat /usr/share/nginx/html/index.html | head -20

# Should show: <!DOCTYPE html>
```

---

## 🎓 Key Concepts

### Multi-Tier Architecture Complete

```
Tier         Component         Purpose                Port
----------------------------------------------------------------------
Frontend     nginx             Serve UI, proxy API    80
Backend      Flask             Business logic         8080
Data         PostgreSQL        Persistent storage     5432
```

**Benefits**:
- Each tier scales independently
- Separation of concerns (UI ≠ logic ≠ data)
- Technology diversity (nginx ≠ Python ≠ Postgres)
- Fault isolation (frontend crash ≠ API crash)

### nginx as Reverse Proxy

**Why nginx proxies `/api/*` instead of direct API access?**

1. **Same-origin policy**: Browsers block `http://localhost:8080` calling `http://task-api-service:8080` (different hosts)
2. **Simplified frontend**: JavaScript calls `/api/tasks` (relative URL), nginx handles routing
3. **Production pattern**: Common microservices architecture
4. **Ingress preparation**: Day 5 Ingress works same way (path-based routing)

**nginx.conf snippet**:
```nginx
location /api/ {
    proxy_pass http://task-api-service:8080/api/;
    # nginx transparently forwards to backend
}
```

### Service Discovery Across Tiers

**How frontend finds API**:

1. nginx config hardcodes: `http://task-api-service:8080`
2. Kubernetes DNS resolves `task-api-service` → ClusterIP
3. ClusterIP load-balances to API pod IPs
4. No IPs in config! Name-based discovery.

**Verify DNS**:
```bash
kubectl run test-dns --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup task-api-service
```

### Auto-Refresh Pattern

**Frontend polls API every 5 seconds**:

```javascript
setInterval(loadTasks, 5000);
```

**Trade-offs**:
- **Pro**: Simple, stateless, works with any backend
- **Pro**: No WebSocket complexity
- **Con**: Higher network usage vs push notifications
- **Con**: 5-second latency for updates

**For KCNA**: Polling is acceptable. Production might use WebSocket/SSE.

---

## 🔗 Day 4 Definition of Done

**You now have a COMPLETE multi-tier application**:

✅ **Storage**: PostgreSQL with 1Gi PVC (data survives pod restarts)
✅ **Security**: Database credentials in Secret (not hardcoded)
✅ **RBAC**: ServiceAccount with read-only permissions (optional)
✅ **Backend**: Flask API with health checks and readiness probes
✅ **Frontend**: nginx web UI with visual task management
✅ **Networking**: ClusterIP Services with DNS-based discovery
✅ **Observability**: Logs showing request flow across tiers

**Skills mastered**:
- Deployed stateful workload (PostgreSQL + PVC)
- Configured Secrets for sensitive data
- Integrated pre-built container images (ghcr.io)
- Tested multi-tier communication (web → API → DB)
- Used port-forward for local access
- Verified persistence and auto-healing

**Next step (Day 5)**: Expose frontend via **Ingress** for external access without port-forward!

---

## 🚀 Bonus Challenges

**Only if time permits**:

### Bonus 1: Scale Frontend Independently

```bash
# Scale frontend to 5 replicas
kubectl scale deployment task-web --replicas=5

# Watch endpoints update
kubectl get endpoints task-web-service --watch

# Verify load balancing in logs
kubectl logs -l app=web --tail=5 --prefix
```

**Observation**: Frontend scales without affecting API or DB.

### Bonus 2: Test Failure Scenarios

```bash
# Kill DB pod
kubectl delete pod -l app=database

# Frontend shows: "⚠️ Impossibile connettersi all'API"
# Wait 30 seconds for pod recreation
# Frontend auto-recovers
```

**Observation**: Kubernetes auto-heals, application resilient.

### Bonus 3: Inspect Network Traffic

```bash
# Capture traffic between frontend and API
kubectl run tcpdump --rm -it --image=nicolaka/netshoot --restart=Never -- \
  tcpdump -i any -n "host task-api-service" -A

# In browser, add a task
# See HTTP POST in tcpdump output
```

---

## 📚 Resources

### Official Kubernetes Docs
- [Services and Networking](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [kubectl port-forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

### KCNA Alignment
- **Kubernetes Fundamentals (46%)**: Multi-tier workloads, Services, DNS
- **Cloud Native Architecture (16%)**: Microservices, separation of concerns
- **Container Orchestration (22%)**: Scaling, self-healing

### Related
- Frontend source: `docs/web-source/`
- API source: `docs/api-source/`
- Troubleshooting: `day-04-storage-security/troubleshooting.md`

---

**Previous**: [Lab 4.3 - RBAC Security](./README.md#lab-43-rbac)  
**Next**: [Day 5 - Observability & Ingress](../day-05-observability-ingress/README.md)
