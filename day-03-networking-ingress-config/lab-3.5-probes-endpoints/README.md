# Lab 3.5: Probes & Endpoints (Readiness vs Liveness)

## 🎯 Goal

Make **"ready"** and **"healthy"** measurable for the `api` component using Kubernetes probes, and observe how **readiness** impacts **Service endpoints**, while **liveness** controls container restarts.

**Key learning**:
- A Pod can be `Running` but **not Ready** → it must **not** receive traffic.
- Readiness controls inclusion in Service endpoints.
- Liveness controls restarts (CrashLoopBackOff when misconfigured).

---

## 📚 Prerequisites

✅ `api-deployment` exists and works via `api-service`:

```bash
kubectl get deployment api-deployment
kubectl get svc api-service
kubectl run test-api --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
```

**Expected:**
- Deployment READY (e.g., 2/2).
- `api-service` ClusterIP with endpoints populated.
- `curl` returns JSON from httpbin.

---

## 🧪 Part A – Add readinessProbe (gate for traffic)

### Step A1: Add readinessProbe to api-deployment

Use the provided `api-with-probes.yaml` manifest that includes both readiness and liveness probes (final good configuration):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
spec:
  replicas: 2
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
        readinessProbe:
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /status/200
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
```

**Start by applying only readiness** (you can temporarily comment out livenessProbe for Part A):

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment
```

---

### Step A2: Observe Pod READY state and endpoints

Watch Pods and endpoints:

```bash
# Watch Pods
kubectl get pods -l app=api -w
```

In another terminal:

```bash
# Watch EndpointSlices for api-service
kubectl get EndpointSlice -l kubernetes.io/service-name=api-service -w
```

**Expected lifecycle:**
1. Pod created → `STATUS=ContainerCreating`, `READY=0/1`.
2. Container Running → `STATUS=Running`, `READY=0/1` (until readinessProbe succeeds).
3. Probe succeeds → `READY=1/1`.
4. EndpointSlice adds Pod IP as endpoint (`ready: true`).

**Key observation:** Pod appears in endpoints **only after** it becomes Ready.

---

### Step A3: Test traffic during readiness

While Pods are rolling out:

```bash
kubectl run test-readiness --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl -v http://api-service/get
```

- If you hit during the window where no Pod is Ready, you may see connection issues.
- Once at least one Pod is Ready, responses should be 200 OK.

This shows how readiness protects your Service from sending traffic to not-yet-ready Pods.

---

## 🧪 Part B – Misconfigure livenessProbe (controlled failure)

> **Warning (didattico):** In this part we intentionally misconfigure livenessProbe to create a restart loop, then fix it.

### Step B1: Add livenessProbe with wrong path

Edit `api-with-probes.yaml` temporarily and change livenessProbe path to something wrong:

```yaml
        livenessProbe:
          httpGet:
            path: /wrong-path  # INTENTIONALLY WRONG
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
```

Apply and watch:

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment

kubectl get pods -l app=api -w
```

**Expected:**
- Pods go into `Running` but then repeatedly restart.
- `RESTARTS` column increases over time.

---

### Step B2: Inspect Events and logs

Describe one api Pod:

```bash
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $API_POD
```

**Look for Events:**

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 404
Normal   Killing    Container httpbin failed liveness probe, will be restarted
```

Check logs (if any before restart):

```bash
kubectl logs $API_POD --tail=20
```

**Key observation:** Misconfigured livenessProbe causes Kubernetes to **kill and restart** containers, creating a CrashLoop-like behavior.

---

### Step B3: Fix livenessProbe

Restore the correct livenessProbe path using the provided `api-with-probes.yaml` (good configuration):

```yaml
        livenessProbe:
          httpGet:
            path: /status/200  # CORRECT
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
```

Apply and wait for stable Pods:

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment

kubectl get pods -l app=api
```

**Expected:**
- Pods `READY=1/1`, `STATUS=Running`.
- `RESTARTS` stops increasing.

---

## 🧪 Part C – Observe impact on endpoints and traffic

### Step C1: Remove readiness (for comparison)

(Optional, to compare behavior.) Temporarily remove readinessProbe and keep livenessProbe correct.

```yaml
# Comment out or remove readinessProbe section
```

Apply and watch endpoints:

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment

kubectl get EndpointSlice -l kubernetes.io/service-name=api-service -o yaml
```

**Observation:**
- Without readinessProbe, Pods are treated as Ready as soon as containers are Running.
- Endpoints may include Pods even if the app is not fully initialized (in real-world apps).

### Step C2: Restore readinessProbe (good configuration)

Final good configuration from provided `api-with-probes.yaml`:

```yaml
        readinessProbe:
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /status/200
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
```

Apply and verify:

```bash
kubectl apply -f api-with-probes.yaml
kubectl rollout status deployment api-deployment

kubectl get pods -l app=api
kubectl get EndpointSlice -l kubernetes.io/service-name=api-service -o yaml | grep -A5 addresses:
```

**Expected:**
- Pods `READY=1/1`.
- EndpointSlice lists only Ready endpoints (`ready: true`).

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] With readinessProbe enabled, Pods go from `READY 0/1` to `READY 1/1` and only then appear in EndpointSlice.
- [ ] Misconfigured livenessProbe causes repeated restarts (`RESTARTS` increasing, Events show liveness failures).
- [ ] Fixing livenessProbe stabilizes Pods (no new restarts).
- [ ] Final configuration (readiness + liveness) keeps api-service healthy: `curl http://api-service/get` returns 200.

If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

---

## 🎓 Key Concepts

### Running vs Ready

- **Running**: Container process is alive.
- **Ready**: Pod is **eligible for traffic** behind a Service.

A Pod can be:
- `STATUS=Running`, `READY=0/1` → **No traffic** (not in endpoints).
- `STATUS=Running`, `READY=1/1` → **Can receive traffic** (in endpoints).

### ReadinessProbe

- Answers: "Can this instance handle traffic now?"
- If failing: Pod stays out of endpoints → protects clients from half-initialized instances.

### LivenessProbe

- Answers: "Should this container be restarted?"
- If failing: Kubernetes **kills and restarts** the container.
- Misconfiguration → CrashLoopBackOff pattern (repeated restarts).

### StartupProbe (cenno)

- Used for slow-starting apps.
- Disables liveness/readiness until initial checks pass.
- Not required for this lab, but useful concept for KCNA.

---

## 🔗 Theory Mapping (Lezione 3)

| Slide Concept | Where in Lab |
|---------------|-------------|
| Ready cambia tutto: Running non basta | Part A (READY vs endpoints) |
| ReadinessProbe - gate per entrare negli endpoint | Step A2, Part C |
| LivenessProbe - riavvio controllato | Part B (misconfigured liveness) |
| StartupProbe - cenno | Key Concepts (StartupProbe) |
| Probes come segnali, non magia | Overall behavior observation |

---

## 📚 Official References

- [Configure Liveness, Readiness, and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

---

**Previous**: [Lab 3.4 - ConfigMap & Secret](../lab-3.4-configmap-secret/README.md)  
**Next**: Day 3 DoD checklist (in main README)
