# Lab 3.1: DNS & Service Discovery

## 🎯 Goal

Verify that **DNS-based service discovery** works in your cluster and practice troubleshooting when it doesn't.

**Key learning**: In cloud-native systems, components depend on names (Service DNS), not ephemeral IPs. When "something doesn't work," the first two questions are:
1. **Does the name resolve?** (DNS working?)
2. **Are there endpoints?** (Backend Pods Ready?)

If either answer is "no," the problem is before any application logs.

---

## 📚 Prerequisites

✅ **Day 2 completed (Lab 2.4 - Multi-Tier Capstone)**:
- `web-deployment` with 3 replicas Running
- `web-service` ClusterIP Service created
- `api-deployment` with 2 replicas Running
- `api-service` ClusterIP Service created

**Verify:**
```bash
kubectl get deployment
kubectl get service
kubectl get pods -o wide
```

**Expected:**
```
NAME             READY   UP-TO-DATE   AVAILABLE
web-deployment   3/3     3            3
api-deployment   2/2     2            2

NAME          TYPE        CLUSTER-IP      PORT(S)
web-service   ClusterIP   10.96.123.45    80/TCP
api-service   ClusterIP   10.96.234.56    80/TCP
```

---

## 🧪 Lab Steps

### Step 1: Verify DNS resolution - api-service

Test if `api-service` DNS name resolves:

```bash
kubectl run test-dns-api --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```

**Expected output:**
```
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   api-service.default.svc.cluster.local
Address: 10.96.234.56

pod "test-dns-api" deleted
```

**Key observations:**
- DNS server: `10.96.0.10` (CoreDNS Service ClusterIP)
- Full DNS name: `api-service.default.svc.cluster.local`
- Resolved IP: `10.96.234.56` (matches `kubectl get svc api-service`)

**If this fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Issue 1**

---

### Step 2: Verify DNS resolution - web-service

Repeat for `web-service`:

```bash
kubectl run test-dns-web --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
```

**Expected:**
```
Name:   web-service.default.svc.cluster.local
Address: 10.96.123.45  # Your web-service ClusterIP
```

**Pattern:** Every Service gets a DNS entry: `<service-name>.<namespace>.svc.cluster.local`

---

### Step 3: Test connectivity via DNS - api-service

DNS resolution is necessary but not sufficient. Now test actual connectivity:

```bash
kubectl run test-curl-api --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl -v http://api-service/get
```

**Expected output:**
```
* Connected to api-service (10.96.234.56) port 80
> GET /get HTTP/1.1
> Host: api-service
...
< HTTP/1.1 200 OK
{
  "args": {},
  "headers": {
    "Host": "api-service",
    ...
  },
  "url": "http://api-service/get"
}
pod "test-curl-api" deleted
```

**Key observations:**
- Connected to ClusterIP (10.96.234.56)
- Request sent to Service name
- Response received from one of the API Pods (load-balanced)

**If you get a timeout or connection refused, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Issue 2**

---

### Step 4: Inspect Service endpoints

When DNS resolves but doesn't respond, check endpoints:

```bash
kubectl get endpoints api-service
```

**Expected:**
```
NAME          ENDPOINTS                       AGE
api-service   10.244.0.10:80,10.244.0.11:80   10m
```

**Modern approach (Kubernetes v1.35):** Use EndpointSlice:

```bash
kubectl get EndpointSlice -l kubernetes.io/service-name=api-service
```

**Expected:**
```
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS                    AGE
api-service-abc123    IPv4          80      10.244.0.10,10.244.0.11      10m
```

Detailed view:

```bash
kubectl get EndpointSlice -l kubernetes.io/service-name=api-service -o yaml | grep -A 5 addresses:
```

**Expected:**
```yaml
endpoints:
- addresses:
  - 10.244.0.10
  conditions:
    ready: true
    ...
- addresses:
  - 10.244.0.11
  conditions:
    ready: true
```

**Key insight:** Endpoints are the **factual proof** of "where traffic goes." Empty endpoints = traffic can't work.

---

### Step 5: Cross-tier communication (web → api)

Now test from within the web Pod (simulating real application behavior):

```bash
# Get a web Pod name
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')

# Exec into it
kubectl exec -it $WEB_POD -- sh

# Inside the web Pod (nginx Alpine), install curl
apk add --no-cache curl

# Call API using Service name
curl http://api-service/get

# Exit
exit
```

**Expected:** JSON response from api-service.

**Key observation:** Web doesn't know (and doesn't care) about API Pod IPs. It uses the stable Service name.

---

### Step 6: Test with FQDN (Fully Qualified Domain Name)

Short names work within the same namespace. Test FQDN:

```bash
kubectl run test-fqdn --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service.default.svc.cluster.local/get
```

**Expected:** Same JSON response.

**DNS resolution hierarchy:**
```
1. api-service              ← Works in same namespace (default)
2. api-service.default      ← Works from any namespace
3. api-service.default.svc  ← More explicit
4. api-service.default.svc.cluster.local  ← FQDN (always works)
```

**Best practice:** Use short name in same namespace; use FQDN for cross-namespace calls.

---

### Step 7: Observe load balancing

Make multiple requests and check which API Pod handles them:

```bash
# Make 10 requests
for i in {1..10}; do
  kubectl run test-lb-$i --image=curlimages/curl:8.11.1 --rm --restart=Never -- \
    curl -s http://api-service/get | grep '"origin"'
done
```

**Expected:** Responses show different origin IPs (distributed across 2 API Pods).

Check API Pod logs:

```bash
kubectl logs -l app=api --tail=30
```

**Expected:** Multiple Pods received requests (kube-proxy load-balanced traffic).

---

### Step 8: Test namespace isolation (optional)

Create a second namespace and test DNS scope:

```bash
# Create test namespace
kubectl create namespace test-ns

# Try to resolve api-service from different namespace
kubectl run test-cross-ns --image=busybox:1.36 --rm -it --restart=Never -n test-ns -- \
  nslookup api-service
```

**Expected:** Fails or resolves to nothing (no `api-service` in `test-ns`).

Now try FQDN:

```bash
kubectl run test-cross-ns-fqdn --image=busybox:1.36 --rm -it --restart=Never -n test-ns -- \
  nslookup api-service.default.svc.cluster.local
```

**Expected:** Resolves correctly! FQDN works across namespaces.

Cleanup:

```bash
kubectl delete namespace test-ns
```

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `nslookup api-service` resolves to ClusterIP (10.96.x.x)
- [ ] `nslookup web-service` resolves to ClusterIP (10.96.x.x)
- [ ] `curl http://api-service/get` from test Pod returns JSON 200 OK
- [ ] `kubectl get endpoints api-service` shows 2 endpoints (Pod IPs)
- [ ] `kubectl get EndpointSlice` shows Ready endpoints matching `kubectl get pods -o wide`
- [ ] Web Pod can call `http://api-service` (exec into web, install curl, test)
- [ ] FQDN works: `api-service.default.svc.cluster.local` resolves from any namespace

**If any check fails, proceed to [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts

### Service Discovery = Name Stability

```
Without Service:                With Service:
┌─────────┐                     ┌─────────┐
│  Web    │                     │  Web    │
└────┬────┘                     └────┬────┘
     │ calls http://10.244.0.10      │ calls http://api-service
     ↓ (Pod IP - ephemeral!)         ↓ (DNS name - stable!)
┌─────────┐                     ┌──────────────┐
│ API Pod │ ← Deleted/recreated │ api-service  │ (ClusterIP)
│ (new IP)│   → Web breaks! ❌   └──────┬───────┘
└─────────┘                            │ routes to
                                       ↓
                                 ┌─────────┐
                                 │ API Pod │ ← Any replica
                                 └─────────┘   → Still works! ✅
```

### DNS is "the glue" for composability

**Cloud-native principle:**
- Dependencies by name, not by address
- Names resolve dynamically to current endpoints
- Enables Pod replaceability without breaking clients

### Endpoints = Truth Source

```yaml
Service without endpoints:
  spec:
    selector:
      app: wrong-label  # No Pods match!
  status:
    loadBalancer: {}    # Empty

→ Traffic: ❌ Can't work (no backend)

Service with endpoints:
  Endpoints: 10.244.0.10:80, 10.244.0.11:80
→ Traffic: ✅ Load-balanced across 2 Pods
```

**Diagnostic mantra:** "Service without endpoints = matching broken or Pods not Ready."

---

## 🔗 Theory Mapping (Lezione 3)

| Slide Concept | Where in Lab |
|---------------|-------------|
| Pod IP - identità effimera | Step 7 - Pod IPs change, Service name stays stable |
| Service discovery via DNS | Step 1-2 - nslookup resolves Service names |
| Endpoints e EndpointSlice | Step 4 - Inspect endpoint list, only Ready Pods included |
| Namespace e nomi DNS | Step 8 - Short name vs FQDN, namespace isolation |
| Sintomo: "DNS risolve ma non risponde" | Step 3 - curl test + Step 4 endpoint check |
| Tre piani: Pod/Service/Ingress | Mental model - today focus on Pod + Service layers |

---

## 🚀 Bonus Challenges (Optional)

**Only if time permits:**

### Bonus 1: Test DNS from different Pod images

Compare DNS tools:

```bash
# busybox (nslookup)
kubectl run test-busybox --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service

# alpine (nslookup, dig)
kubectl run test-alpine --image=alpine:3.19 --rm -it --restart=Never -- sh -c "apk add --no-cache bind-tools && dig api-service"

# dnsutils (dig, nslookup, host)
kubectl run test-dnsutils --image=gcr.io/kubernetes-e2e-test-images/dnsutils:1.3 --rm -it --restart=Never -- nslookup api-service
```

### Bonus 2: Inspect CoreDNS

Explore the DNS server itself:

```bash
# Check CoreDNS Pods
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50

# Check CoreDNS ConfigMap
kubectl -n kube-system get configmap coredns -o yaml
```

### Bonus 3: Service in different namespace

Create a Service in a custom namespace and test cross-namespace DNS:

```bash
# Create namespace
kubectl create namespace other-ns

# Create a simple Service
kubectl -n other-ns create deployment test-nginx --image=nginx:1.27-alpine
kubectl -n other-ns expose deployment test-nginx --port=80 --name=test-service

# Resolve from default namespace
kubectl run test-cross-ns --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup test-service.other-ns.svc.cluster.local

# Cleanup
kubectl delete namespace other-ns
```

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `nslookup api-service` resolves to ClusterIP (10.96.x.x)
- [ ] `nslookup web-service` resolves to ClusterIP (10.96.x.x)
- [ ] `curl http://api-service/get` from test Pod returns JSON 200 OK
- [ ] `kubectl get endpoints api-service` shows 2 endpoints (Pod IPs)
- [ ] `kubectl get EndpointSlice` shows Ready endpoints matching `kubectl get pods -o wide`
- [ ] Web Pod can call `http://api-service` (exec into web, install curl, test)
- [ ] FQDN works: `api-service.default.svc.cluster.local` resolves from any namespace

**If any check fails, proceed to [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts (From Lezione 3)

### The Two Questions

**When connectivity fails:**

```
1. Does the name resolve?
   → Test: nslookup <service>
   → If NO: DNS broken (CoreDNS down, wrong namespace)
   → If YES: Proceed to question 2

2. Are there endpoints?
   → Test: kubectl get endpoints <service>
   → If EMPTY: Selector mismatch OR Pods not Ready
   → If POPULATED: Check port/targetPort, then app logs
```

**Diagnostic sequence (golden path):**
```bash
# 1. Service exists?
kubectl get svc <name>

# 2. Endpoints exist?
kubectl get EndpointSlice -l kubernetes.io/service-name=<name>

# 3. Pods Ready?
kubectl get pods -l <selector> -o wide

# 4. Selector matches Pod labels?
kubectl get svc <name> -o jsonpath='{.spec.selector}'
kubectl get pods -l <selector> --show-labels

# 5. Events and conditions
kubectl describe pod <pod-name>
```

### Service Types Recap

**Today we use ClusterIP (internal only):**

| Type | Scope | Use Case | Capstone Usage |
|------|-------|----------|----------------|
| **ClusterIP** | Internal only | Service-to-Service (web→api, api→db) | ✅ web-service, api-service |
| **NodePort** | External (port on node) | Quick local testing | ❌ Not needed (using Ingress) |
| **LoadBalancer** | External (cloud LB) | Production external access | ❌ Not in Minikube |

**Why ClusterIP for capstone?**
- Clean separation: internal networking via Services, external access via Ingress
- More diagnosable: clear layer boundaries
- KCNA-aligned: standard multi-tier pattern

### Selector = The Matching Contract

```yaml
Service selector:        Pod labels:
  app: api         ←─→    app: api
  tier: backend    ←─→    tier: backend
                   ✅ Match!

EndpointSlice populated → Traffic works
```

**Mismatch example:**
```yaml
Service selector:        Pod labels:
  app: api         ←─X    app: wrong-name
  tier: backend          tier: backend
                   ❌ No match!

EndpointSlice empty → Traffic fails (timeout)
```

**Diagnostic command:**
```bash
# Compare selector to actual Pod labels
kubectl get svc api-service -o jsonpath='{.spec.selector}' | jq
kubectl get pods -l app=api --show-labels
```

### DNS vs Endpoints: Different Failure Modes

| Symptom | DNS State | Endpoints | Root Cause | Fix |
|---------|-----------|-----------|------------|-----|
| "Name not found" | ❌ Doesn't resolve | N/A | Service doesn't exist OR wrong namespace | Create Service or use FQDN |
| "Connection refused" | ✅ Resolves | ❌ Empty | Selector mismatch OR Pods not Ready | Fix selector or readiness probe |
| "Timeout" | ✅ Resolves | ✅ Populated | Wrong port OR app not listening | Check port/targetPort |
| "Works!" | ✅ Resolves | ✅ Populated | N/A | 🎉 |

---

## 📚 Resources

### Official Kubernetes Documentation
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/service/#endpointslices)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

### KCNA Alignment
- **Kubernetes Fundamentals (46%)**: DNS, service discovery, networking model
- **Container Orchestration (22%)**: Endpoint management, Service types

### Related
- Lezione 3: Slides 10-20 (modello rete, DNS, endpoints)
- Day 2 Lab 2.4: Multi-tier foundation (this lab builds on it)

---

**Previous**: [Day 3 Overview](../README.md)  
**Next**: [Lab 3.2 - Ingress Controller Setup](../lab-3.2-ingress-setup/README.md)
