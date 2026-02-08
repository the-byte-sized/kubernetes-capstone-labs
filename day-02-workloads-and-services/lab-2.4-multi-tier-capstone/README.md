# Lab 2.4: Multi-Tier Capstone - Web → API

## 🎯 Goal

Build a **multi-tier application** where the web component communicates with an API backend using **Service discovery via DNS**. This demonstrates:
- Multi-component architecture
- Service-to-Service communication
- DNS-based service discovery
- Label-based Pod selection across tiers
- Real-world application composition

**Key learning**: Services enable loose coupling between components. Web doesn't need to know API's IP, only its Service name.

---

## 📚 Prerequisites

- ✅ Lab 2.3 completed (Service basics)
- ✅ Web Deployment with 3 replicas running
- ✅ `web-service` ClusterIP Service working
- ✅ Theory: Lezione 2 - Service discovery, DNS interno, architettura multi-tier

**Verify current state:**
```bash
kubectl get deployment web-deployment
kubectl get service web-service
kubectl get pods -l app=web
```

**Expected:** 
- Deployment `web-deployment` with 3/3 Ready
- Service `web-service` with ClusterIP
- 3 Pods Running

---

## 🏗️ Architecture Overview

### **Current state (Lab 2.3):**
```
┌─────────────────────┐
│  web-deployment     │
│  (nginx, 3 replicas)│
└──────────┬──────────┘
           │
    ┌──────▼───────┐
    │ web-service  │ (ClusterIP)
    └──────────────┘
```

### **Target state (Lab 2.4):**
```
┌─────────────────────┐          ┌─────────────────────┐
│  web-deployment     │          │  api-deployment     │
│  (nginx, 3 replicas)│──────────▶  (httpbin, 2 replicas)│
└──────────┬──────────┘   calls   └──────────┬──────────┘
           │             via DNS              │
    ┌──────▼───────┐                  ┌───────▼────────┐
    │ web-service  │                  │  api-service   │
    └──────────────┘                  └────────────────┘
     (ClusterIP)                       (ClusterIP)
```

**Traffic flow:**
1. Web Pod makes HTTP request to `http://api-service`
2. Kubernetes DNS resolves `api-service` → ClusterIP
3. ClusterIP routes to one of API Pod IPs (load-balanced)
4. API Pod processes request and responds

---

## 🧪 Lab Steps

### Step 1: Understand the API component

**We'll use `httpbin`** - a simple HTTP testing service that echoes requests.

**Why httpbin?**
- Returns structured JSON responses
- Has useful endpoints: `/get`, `/headers`, `/status/200`
- Perfect for demonstrating service-to-service calls
- No configuration needed

**Alternative:** You can use any lightweight API image (e.g., `kennethreitz/httpbin`, `ealen/echo-server`).

### Step 2: Create API Deployment manifest

Create `api-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
  namespace: task-tracker
  labels:
    app: api
    tier: backend
spec:
  replicas: 2  # Start with 2 API replicas
  selector:
    matchLabels:
      app: api
      tier: backend
  template:
    metadata:
      labels:
        app: api
        tier: backend
    spec:
      containers:
      - name: httpbin
        image: kennethreitz/httpbin:latest
        ports:
        - containerPort: 80
          name: http
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        # Readiness probe: API must be Ready to receive traffic
        readinessProbe:
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

**Key points:**
- Labels: `app=api, tier=backend` (different from web)
- 2 replicas for demonstration
- Readiness probe on `/get` endpoint
- Port 80 (httpbin default)

### Step 3: Apply API Deployment

```bash
kubectl apply -f api-deployment.yaml
```

**Expected output:**
```
deployment.apps/api-deployment created
```

Verify Deployment:
```bash
kubectl get deployment api-deployment
```

**Expected:**
```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
api-deployment   2/2     2            2           30s
```

Check Pods:
```bash
kubectl get pods -l app=api -o wide
```

**Expected:**
```
NAME                              READY   STATUS    RESTARTS   AGE   IP
api-deployment-7c8f9d5b6f-abc12   1/1     Running   0          40s   10.244.0.10
api-deployment-7c8f9d5b6f-def34   1/1     Running   0          40s   10.244.0.11
```

**Note the Pod IPs** - these are ephemeral. We'll use a Service to stabilize access.

### Step 4: Test API directly (optional)

Before creating the Service, verify API works:

```bash
kubectl run test-api --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://10.244.0.10/get
```

**Replace `10.244.0.10` with actual Pod IP from Step 3.**

**Expected output (JSON from httpbin):**
```json
{
  "args": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "10.244.0.10"
  }, 
  "origin": "10.244.0.X", 
  "url": "http://10.244.0.10/get"
}
pod "test-api" deleted
```

**Key observation:** Direct Pod IP works, but it's ephemeral!

### Step 5: Create API Service manifest

Create `api-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: task-tracker
  labels:
    app: api
spec:
  type: ClusterIP  # Internal only
  selector:
    app: api
    tier: backend  # Matches API Pods
  ports:
  - name: http
    protocol: TCP
    port: 80        # Service port
    targetPort: 80  # Container port
  sessionAffinity: None
```

**Key points:**
- Selector matches API Pod labels: `app=api, tier=backend`
- Port 80 → 80 (Service port → Pod port)
- ClusterIP (internal only)

### Step 6: Apply API Service

```bash
kubectl apply -f api-service.yaml
```

**Expected output:**
```
service/api-service created
```

Verify Service:
```bash
kubectl get service api-service
```

**Expected:**
```
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
api-service   ClusterIP   10.96.234.56    <none>        80/TCP    20s
```

Check Endpoints:
```bash
kubectl get endpoints api-service
```

**Expected:**
```
NAME          ENDPOINTS                     AGE
api-service   10.244.0.10:80,10.244.0.11:80  30s
```

**Verify:** Endpoints match the 2 API Pod IPs from Step 3.

### Step 7: Test API via Service (DNS)

**Now test using Service name instead of IP:**

```bash
kubectl run test-api-dns --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
```

**Expected output:**
```json
{
  "args": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "api-service"
  }, 
  "origin": "10.244.0.X", 
  "url": "http://api-service/get"
}
pod "test-api-dns" deleted
```

**Key observation:** Used `api-service` (DNS name), not IP! Notice `"Host": "api-service"` in response.

### Step 8: Verify DNS resolution

Test DNS explicitly:

```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```

**Expected output:**
```
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   api-service.task-tracker.svc.cluster.local
Address: 10.96.234.56  # Service ClusterIP

pod "test-dns" deleted
```

**Key observation:** DNS resolves `api-service` → ClusterIP (10.96.234.56).

### Step 9: Update web to call API (optional - advanced)

**This step is OPTIONAL**. By default, nginx serves static content. To demonstrate web → API, you can:

**Option A: Use port-forward to simulate web calling API**

From your machine:
```bash
# Terminal 1: Forward web service
kubectl port-forward service/web-service 8080:80

# Terminal 2: Forward API service
kubectl port-forward service/api-service 8081:80

# Terminal 3: Test
curl http://localhost:8080  # Web (nginx)
curl http://localhost:8081/get  # API (httpbin)
```

**Option B: Deploy a custom web image that calls API**

For a real demonstration, you would need a web app that makes backend calls. Example:
- Build a simple web app that calls `http://api-service/get` on page load
- Update `web-deployment.yaml` with the new image
- This is beyond today's scope but shows the pattern

**Option C: Manual test from web Pod**

Exec into a web Pod and call API:

```bash
# Get a web Pod name
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')

# Exec into it
kubectl exec -it $WEB_POD -- /bin/sh

# Inside the Pod, install curl (Alpine)
apk add --no-cache curl

# Call API via Service name
curl http://api-service/get

# Exit
exit
```

**Expected:** JSON response from API.

**Key observation:** Web Pod can reach API using just the Service name (`api-service`), not an IP!

### Step 10: Observe load balancing across API Pods

Run multiple requests and check which API Pod handles them:

```bash
# Make 10 requests
for i in {1..10}; do
  kubectl run test-lb-$i --image=curlimages/curl:8.11.1 --rm --restart=Never -- curl -s http://api-service/get | grep -i origin
done
```

**Expected:** Responses show different origin IPs (the Pod IPs of api-deployment).

**Check API Pod logs to see traffic:**

```bash
kubectl logs -l app=api --tail=20
```

**Expected:** Multiple API Pods received requests (load-balanced).

### Step 11: Test resilience - Delete an API Pod

Delete one API Pod:

```bash
kubectl delete pod -l app=api --field-selector metadata.name=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
```

Immediately check Endpoints:

```bash
kubectl get endpoints api-service
```

**Expected:** 
- Initially: 1 endpoint (one Pod down)
- After 5-10 seconds: 2 endpoints (Deployment auto-recreated Pod)

**Key observation:** Service automatically updates Endpoints when Pods change.

Test API during recreation:

```bash
kubectl run test-resilience --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
```

**Expected:** Still works! Traffic routed to surviving Pod.

### Step 12: Scale API and observe Endpoint changes

Scale API to 4 replicas:

```bash
kubectl scale deployment api-deployment --replicas=4
```

Watch Endpoints update:

```bash
kubectl get endpoints api-service --watch
```

**Expected:** Endpoints grow from 2 to 4 as new Pods become Ready.

**Stop watch:** Ctrl+C

Scale back:

```bash
kubectl scale deployment api-deployment --replicas=2
kubectl get endpoints api-service
```

**Expected:** Back to 2 endpoints.

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `kubectl get deployment api-deployment` shows `2/2 READY`
- [ ] `kubectl get service api-service` shows `TYPE=ClusterIP` with stable IP
- [ ] `kubectl get endpoints api-service` shows 2 Pod IPs matching `kubectl get pods -l app=api -o wide`
- [ ] DNS resolves: `nslookup api-service` returns Service ClusterIP
- [ ] API responds: `curl http://api-service/get` from test Pod returns JSON
- [ ] Web Pod can reach API: `kubectl exec` into web Pod, install curl, call `http://api-service/get` → works
- [ ] Load balancing works: Multiple requests distributed across API Pods (check logs)
- [ ] Resilience works: Delete 1 API Pod → Service still responds, Deployment recreates Pod
- [ ] Scaling works: Scale to 4 → Endpoints update; scale to 2 → Endpoints update

**If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts (Lezione 2 References)

### **Multi-tier architecture pattern**

```
Component separation:
- Web tier: presentation (nginx)
- API tier: business logic (httpbin)
- (Future: DB tier for persistence)

Communication:
- Via Service names (DNS), not IPs
- ClusterIP for internal communication
- Each tier has own Deployment + Service
```

### **Service discovery via DNS**

```yaml
# Instead of hardcoding IPs:
API_URL: "http://10.244.0.10"  # BAD - ephemeral!

# Use Service name:
API_URL: "http://api-service"  # GOOD - stable, load-balanced
```

**DNS resolution:**
- Short name (same namespace): `api-service`
- FQDN: `api-service.task-tracker.svc.cluster.local`
- Both resolve to Service ClusterIP

### **Label-based composition**

```yaml
# Web Service selects web Pods:
selector:
  app: web
  tier: frontend

# API Service selects API Pods:
selector:
  app: api
  tier: backend
```

**Key insight:** Labels enable dynamic, loosely-coupled architecture. Add/remove Pods → Endpoints auto-update.

### **Readiness and traffic flow**

```
Pod lifecycle:
1. Pod created → STATUS: ContainerCreating
2. Container starts → STATUS: Running, READY: 0/1
3. Readiness probe succeeds → READY: 1/1
4. Pod added to Service Endpoints
5. Traffic arrives

If readiness fails:
- Pod stays Running but NOT Ready (0/1)
- Service excludes Pod from Endpoints
- No traffic routed to that Pod
```

### **Why multi-tier matters (KCNA Cloud Native Architecture)**

**Benefits:**
- **Separation of concerns**: Each tier scales independently
- **Fault isolation**: Web crash doesn't affect API
- **Technology diversity**: Web=nginx, API=Python/Go/Java, DB=Postgres
- **Incremental updates**: Update API without redeploying web

**Cloud-native pattern:**
```
Monolith:            Multi-tier Kubernetes:
┌──────────────┐     ┌─────┐   ┌─────┐   ┌─────┐
│   App        │     │ Web │──▶│ API │──▶│ DB  │
│ (all-in-one) │     └─────┘   └─────┘   └─────┘
└──────────────┘      Scale     Scale     Scale
                       ↕          ↕         ↕
```

---

## 🔗 Theory Mapping

From **Lezione 2**:

| Concept (slide) | Where in lab |
|-----------------|-------------|
| Service discovery e DNS | `curl http://api-service` - no IP needed |
| Selector e EndpointSlice | API Service selector → 2 Pod IPs in Endpoints |
| ClusterIP per comunicazione interna | `web-service` and `api-service` both ClusterIP |
| Readiness probe impatta traffico | API readinessProbe → only Ready Pods get traffic |
| Auto-riparazione workload | Delete API Pod → Deployment recreates → Endpoints update |
| Scalabilità indipendente | Scale web (3→5) and API (2→4) separately |

---

## 🎉 Day 2 Definition of Done (DoD)

You now have:

✅ **Multi-tier application:**
- Web tier: 3 Pods (nginx)
- API tier: 2 Pods (httpbin)

✅ **Stable networking:**
- `web-service` ClusterIP → 3 web Pods
- `api-service` ClusterIP → 2 API Pods
- DNS resolution working for both Services

✅ **Service-to-service communication:**
- Web can call API via `http://api-service`
- API responds with JSON

✅ **Resilience demonstrated:**
- Delete Pod → auto-recreated
- Scale replicas → Endpoints auto-update
- Service continues routing during changes

✅ **Skills mastered:**
- Created multi-component application
- Used DNS for service discovery
- Verified Endpoint management
- Observed load balancing and resilience

**Next evolution (Day 3):** Add Ingress for external access, ConfigMap/Secret for configuration, and readiness/liveness tuning.

---

## 🚀 Bonus Challenges (Optional)

**Only attempt if time permits:**

### **Bonus 1: Add DB tier (preview Day 4)**

Deploy a Postgres Pod + Service:
- Deployment: `postgres:15-alpine`
- Service: `db-service`
- Test: API connects to `db-service` (via env var)

### **Bonus 2: Observability**

Add logging to see request flow:
- Check nginx access logs: `kubectl logs -l app=web --tail=20`
- Check httpbin logs: `kubectl logs -l app=api --tail=20`
- Correlate request IDs

### **Bonus 3: Namespace isolation**

Deploy a second instance in namespace `task-tracker-dev`:
- Same manifests, different namespace
- Observe DNS: `api-service.task-tracker` vs `api-service.task-tracker-dev`
- Test cross-namespace (should fail unless explicitly configured)

---

## 📚 Resources

### **Official Kubernetes Docs:**
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)

### **KCNA Alignment:**
- **Kubernetes Fundamentals (46%)**: Service discovery, multi-tier workloads
- **Cloud Native Architecture (16%)**: Microservices, loose coupling, service mesh concepts
- **Container Orchestration (22%)**: Deployment strategies, scaling

### **Related:**
- httpbin docs: https://httpbin.org/
- Lezione 2: Sezione "Networking di base" + "Service discovery"

---

**Previous**: [Lab 2.3 - Service](../lab-2.3-service/README.md)  
**Next**: [Day 3 - Networking, Ingress & Config](../../day-03-networking-ingress/README.md)
