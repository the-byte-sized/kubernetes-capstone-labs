# Lab 3.5 Troubleshooting: Probes & Endpoints

## Issue 1: Pod Running but not Ready (READY 0/1)

### Symptom

```bash
kubectl get pods -l app=api
```

**Output:**
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-...                0/1     Running   0          2m
```

### Root Causes & Fixes

#### Cause 1.1: ReadinessProbe failing

**Verify:**

```bash
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $API_POD | grep -A10 "Readiness"
```

Look at Events:

```
Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

**Fix:**

Ensure readinessProbe path/port matches the real app:

For httpbin:

```yaml
readinessProbe:
  httpGet:
    path: /get
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
```

Apply fix and wait for rollout:

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment
```

Check Pods:

```bash
kubectl get pods -l app=api
# Expected: READY 1/1
```

Check EndpointSlice:

```bash
kubectl get endpointslice -l kubernetes.io/service-name=api-service -o yaml | grep -A5 endpoints:
```

**Expected:** `ready: true` for each endpoint.

---

#### Cause 1.2: Probe too aggressive (timeouts)

If readinessProbe uses very short timeouts or frequent checks, slow startup can cause flapping.

**Fix:**

Tune timings:

```yaml
readinessProbe:
  httpGet:
    path: /get
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
```

Re-apply and monitor:

```bash
kubectl apply -f api-with-probes.yaml
kubectl get pods -l app=api -w
```

---

## Issue 2: Pod in CrashLoopBackOff (liveness misconfigured)

### Symptom

```bash
kubectl get pods -l app=api
```

**Output:**
```
NAME                              READY   STATUS             RESTARTS   AGE
api-deployment-...                0/1     CrashLoopBackOff   5          3m
```

### Root Causes & Fixes

#### Cause 2.1: LivenessProbe pointing to invalid path/port

**Verify:**

```bash
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $API_POD | grep -A10 "Liveness"
```

Look at Events:

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 404
Normal   Killing    Container httpbin failed liveness probe, will be restarted
```

**Fix:**

For httpbin, use a known good path:

```yaml
livenessProbe:
  httpGet:
    path: /status/200
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 5
```

Apply and watch:

```bash
kubectl apply -f api-with-probes.yaml
kubectl get pods -l app=api -w
```

**Expected:**
- Pod stabilizes in `Running` and `READY 1/1`.
- `RESTARTS` stops increasing.

---

#### Cause 2.2: Probe too aggressive

If `initialDelaySeconds` is too low or `periodSeconds` too frequent, slow startup or transient glitches can trigger restarts.

**Fix:**

Increase initialDelay and period:

```yaml
livenessProbe:
  httpGet:
    path: /status/200
    port: 80
  initialDelaySeconds: 20
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
```

Apply and monitor again.

---

## Issue 3: Service has no endpoints after adding readinessProbe

### Symptom

```bash
kubectl get endpoints api-service
```

**Output:**
```
NAME          ENDPOINTS   AGE
api-service   <none>      15m
```

Yet Pods exist:

```bash
kubectl get pods -l app=api
```

**Output:**
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-...                0/1     Running   0          5m
```

### Explanation

ReadinessProbe is failing, so Pods are not considered Ready and are excluded from endpoints.

### Fix

Same as Issue 1:
- Fix readinessProbe path/port.
- Ensure app responds correctly.

After fix:

```bash
kubectl get endpoints api-service
# Expected: IP:80 entries
kubectl get endpointslice -l kubernetes.io/service-name=api-service -o yaml | grep -A5 endpoints:
```

---

## Issue 4: Traffic intermittently fails

### Symptom

`curl http://api-service/get` sometimes works, sometimes times out.

### Root Cause

One Pod flapping between Ready/NotReady due to unstable readinessProbe.

### Fix

1. Identify Pod with issues:

```bash
kubectl get pods -l app=api
kubectl describe pod <api-pod>
```

2. Tune readinessProbe thresholds (as in Issue 1.2).

3. Optionally, scale down to 1 replica to isolate behavior, then scale back.

```bash
kubectl scale deployment api-deployment --replicas=1
# Fix probe
kubectl apply -f api-with-probes.yaml
kubectl scale deployment api-deployment --replicas=2
```

---

## Issue 5: Probe paths work with curl but fail as probes

### Symptom

Inside Pod, this works:

```bash
kubectl exec <api-pod> -- wget -qO- http://localhost:80/get
```

But readiness/livenessProbe still fail.

### Root Causes & Fixes

#### Cause 5.1: Probes using HTTPS instead of HTTP

**Verify:**

```bash
kubectl get deployment api-deployment -o yaml | grep -A5 readinessProbe
```

If you see `scheme: HTTPS` but your app only serves HTTP, probe fails.

**Fix:**

Remove `scheme` or set to `HTTP`:

```yaml
httpGet:
  path: /get
  port: 80
  scheme: HTTP
```

Apply and monitor.

---

#### Cause 5.2: Probes targeting wrong port

If container listens on 8080 but probe uses 80, it fails.

**Fix:**

Check container ports:

```bash
kubectl get pod <api-pod> -o jsonpath='{.spec.containers[0].ports}' | jq
```

Align probe port:

```yaml
readinessProbe:
  httpGet:
    path: /get
    port: 8080
```

---

## Quick Diagnostic Checklist

Use this script-like sequence when probes misbehave:

```bash
# 1. Check Pods
kubectl get pods -l app=api -o wide

# 2. Describe Pod for probe details
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $API_POD | grep -A10 "Readiness"
kubectl describe pod $API_POD | grep -A10 "Liveness"

# 3. Check Events
kubectl describe pod $API_POD | grep -A10 "Events"

# 4. Test endpoints manually from inside Pod
kubectl exec $API_POD -- wget -qO- http://localhost:80/get || echo "Readiness path failed"
kubectl exec $API_POD -- wget -qO- http://localhost:80/status/200 || echo "Liveness path failed"

# 5. Check Service endpoints
kubectl get endpoints api-service
kubectl get endpointslice -l kubernetes.io/service-name=api-service -o yaml | grep -A5 endpoints:
```

---

## Additional Resources

- [Configure Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Debugging Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pod-replication-controller/)

---

**Back to**: [Lab 3.5 README](./README.md)
