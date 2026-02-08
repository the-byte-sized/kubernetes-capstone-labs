# Lab 2.4 Verification Checklist

## ✅ Pass/Fail Criteria

Use this checklist to verify Lab 2.4 completion. **All items must pass** for Day 2 Definition of Done (DoD).

---

## 🔍 Pre-Flight Check (Lab 2.3 prerequisites)

**Before starting Lab 2.4, verify:**

- [ ] **Lab 2.3 completed:**
  ```bash
  kubectl get deployment web-deployment
  # EXPECTED: READY=3/3, AVAILABLE=3
  ```

- [ ] **Web Service exists:**
  ```bash
  kubectl get service web-service
  # EXPECTED: TYPE=ClusterIP, ClusterIP assigned
  ```

- [ ] **Web Service has Endpoints:**
  ```bash
  kubectl get endpoints web-service
  # EXPECTED: 3 Pod IPs listed
  ```

**If any pre-flight check fails, complete Lab 2.3 first.**

---

## 📦 1. API Deployment Created and Healthy

### **Check 1.1: Deployment exists**
```bash
kubectl get deployment api-deployment
```

**PASS:** Shows output like:
```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
api-deployment   2/2     2            2           5m
```

**FAIL if:**
- `Error from server (NotFound)` → Apply `api-deployment.yaml`
- `READY=0/2` or `AVAILABLE=0` → Check Step 1.2

---

### **Check 1.2: Pods are Running and Ready**
```bash
kubectl get pods -l app=api
```

**PASS:** All Pods show:
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-7c8f9d5b6f-abc12   1/1     Running   0          5m
api-deployment-7c8f9d5b6f-def34   1/1     Running   0          5m
```

**FAIL if:**
- `STATUS=Pending` → See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) Issue 1
- `STATUS=ImagePullBackOff` → See Issue 2
- `READY=0/1` → Check readiness probe (Step 1.3)
- `RESTARTS > 5` → Check liveness probe and logs

---

### **Check 1.3: Readiness probe passing**
```bash
kubectl describe pod -l app=api | grep -A 5 "Readiness:"
```

**PASS:** Shows:
```
Readiness:      http-get http://:80/get delay=5s timeout=3s period=5s #success=1 #failure=3
```

And no recent failures:
```bash
kubectl describe pod -l app=api | grep "Readiness probe failed"
```

**PASS:** No output (no failures).

**FAIL if:**
- `Readiness probe failed: HTTP probe failed with statuscode: 404` → Wrong probe path
- `Readiness probe failed: Get "http://...": dial tcp: connect: connection refused` → Container not listening on port 80

---

### **Check 1.4: Logs show httpbin started**
```bash
kubectl logs -l app=api --tail=10
```

**PASS:** Shows httpbin startup messages (Gunicorn workers):
```
[2026-02-08 20:00:00 +0000] [1] [INFO] Starting gunicorn 20.1.0
[2026-02-08 20:00:00 +0000] [1] [INFO] Listening at: http://0.0.0.0:80 (1)
[2026-02-08 20:00:00 +0000] [1] [INFO] Using worker: gthread
[2026-02-08 20:00:00 +0000] [8] [INFO] Booting worker with pid: 8
```

**FAIL if:**
- Error messages about missing dependencies
- `ModuleNotFoundError` or Python exceptions
- No output → Container may not have started

---

## 🌐 2. API Service Created and Configured

### **Check 2.1: Service exists**
```bash
kubectl get service api-service
```

**PASS:** Shows:
```
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
api-service   ClusterIP   10.96.234.56    <none>        80/TCP    5m
```

**FAIL if:**
- `Error from server (NotFound)` → Apply `api-service.yaml`
- `TYPE != ClusterIP` → Verify manifest

---

### **Check 2.2: Service has Endpoints**
```bash
kubectl get endpoints api-service
```

**PASS:** Shows 2 Pod IPs:
```
NAME          ENDPOINTS                     AGE
api-service   10.244.0.10:80,10.244.0.11:80  5m
```

**FAIL if:**
- `ENDPOINTS=<none>` → See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) Issue 3
- Fewer than 2 endpoints → Check Pod readiness (Step 1.3)

---

### **Check 2.3: Endpoints match Pod IPs**
```bash
# Get Pod IPs
kubectl get pods -l app=api -o wide

# Get Endpoints
kubectl get endpoints api-service
```

**PASS:** Endpoint IPs match Pod IPs exactly.

**FAIL if:**
- Endpoint IPs don't match any Pod IPs → Label mismatch (see Issue 3)

---

### **Check 2.4: Service selector matches Pod labels**
```bash
# Service selector
kubectl get service api-service -o jsonpath='{.spec.selector}'

# Pod labels
kubectl get pods -l app=api --show-labels
```

**PASS:** 
- Service selector shows: `{"app":"api","tier":"backend"}`
- All Pods have labels: `app=api,tier=backend`

**FAIL if:**
- Selector and labels don't match → Update Deployment template labels

---

## 🔍 3. DNS Resolution Works

### **Check 3.1: DNS resolves short name (same namespace)**
```bash
kubectl run test-dns-short -n task-tracker --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```

**PASS:** Shows:
```
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   api-service.task-tracker.svc.cluster.local
Address: 10.96.234.56

pod "test-dns-short" deleted
```

**FAIL if:**
- `nslookup: can't resolve 'api-service'` → See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) Issue 4

---

### **Check 3.2: DNS resolves FQDN**
```bash
kubectl run test-dns-fqdn --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service.task-tracker.svc.cluster.local
```

**PASS:** Resolves to same ClusterIP as Check 3.1.

**FAIL if:**
- Resolution fails → CoreDNS issue (see Issue 4)

---

### **Check 3.3: DNS resolves to correct ClusterIP**

```bash
# Get Service ClusterIP
SVC_IP=$(kubectl get service api-service -o jsonpath='{.spec.clusterIP}')
echo $SVC_IP

# Test DNS
kubectl run test-dns-ip --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```

**PASS:** DNS returns the same IP as `$SVC_IP`.

---

## 🌐 4. API Responds to HTTP Requests

### **Check 4.1: Direct Pod IP access works**
```bash
# Get first Pod IP
POD_IP=$(kubectl get pods -l app=api -o jsonpath='{.items[0].status.podIP}')
echo $POD_IP

# Test direct access
kubectl run test-direct --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl -s http://$POD_IP/get
```

**PASS:** Returns JSON:
```json
{
  "args": {}, 
  "headers": {...}, 
  "origin": "10.244.0.X", 
  "url": "http://10.244.0.10/get"
}
pod "test-direct" deleted
```

**FAIL if:**
- `curl: (7) Failed to connect` → Container not listening or wrong port
- `curl: (28) Connection timed out` → Network issue or readiness failing

---

### **Check 4.2: Service name access works (DNS)**
```bash
kubectl run test-service -n task-tracker --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl -s http://api-service/get
```

**PASS:** Returns JSON with `"Host": "api-service"`:
```json
{
  "args": {}, 
  "headers": {
    "Host": "api-service"
  }, 
  "origin": "10.244.0.X", 
  "url": "http://api-service/get"
}
pod "test-service" deleted
```

**FAIL if:**
- `curl: (6) Could not resolve host: api-service` → DNS issue (Check 3)
- `curl: (7) Failed to connect` → Service has no Endpoints (Check 2.2)

---

### **Check 4.3: Multiple endpoints tested (different responses)**

Test httpbin's `/uuid` endpoint (returns unique ID per request):

```bash
for i in {1..5}; do
  kubectl run test-lb-$i -n task-tracker --image=curlimages/curl:8.11.1 --rm --restart=Never -- curl -s http://api-service/uuid
done
```

**PASS:** Returns different UUIDs, showing requests distributed.

**FAIL if:**
- Always same UUID → Single Pod responding (Check 2.2 - missing Endpoints?)

---

## 🔗 5. Web → API Communication Works

### **Check 5.1: Web Pod can resolve api-service**
```bash
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $WEB_POD -- nslookup api-service
```

**PASS:** Resolves to ClusterIP.

**FAIL if:**
- `nslookup: can't resolve` → DNS issue or wrong namespace

---

### **Check 5.2: Web Pod can call API (install curl first)**
```bash
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $WEB_POD -- /bin/sh -c "apk add --no-cache curl && curl -s http://api-service/get"
```

**PASS:** Returns JSON response.

**FAIL if:**
- `curl: (7) Failed to connect` → See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) Issue 5

---

## 🔄 6. Resilience and Auto-Healing

### **Check 6.1: Delete API Pod → auto-recreated**
```bash
# Before delete
kubectl get pods -l app=api

# Delete one Pod
kubectl delete pod -l app=api --field-selector metadata.name=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

# Wait 10 seconds
sleep 10

# After delete
kubectl get pods -l app=api
```

**PASS:** 
- Number of Pods returns to 2
- New Pod has `AGE < 1m`
- STATUS=Running, READY=1/1

**FAIL if:**
- Pod count stays at 1 → Deployment not managing Pods (wrong selector?)

---

### **Check 6.2: Service Endpoints update automatically**
```bash
# Before delete
kubectl get endpoints api-service

# Delete one Pod
kubectl delete pod -l app=api --field-selector metadata.name=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

# Immediately check Endpoints
kubectl get endpoints api-service

# After 10 seconds
sleep 10
kubectl get endpoints api-service
```

**PASS:** 
- Initially: 1 endpoint (one Pod down)
- After 10s: 2 endpoints (new Pod Ready)

**FAIL if:**
- Endpoints stay at 1 → New Pod not becoming Ready

---

### **Check 6.3: API remains accessible during Pod deletion**
```bash
# Delete Pod in background
kubectl delete pod -l app=api --field-selector metadata.name=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}') &

# Immediately test API
for i in {1..5}; do
  kubectl run test-resilience-$i -n task-tracker --image=curlimages/curl:8.11.1 --rm --restart=Never -- curl -s http://api-service/get | grep -i origin
  sleep 1
done
```

**PASS:** All 5 requests succeed (may route to surviving Pod).

**FAIL if:**
- Requests fail → Only 1 Pod was handling traffic

---

## 📈 7. Scaling Verification

### **Check 7.1: Scale up → Endpoints increase**
```bash
# Scale to 4
kubectl scale deployment api-deployment --replicas=4

# Wait for Pods
kubectl wait --for=condition=Ready pod -l app=api --timeout=60s

# Check Endpoints
kubectl get endpoints api-service
```

**PASS:** Shows 4 Pod IPs.

**FAIL if:**
- Fewer than 4 endpoints → Pods not Ready (check logs/describe)

---

### **Check 7.2: Scale down → Endpoints decrease**
```bash
# Scale to 2
kubectl scale deployment api-deployment --replicas=2

# Wait for termination
sleep 10

# Check Endpoints
kubectl get endpoints api-service
```

**PASS:** Shows 2 Pod IPs.

**FAIL if:**
- More than 2 endpoints → Pods not terminating

---

## 🎓 8. Multi-Tier Architecture Verified

### **Check 8.1: Both tiers running**
```bash
kubectl get deployments
```

**PASS:** Shows:
```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
web-deployment   3/3     3            3           30m
api-deployment   2/2     2            2           15m
```

---

### **Check 8.2: Both Services have Endpoints**
```bash
kubectl get endpoints
```

**PASS:** Shows:
```
NAME          ENDPOINTS                                 AGE
web-service   10.244.0.5:80,10.244.0.6:80,10.244.0.7:80  30m
api-service   10.244.0.10:80,10.244.0.11:80              15m
```

---

### **Check 8.3: Cross-tier communication works**

From web Pod to API:

```bash
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec $WEB_POD -- /bin/sh -c "apk add --no-cache curl > /dev/null 2>&1 && curl -s http://api-service/get" | jq -r '.url'
```

**PASS:** Output: `http://api-service/get`

**FAIL if:**
- `curl: (6) Could not resolve host` → DNS issue
- `curl: (7) Failed to connect` → Service/Endpoints issue

---

## 📊 Final Summary

**Day 2 DoD Checklist:**

- [ ] **Web tier:** 3 Pods Running, web-service with Endpoints
- [ ] **API tier:** 2 Pods Running, api-service with Endpoints
- [ ] **DNS:** Both Services resolve via short name and FQDN
- [ ] **Communication:** Web → API via Service name works
- [ ] **Resilience:** Delete Pod → auto-recreated, Endpoints updated
- [ ] **Scaling:** Scale Deployment → Endpoints auto-adjust
- [ ] **Load balancing:** Multiple requests distributed across Pods

**All checks passed? Congratulations! Day 2 complete.** 🎉

**Next:** Day 3 - Networking, Ingress, ConfigMap/Secret

---

## 🆘 Failed Checks?

If any check fails:

1. **Check specific issue in [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**
2. **Re-run failed check after fix**
3. **If stuck, ask instructor or review [Lezione 2 theory](../../../docs/Lezione-2.pdf)**

---

**Quick reset if needed:**
```bash
kubectl delete -f api-deployment.yaml
kubectl delete -f api-service.yaml
kubectl apply -f api-deployment.yaml
kubectl apply -f api-service.yaml
kubectl wait --for=condition=Ready pod -l app=api --timeout=60s
```
