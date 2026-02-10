# Lab 3.1 Troubleshooting: DNS & Service Discovery

## Issue 1: DNS Resolution Fails

### Symptom

```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```

**Output:**
```
Server:         10.96.0.10
Address:        10.96.0.10:53

nslookup: can't resolve 'api-service'
pod "test-dns" deleted
```

Or:
```
;; connection timed out; no servers could be reached
```

### Root Causes & Fixes

#### Cause 1.1: Service doesn't exist

**Verify:**
```bash
kubectl get service api-service
```

**If output:**
```
Error from server (NotFound): services "api-service" not found
```

**Fix:**
Create the Service (from Day 2 Lab 2.4):
```bash
kubectl apply -f api-service.yaml
```

Or create imperatively:
```bash
kubectl expose deployment api-deployment --name=api-service --port=80 --target-port=80
```

Verify:
```bash
kubectl get svc api-service
# Expected: ClusterIP assigned
```

---

#### Cause 1.2: Wrong namespace

**Verify:**
```bash
# Check current namespace
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}'

# List Services in all namespaces
kubectl get svc --all-namespaces | grep api-service
```

**If Service is in different namespace (e.g., `capstone`):**

**Fix Option A:** Use FQDN:
```bash
kubectl run test-dns-fqdn --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup api-service.capstone.svc.cluster.local
```

**Fix Option B:** Test from same namespace:
```bash
kubectl run test-dns-same-ns --image=busybox:1.36 --rm -it --restart=Never -n capstone -- \
  nslookup api-service
```

**Best practice:** Always specify namespace explicitly:
```bash
kubectl get svc -n <namespace>
kubectl run test-dns -n <namespace> ...
```

---

#### Cause 1.3: CoreDNS not running

**Verify:**
```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

**If no Pods or Pods not Ready:**
```
NAME                      READY   STATUS    RESTARTS
coredns-5d78c9869d-abc12  0/1     Pending   0
```

**Check Events:**
```bash
kubectl -n kube-system describe pod -l k8s-app=kube-dns
```

**Common reasons:**
- Insufficient resources (Minikube too small)
- Node issues

**Fix for Minikube:**
```bash
# Stop Minikube
minikube stop

# Restart with more resources
minikube start --cpus=4 --memory=8192

# Wait for CoreDNS
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=60s
```

Verify:
```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
# Expected: 2/2 Running and Ready
```

Retest DNS:
```bash
kubectl run test-dns-retry --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
# Expected: Resolves to ClusterIP
```

---

#### Cause 1.4: Service ClusterIP is None (Headless Service)

**Verify:**
```bash
kubectl get svc api-service -o jsonpath='{.spec.clusterIP}'
```

**If output:** `None`

**Explanation:** Headless Service (clusterIP: None) doesn't get a stable ClusterIP. DNS returns Pod IPs directly.

**Fix (if you want stable ClusterIP):**

Edit Service:
```bash
kubectl edit svc api-service
```

Remove or comment out:
```yaml
spec:
  # clusterIP: None  # Remove this line
  ...
```

Save and verify:
```bash
kubectl get svc api-service
# Expected: ClusterIP assigned (e.g., 10.96.234.56)
```

**Note:** Headless Services are valid for specific use cases (StatefulSets), but not needed for basic capstone.

---

## Issue 2: DNS Resolves but Connection Fails

### Symptom

```bash
kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
```

**Output:**
```
curl: (7) Failed to connect to api-service port 80: Connection refused
```

Or:
```
curl: (28) Failed to connect to api-service port 80 after 130ms: Operation timed out
```

### Root Causes & Fixes

#### Cause 2.1: Service has no endpoints (most common)

**Verify:**
```bash
kubectl get endpoints api-service
```

**If output:**
```
NAME          ENDPOINTS   AGE
api-service   <none>      5m
```

**This means:** No Pods are selected and Ready behind this Service.

**Diagnose selector mismatch:**

```bash
# Get Service selector
kubectl get svc api-service -o jsonpath='{.spec.selector}' | jq
```

**Expected output:**
```json
{
  "app": "api",
  "tier": "backend"
}
```

Check if Pods have matching labels:

```bash
kubectl get pods -l app=api,tier=backend --show-labels
```

**If no Pods returned:** Selector mismatch!

**Fix:**

Check actual Pod labels:
```bash
kubectl get pods -o wide --show-labels | grep api
```

Edit Service selector to match:
```bash
kubectl edit svc api-service
```

Or recreate Service with correct selector:
```bash
kubectl delete svc api-service
kubectl expose deployment api-deployment --name=api-service --port=80 --target-port=80
```

Verify endpoints populated:
```bash
kubectl get endpoints api-service
# Expected: 2 Pod IPs listed
```

---

#### Cause 2.2: Pods exist but not Ready

**Verify:**
```bash
kubectl get pods -l app=api
```

**If output:**
```
NAME                              READY   STATUS    RESTARTS
api-deployment-7c8f9d5b6f-abc12   0/1     Running   0
api-deployment-7c8f9d5b6f-def34   0/1     Running   0
```

**Notice:** STATUS is Running, but READY is 0/1!

**Check readiness probe failures:**
```bash
kubectl describe pod -l app=api
```

**Look for Events:**
```
Events:
  Type     Reason     Message
  ----     ------     -------
  Warning  Unhealthy  Readiness probe failed: Get "http://10.244.0.10:80/health": dial tcp 10.244.0.10:80: connect: connection refused
```

**Fix:**

Option A - Remove readiness probe temporarily:
```bash
kubectl edit deployment api-deployment
# Comment out or remove readinessProbe section
```

Option B - Fix readiness probe path/port:
```yaml
readinessProbe:
  httpGet:
    path: /get  # Correct path for httpbin
    port: 80    # Correct port
  initialDelaySeconds: 5
  periodSeconds: 5
```

Wait for rollout:
```bash
kubectl rollout status deployment api-deployment
```

Verify Pods Ready:
```bash
kubectl get pods -l app=api
# Expected: READY 1/1
```

Verify endpoints populated:
```bash
kubectl get endpoints api-service
# Expected: 2 Pod IPs
```

---

#### Cause 2.3: Wrong port configuration

**Symptom:** Endpoints exist, but connection refused.

**Verify Service ports:**
```bash
kubectl describe svc api-service
```

**Look for:**
```
Port:              http  80/TCP
TargetPort:        80/TCP
Endpoints:         10.244.0.10:80,10.244.0.11:80
```

**Check actual Pod container port:**
```bash
kubectl get pod -l app=api -o jsonpath='{.items[0].spec.containers[0].ports}' | jq
```

**Expected (httpbin):**
```json
[{"containerPort": 80, "name": "http", "protocol": "TCP"}]
```

**If mismatch:** Service targetPort ≠ container listening port.

**Fix:**

Edit Service to use correct targetPort:
```bash
kubectl edit svc api-service
```

Change:
```yaml
spec:
  ports:
  - port: 80
    targetPort: 80  # Must match containerPort in Pod
```

Or verify from Pod:
```bash
# Check what port the app actually listens on
kubectl exec -l app=api -- netstat -tlnp | grep LISTEN
```

For httpbin, port 80 is correct. If using different image, adjust accordingly.

---

#### Cause 2.4: Application not listening

**Symptom:** Service, endpoints, ports all correct, but still connection refused.

**Diagnose:**

Check Pod logs:
```bash
kubectl logs -l app=api --tail=50
```

**Look for:**
- Startup errors
- Bind address issues (app listening on 127.0.0.1 instead of 0.0.0.0)
- Port configuration errors

**Fix:**

Depends on application. For httpbin (should work out of the box):

```bash
# Verify httpbin is healthy
kubectl exec -l app=api -- wget -O- http://localhost:80/get
```

**If this works but Service doesn't:** Port forwarding test:
```bash
# Forward directly to Pod
kubectl port-forward pod/<api-pod-name> 8080:80

# In another terminal
curl http://localhost:8080/get
```

If port-forward works but Service doesn't, revisit Service port/targetPort configuration.

---

## Issue 3: Cross-Tier Communication Fails (web → api)

### Symptom

```bash
kubectl exec -it <web-pod> -- sh
# Inside Pod:
apk add curl
curl http://api-service/get
# Output: curl: (6) Could not resolve host: api-service
```

### Root Causes & Fixes

#### Cause 3.1: Different namespaces

**Verify namespaces:**
```bash
kubectl get pods <web-pod> -o jsonpath='{.metadata.namespace}'
kubectl get svc api-service -o jsonpath='{.metadata.namespace}'
```

**If different:** Use FQDN in curl.

**Fix:**
```bash
# Inside web Pod
curl http://api-service.<api-namespace>.svc.cluster.local/get
```

Or move Services to same namespace.

---

#### Cause 3.2: DNS search path issue

**Verify DNS config in Pod:**
```bash
kubectl exec <web-pod> -- cat /etc/resolv.conf
```

**Expected:**
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

**If missing search paths or wrong nameserver:** Pod DNS configuration broken (rare, usually cluster-level issue).

**Workaround:**
Use FQDN instead of short name.

---

## Issue 4: Load Balancing Not Working

### Symptom

All requests go to the same API Pod (not load-balanced).

### Root Cause

**Check Service sessionAffinity:**
```bash
kubectl get svc api-service -o jsonpath='{.spec.sessionAffinity}'
```

**If output:** `ClientIP`

**Explanation:** Session affinity enabled - same client IP always routes to same Pod.

### Fix

Disable session affinity:
```bash
kubectl edit svc api-service
```

Set:
```yaml
spec:
  sessionAffinity: None
```

Retest:
```bash
for i in {1..10}; do
  kubectl run test-lb-$i --image=curlimages/curl:8.11.1 --rm --restart=Never -- \
    curl -s http://api-service/get | grep '"origin"'
done
```

**Expected:** Different origin IPs (load-balanced).

---

## Issue 5: Service Resolves but Returns Wrong Content

### Symptom

```bash
curl http://api-service/get
# Returns content from wrong application (e.g., nginx default page)
```

### Root Cause

Service selector is matching wrong Pods (label collision).

**Verify:**

```bash
# Get Service selector
kubectl get svc api-service -o jsonpath='{.spec.selector}' | jq

# Get all Pods matching that selector
kubectl get pods -l app=api --show-labels
```

**If output includes unexpected Pods:** Label collision!

### Fix

Use more specific labels:

```yaml
# Instead of just:
selector:
  app: api

# Use:
selector:
  app: api
  tier: backend  # Additional discriminator
```

Update Service:
```bash
kubectl edit svc api-service
```

Ensure API Pods have both labels:
```bash
kubectl get pods -l app=api,tier=backend --show-labels
# Expected: Only API Pods, not web or others
```

---

## Issue 6: Intermittent Connection Failures

### Symptom

Sometimes works, sometimes times out.

### Root Cause

One or more backend Pods are not Ready (failing readiness probe).

**Verify:**
```bash
kubectl get pods -l app=api
```

**If output:**
```
NAME                              READY   STATUS    RESTARTS
api-deployment-7c8f9d5b6f-abc12   1/1     Running   0        ← Healthy
api-deployment-7c8f9d5b6f-def34   0/1     Running   0        ← Not Ready!
```

**Check endpoints:**
```bash
kubectl get endpointslice -l kubernetes.io/service-name=api-service -o yaml | grep -A 10 endpoints:
```

**Expected:** Only 1 endpoint (the Ready Pod), not 2.

### Fix

Diagnose why Pod is not Ready:
```bash
kubectl describe pod <not-ready-pod-name>
```

**Look at Events:**
```
Warning  Unhealthy  Readiness probe failed: ...
```

Fix the probe or underlying issue (see Lab 3.5 for probe troubleshooting).

---

## Quick Reference: DNS Troubleshooting Sequence

**Copy-paste ready diagnostic script:**

```bash
#!/bin/bash
SERVICE_NAME="api-service"
NAMESPACE="default"

echo "=== Step 1: Check Service exists ==="
kubectl get svc $SERVICE_NAME -n $NAMESPACE

echo "\n=== Step 2: Check DNS resolution ==="
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n $NAMESPACE -- \
  nslookup $SERVICE_NAME

echo "\n=== Step 3: Check endpoints ==="
kubectl get endpoints $SERVICE_NAME -n $NAMESPACE
kubectl get endpointslice -l kubernetes.io/service-name=$SERVICE_NAME -n $NAMESPACE

echo "\n=== Step 4: Check Pod status ==="
SELECTOR=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.selector}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
kubectl get pods -l "$SELECTOR" -n $NAMESPACE -o wide

echo "\n=== Step 5: Check CoreDNS ==="
kubectl -n kube-system get pods -l k8s-app=kube-dns

echo "\n=== Step 6: Test connectivity ==="
kubectl run curl-test --image=curlimages/curl:8.11.1 --rm -it --restart=Never -n $NAMESPACE -- \
  curl -v http://$SERVICE_NAME
```

**Usage:**
1. Save as `dns-debug.sh`
2. Make executable: `chmod +x dns-debug.sh`
3. Run: `./dns-debug.sh`
4. Analyze output to locate the broken layer

---

## Additional Resources

- [Debug Services - Official Kubernetes Docs](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [DNS Troubleshooting](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/service/#endpointslices)

---

**Back to**: [Lab 3.1 README](./README.md)
