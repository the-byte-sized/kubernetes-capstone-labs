# Day 5 Troubleshooting Guide

**Before asking the instructor**, use this guide to diagnose and fix common issues.

---

## Table of Contents

1. [Metrics Server Issues](#metrics-server-issues)
2. [HPA Showing `<unknown>`](#hpa-showing-unknown)
3. [HPA Not Scaling Up](#hpa-not-scaling-up)
4. [HPA Not Scaling Down](#hpa-not-scaling-down)
5. [Rolling Update Stuck](#rolling-update-stuck)
6. [Load Generator Fails](#load-generator-fails)
7. [Pods Crash After Update](#pods-crash-after-update)

---

## Metrics Server Issues

### Symptom
```bash
kubectl top nodes
# error: Metrics API not available
```

### Diagnosis

**Check 1: Is metrics-server Pod running?**
```bash
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

**Expected**: `STATUS=Running`, `READY=1/1`

**If Pod is missing or not Ready**:
```bash
# Re-enable addon
minikube addons disable metrics-server
minikube addons enable metrics-server

# Wait 30 seconds
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s
```

**Check 2: Is metrics-server responding?**
```bash
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=20
```

**Look for errors like**:
- `unable to fetch pod metrics` → Wait 30s, metrics are still populating
- `TLS handshake error` → Minikube certificate issue (restart minikube)
- `connection refused` → Kubelet not responding (restart minikube)

**Check 3: Can API server reach metrics API?**
```bash
kubectl get apiservices | grep metrics
```

**Expected**:
```
v1beta1.metrics.k8s.io    kube-system/metrics-server   True
```

**If `False` in last column**:
```bash
kubectl delete apiservice v1beta1.metrics.k8s.io
# Will auto-recreate in 10-20s
```

### Solution: Nuclear Option (If All Else Fails)

```bash
# 1. Restart minikube
minikube stop
minikube start

# 2. Re-enable metrics-server
minikube addons enable metrics-server

# 3. Wait 60s
sleep 60

# 4. Test
kubectl top nodes
```

---

## HPA Showing `<unknown>`

### Symptom
```bash
kubectl get hpa api-hpa
# TARGETS: <unknown>/50%
```

### Diagnosis

**Root cause**: HPA cannot calculate percentage because:
1. Metrics not available yet (most common)
2. No resource requests defined
3. Target deployment has 0 Pods

**Check 1: Are metrics available?**
```bash
kubectl top pods -l app=api
```

**If you see `<unknown>` here too**:
- Metrics still populating (wait 30s)
- Metrics-server issue (see previous section)

**If you see values (e.g., `10m`)**: Proceed to Check 2.

**Check 2: Are resource requests defined?**
```bash
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'
```

**Expected**: `{"cpu":"100m","memory":"128Mi"}`

**If empty or missing `cpu`**:
```bash
# HPA REQUIRES cpu requests to calculate percentage!
# Add requests to deployment:
kubectl patch deployment api-deployment --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests", "value": {"cpu": "100m", "memory": "128Mi"}}
]'
```

**Check 3: Are Pods Running?**
```bash
kubectl get pods -l app=api
```

**If 0 Pods**: Deployment issue (check `kubectl describe deployment api-deployment`)

### Solution

**90% of cases**: Just wait 30-60 seconds for metrics to populate.

**If persistent after 2 minutes**:
```bash
# Force HPA refresh
kubectl delete hpa api-hpa
kubectl apply -f manifests/09-hpa-api.yaml

# Wait 30s
kubectl get hpa api-hpa
```

---

## HPA Not Scaling Up

### Symptom
```bash
# CPU is high but replicas don't increase
kubectl get hpa api-hpa
# TARGETS: 85%/50%   MIN: 1   MAX: 5   REPLICAS: 2  ← Stuck at 2
```

### Diagnosis

**Check 1: Is HPA allowed to scale up?**
```bash
kubectl get hpa api-hpa -o jsonpath='{.spec.maxReplicas}'
```

**If current replicas == maxReplicas**: HPA is at limit (can't scale further)

**Check 2: Is deployment at maxReplicas already?**
```bash
kubectl get hpa api-hpa -o jsonpath='{.status.currentReplicas}'
kubectl get hpa api-hpa -o jsonpath='{.status.desiredReplicas}'
```

**If currentReplicas != desiredReplicas**: Scale is pending (wait for Pods to start)

**Check 3: Are there scaling events?**
```bash
kubectl describe hpa api-hpa | tail -20
```

**Look for**:
- `FailedGetResourceMetric` → Metrics issue
- `FailedComputeMetricsReplicas` → Math error (check requests)
- `SuccessfulRescale` → It IS scaling (check Pod status)

**Check 4: Can Kubernetes schedule new Pods?**
```bash
kubectl get nodes
```

**If node resources exhausted**: Minikube can't fit more Pods

### Solutions

**If metrics issue**:
```bash
./scripts/setup-metrics.sh
```

**If at maxReplicas**:
```bash
# Increase limit (temporary)
kubectl patch hpa api-hpa --type='json' -p='[{"op": "replace", "path": "/spec/maxReplicas", "value": 10}]'
```

**If insufficient node resources**:
```bash
# Increase minikube memory/CPU
minikube delete
minikube start --cpus=4 --memory=4096
```

**If load is too low**:
```bash
# Increase load intensity
./scripts/generate-load.sh 50 120  # 50 req/s for 2 min
```

---

## HPA Not Scaling Down

### Symptom
```bash
# Load stopped, CPU low, but replicas stay high
kubectl get hpa api-hpa
# TARGETS: 8%/50%   REPLICAS: 5  ← Should scale down but doesn't
```

### Diagnosis

**Root cause**: This is **expected behavior** (not a bug).

HPA has a **5-minute stabilization window** for scale-down to prevent flapping.

**Check when scale-down is allowed**:
```bash
kubectl describe hpa api-hpa | grep -A 3 "Scale Down"
```

**Expected**:
```
Scale Down:
  Stabilization Window: 300 seconds  ← 5 minutes
```

**Check when load stopped**:
```bash
kubectl describe hpa api-hpa | grep -A 5 Events
```

**Look for**: Last `SuccessfulRescale` timestamp. Add 5 minutes = when scale-down will happen.

### Solution

**Just wait 5 minutes.**

If you REALLY need faster scale-down (not recommended for production):
```bash
kubectl patch hpa api-hpa --type='json' -p='[
  {"op": "replace", "path": "/spec/behavior/scaleDown/stabilizationWindowSeconds", "value": 60}
]'
# Now scale-down happens after 1 minute
```

**Why 5 minutes is good**:
- Prevents thrashing (rapid scale up/down)
- Gives time for load spikes to resolve
- Reduces cost of Pod churn (startup overhead)

---

## Rolling Update Stuck

### Symptom
```bash
kubectl rollout status deployment/api-deployment
# Waiting for deployment "api-deployment" rollout to finish: 1 out of 2 new replicas have been updated...
# ← Stuck here for > 5 minutes
```

### Diagnosis

**Check 1: Are new Pods starting?**
```bash
kubectl get pods -l app=api
```

**Look for**:
- `STATUS=Pending` → Scheduling issue (no resources)
- `STATUS=ContainerCreating` for > 2 min → Image pull issue
- `STATUS=CrashLoopBackOff` → New version is broken
- `READY=0/2` but `STATUS=Running` → Readiness probe failing

**Check 2: Describe stuck Pod**
```bash
# Replace xxx with actual Pod name
kubectl describe pod api-deployment-xxx
```

**Common issues**:

| Event Message | Cause | Solution |
|---------------|-------|----------|
| `ImagePullBackOff` | Image doesn't exist | Check image tag: `kubectl get deployment api-deployment -o yaml \| grep image:` |
| `Insufficient cpu` | Node full | Increase minikube: `minikube delete && minikube start --cpus=4` |
| `Readiness probe failed` | `/health` endpoint broken | Check logs: `kubectl logs api-deployment-xxx` |
| `CrashLoopBackOff` | App crashes at startup | Check logs: `kubectl logs api-deployment-xxx --previous` |

**Check 3: Check Pod logs**
```bash
kubectl logs -l app=api --tail=50
```

**Look for**:
- Database connection errors
- Missing environment variables
- Port conflicts

### Solutions

**If image doesn't exist**:
```bash
# Rollback to working version
kubectl rollout undo deployment/api-deployment
```

**If readiness probe too aggressive**:
```bash
# Temporarily increase initialDelaySeconds
kubectl patch deployment api-deployment --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 30}
]'
```

**If new version is broken**:
```bash
# Rollback immediately
kubectl rollout undo deployment/api-deployment
kubectl rollout status deployment/api-deployment
```

---

## Load Generator Fails

### Symptom
```bash
./scripts/generate-load.sh
# Error: API not reachable at http://192.168.49.2/api
```

### Diagnosis

**Check 1: Is Ingress working?**
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
```

**Expected**: `{"status":"healthy",...}`

**If connection refused**:
```bash
# Check Ingress controller
kubectl get pods -n ingress-nginx

# If not installed:
minikube addons enable ingress
```

**Check 2: Is API service resolving?**
```bash
kubectl get service api-service
```

**Expected**: `CLUSTER-IP` should be valid (not `<none>`)

**If missing**:
```bash
kubectl apply -f manifests/05-service-api.yaml
```

**Check 3: Are API Pods Running?**
```bash
kubectl get pods -l app=api
```

**If 0 Pods or not Ready**: Fix deployment first.

### Solutions

**Quick fix stack**:
```bash
# 1. Ensure all manifests applied
kubectl apply -f manifests/

# 2. Wait for rollout
kubectl rollout status deployment/api-deployment

# 3. Test manually
curl -H "Host: capstone.local" http://$(minikube ip)/api/health

# 4. If works, try load generator again
./scripts/generate-load.sh
```

---

## Pods Crash After Update

### Symptom
```bash
kubectl get pods -l app=api
# NAME                    READY   STATUS             RESTARTS
# api-deployment-xxx      1/2     CrashLoopBackOff   5
```

### Diagnosis

**Check logs of crashed container**:
```bash
kubectl logs api-deployment-xxx --previous
# --previous shows logs from the crashed instance
```

**Common errors**:

| Log Message | Cause | Solution |
|-------------|-------|----------|
| `Connection to postgres refused` | Database not ready | Wait 30s, check `kubectl get pods \| grep postgres` |
| `POSTGRES_PASSWORD not set` | Secret missing | Apply: `kubectl apply -f manifests/00-secret-postgres.yaml` |
| `Address already in use: 8080` | Port conflict (rare) | Check container image |
| `Killed` (no other message) | OOMKilled | Increase memory limit |

**Check resource limits**:
```bash
kubectl describe pod api-deployment-xxx | grep -A 5 Limits
```

**If `OOMKilled` in events**: Memory limit too low.

### Solutions

**If database connection issue**:
```bash
# Check postgres is Running
kubectl get pods | grep postgres

# If not Running:
kubectl apply -f manifests/02-deployment-postgres.yaml
kubectl rollout status deployment/postgres
```

**If Secret missing**:
```bash
kubectl apply -f manifests/00-secret-postgres.yaml
# Restart Pods to pick up secret:
kubectl rollout restart deployment/api-deployment
```

**If OOMKilled**:
```bash
# Increase memory limit
kubectl patch deployment api-deployment --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'
```

**If new version is fundamentally broken**:
```bash
# Rollback to last working version
kubectl rollout undo deployment/api-deployment
```

---

## Still Stuck?

### Gather Debug Info

Before asking the instructor, collect:

```bash
# 1. Full status
kubectl get all

# 2. HPA status
kubectl get hpa -o yaml

# 3. Deployment status
kubectl describe deployment api-deployment

# 4. Pod logs
kubectl logs -l app=api --tail=100

# 5. Events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# 6. Metrics
kubectl top nodes
kubectl top pods
```

### Common "It Works on My Machine" Issues

1. **Wrong namespace**: All commands assume `default` namespace
2. **Old minikube version**: Update with `minikube update-check`
3. **Insufficient resources**: `minikube start --cpus=2 --memory=4096`
4. **Cached images**: `minikube ssh docker system prune -af`
5. **WSL2 networking**: Restart WSL: `wsl --shutdown` (Windows only)

---

**📚 Reference**: [Kubernetes Debugging Guide](https://kubernetes.io/docs/tasks/debug/)
