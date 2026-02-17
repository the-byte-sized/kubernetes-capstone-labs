# Day 5: Observability, Metrics, Autoscaling & Deployment Strategies

## 🎯 Learning Objectives

By the end of this lab, you will be able to:
- [ ] Install and verify metrics-server for resource monitoring
- [ ] Use `kubectl top` to observe CPU and memory usage
- [ ] Configure HorizontalPodAutoscaler (HPA) based on CPU metrics
- [ ] Generate load to trigger automatic scaling
- [ ] Observe scaling behavior and understand stabilization windows
- [ ] Perform rolling updates with zero downtime
- [ ] Execute rollback to previous version
- [ ] Explain when NOT to use autoscaling (static workloads)
- [ ] Compare Rolling Update, Blue/Green, and Canary strategies

**KCNA Domains Covered:**
- **Kubernetes Fundamentals (44%)**: Resource requests/limits, autoscaling
- **Container Orchestration (28%)**: HPA, rolling updates, self-healing
- **Cloud Native Application Delivery (16%)**: Deployment strategies, zero-downtime releases

---

## 📋 Prerequisites

**Before starting, ensure:**

1. ✅ **Day 4 completed**: PVC, API, Frontend, Ingress working
2. ✅ **Minikube running**: `minikube status` shows all Running
3. ✅ **Images tagged**: `task-api:v1.0.0` and `v1.1.0` available (pre-configured)
4. ✅ **Resource requests set**: API/Web deployments have CPU/memory requests

**Quick verification**:
```bash
# Check Day 4 stack is running
kubectl get pods
# Expected: postgres, api-deployment (2/2), web-deployment (3/3)

# Check resource requests exist
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'
# Expected: {"cpu":"100m","memory":"128Mi"}

# Check Ingress working
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Expected: {"status":"healthy",...}
```

**If any check fails**, go back to Day 4 and complete it first.

---

## 🚨 BEFORE YOU START: Migration from Day 4

**IMPORTANT**: Day 5 uses **versioned images** instead of `:latest`.

**What changes:**
- API image: `task-api:latest` → `task-api:v1.0.0`
- Web image: `task-web:latest` → `task-web:v1.0.0`
- HPA added for API deployment
- All other resources (PVC, Services, Ingress) unchanged

**Migration path** (choose ONE):

### Option A: Fresh Start (Recommended if you had issues in Day 4)
```bash
# Clean Day 4 resources (keeps PVC data)
kubectl delete deployment api-deployment web-deployment postgres
kubectl delete service api-service web-service postgres-service
# Keep: PVC, Secret, Ingress, RBAC

# Apply Day 5 manifests
cd day-05-observability-autoscaling/
kubectl apply -f manifests/
```

### Option B: In-Place Update (If Day 4 is stable)
```bash
# Just update deployments with new manifests
cd day-05-observability-autoscaling/
kubectl apply -f manifests/04-deployment-api-v1.yaml
kubectl apply -f manifests/06-deployment-web-v1.yaml
kubectl apply -f manifests/09-hpa-api.yaml

# Verify rollout
kubectl rollout status deployment/api-deployment
kubectl rollout status deployment/web-deployment
```

**See [MIGRATION-FROM-DAY4.md](./MIGRATION-FROM-DAY4.md) for detailed comparison.**

---

## 🏗️ What We're Building Today

Today we add **observability and automation** to the existing stack:

```
                    📊 METRICS-SERVER
                          ↓
                    (collects metrics)
                          ↓
[Ingress] → [Web (3 replicas)] + [API (1-5 replicas ← HPA)] → [Postgres]
                                        ↑
                                   (autoscales)
                                        ↓
                              When CPU > 50%
```

**New capabilities:**
- ✅ Real-time resource usage via `kubectl top`
- ✅ Automatic scaling based on CPU load
- ✅ Zero-downtime version updates
- ✅ Instant rollback if issues detected

---

## ⏱️ Estimated Time

- **Lab 5.1** (Metrics Pipeline): 20 minutes
- **Lab 5.2** (HPA Setup): 15 minutes
- **Lab 5.3** (Load Testing): 30 minutes
- **Lab 5.4** (Rolling Update): 20 minutes
- **Lab 5.5** (Rollback): 10 minutes
- **Total Core Labs**: ~95 minutes (~1.5 hours)
- **Bonus Labs** (Blue/Green, Canary): +30-40 minutes each (optional)

---

## 🚨 TROUBLESHOOTING FIRST

**BEFORE ASKING THE INSTRUCTOR**, check these common issues:

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------||
| `kubectl top` says "Metrics API not available" | metrics-server not ready | Wait 30s, run `./scripts/setup-metrics.sh` |
| HPA shows `<unknown>` in TARGETS | No resource requests OR metrics-server not ready | Check deployment has `resources.requests.cpu` |
| HPA doesn't scale up | CPU below target OR load too low | Increase load: `./scripts/generate-load.sh 50 120` |
| HPA doesn't scale down | Cooldown period (5 min) | Wait, or check `behavior.scaleDown` settings |
| Rolling update stuck | Readiness probe failing | Check logs: `kubectl logs -l app=api --tail=50` |

**Full troubleshooting guide**: [troubleshooting.md](./troubleshooting.md)

---

# Lab 5.1: Metrics Pipeline (20 minutes)

## Goal

Install metrics-server and verify you can observe real-time CPU/memory usage.

---

## Step 1: Verify Metrics Server is NOT Installed Yet

```bash
kubectl top nodes
```

**Expected output (error is OK here)**:
```
error: Metrics API not available
```

**Why this is expected**: Minikube doesn't include metrics-server by default.

---

## Step 2: Install Metrics Server

**Automated method** (recommended):
```bash
cd day-05-observability-autoscaling/
chmod +x scripts/*.sh
./scripts/setup-metrics.sh
```

**What the script does**:
1. Enables minikube metrics-server addon
2. Waits for metrics-server Pod to be Ready
3. Waits for Metrics API to become available
4. Runs verification tests
5. Shows example `kubectl top` output

**Script output (expected)**:
```
🔧 Setting up metrics-server...
✅ metrics-server addon enabled
⏳ Waiting for metrics-server to be ready...
✅ metrics-server Pod is Running
⏳ Waiting for Metrics API to become available (can take 30-60s)...
✅ Metrics API is available
✅ Setup complete!
```

**⚠️ WAIT HERE**: If script says "still waiting...", give it 60 more seconds.

**Manual method** (if script fails):
```bash
# Enable addon
minikube addons enable metrics-server

# Wait for Pod
kubectl get pods -n kube-system -l k8s-app=metrics-server -w
# Wait until READY=1/1 (Ctrl+C to exit watch)

# Test API (may fail for first 30-60s)
kubectl top nodes
```

---

## Step 3: Verify Metrics Collection

```bash
# Check nodes
kubectl top nodes
```

**Expected output**:
```
NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
minikube   450m         11%    2100Mi          27%
```

**If you see `<unknown>`**: Wait 30 more seconds and try again.

```bash
# Check Pods
kubectl top pods
```

**Expected output**:
```
NAME                              CPU(cores)   MEMORY(bytes)   
api-deployment-xxx                10m          85Mi            
api-deployment-yyy                8m           82Mi            
postgres-xxx                      5m           45Mi            
web-deployment-xxx                2m           18Mi            
web-deployment-yyy                2m           17Mi            
web-deployment-zzz                2m           19Mi
```

**🟢 Success criteria**:
- ✅ `kubectl top nodes` shows CPU/Memory percentages
- ✅ `kubectl top pods` shows values (not `<unknown>`)
- ✅ API Pods show ~5-15m CPU (idle state)

---

## Step 4: Understand What You're Seeing

**CPU values**:
- `10m` = 10 millicores = 0.01 CPU cores = 1% of 1 core
- API requested `100m` (0.1 core), using ~10m = **10% of request**
- Web requested `50m` (0.05 core), using ~2m = **4% of request**

**Memory values**:
- `85Mi` = 85 Mebibytes
- API requested `128Mi`, using ~85Mi = **66% of request**

**Key concept for KCNA**:
> HPA uses **percentage of resource requests**, not absolute values.
> Without requests, HPA cannot calculate utilization → shows `<unknown>`.

---

## Step 5: Generate Some Load to See Metrics Change

```bash
# In terminal 1: Watch metrics
watch -n 2 'kubectl top pods -l app=api'

# In terminal 2: Send requests
for i in {1..50}; do
  curl -s -H "Host: capstone.local" http://$(minikube ip)/api/tasks > /dev/null
done
```

**Observe in terminal 1**:
- CPU usage increases during requests (15m → 25m → 35m)
- CPU usage decreases after requests stop
- Memory stays relatively stable

**🎓 Learning**:
- API workload is CPU-bound (CPU varies with load)
- This makes it a **good candidate for HPA**
- Static workloads (like web frontend) don't benefit from HPA

---

## ✅ Checkpoint 1: Metrics Pipeline Working

Run verification:
```bash
./verify.sh checkpoint1
```

**Expected**:
```
✅ metrics-server Pod is Running
✅ Metrics API is available
✅ kubectl top nodes works
✅ kubectl top pods works (no <unknown>)
✅ Checkpoint 1 passed!
```

**If any check fails**, see [troubleshooting.md#metrics-server-issues](./troubleshooting.md#metrics-server-issues).

---

**🎉 Lab 5.1 Complete!** You can now observe resource usage in real-time.

**Next**: Configure HPA to make scaling decisions based on these metrics.

---
