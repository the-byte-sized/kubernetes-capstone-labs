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

# Lab 5.2: HPA Configuration (15 minutes)

## Goal

Configure HorizontalPodAutoscaler to automatically scale the API based on CPU usage.

---

## Step 1: Review HPA Manifest

```bash
cat manifests/09-hpa-api.yaml
```

**Key fields**:
```yaml
spec:
  scaleTargetRef:
    name: api-deployment  # Target deployment
  minReplicas: 1          # Never scale below this
  maxReplicas: 5          # Never scale above this
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 50  # Target: 50% of requests (100m)
```

**What this means**:
- HPA will try to keep CPU at **50% of the 100m request** = 50m
- If average CPU > 50m → scale up
- If average CPU < 50m (for 5 min) → scale down

---

## Step 2: Apply HPA

```bash
kubectl apply -f manifests/09-hpa-api.yaml
```

**Expected output**:
```
horizontalpodautoscaler.autoscaling/api-hpa created
```

---

## Step 3: Verify HPA Status

```bash
kubectl get hpa api-hpa
```

**Expected output (initially)**:
```
NAME      REFERENCE                TARGETS   MINPODS   MAXPODS   REPLICAS
api-hpa   Deployment/api-deployment   12%/50%   1         5         2
```

**Understanding the output**:
- `TARGETS`: Current CPU % / Target CPU %
- `12%/50%` means: using 12% of requests, target is 50%
- `REPLICAS`: Current number of Pods (starts at 2 from deployment)

**⚠️ If you see `<unknown>/50%`**: Wait 30s for metrics to populate, then check again.

---

## Step 4: Observe Initial HPA Behavior

```bash
# Watch HPA continuously
watch -n 2 'kubectl get hpa api-hpa'
```

**What you should see**:
- Current CPU stays low (~10-15%) because there's no load
- HPA keeps `REPLICAS` at current level (no scaling needed yet)
- After 5 minutes of low CPU, HPA may scale down to `minReplicas: 1`

**Press Ctrl+C to exit watch when ready.**

---

## Step 5: Understand Scale-Down Delay

```bash
kubectl describe hpa api-hpa | grep -A 5 "Scale Down"
```

**Expected output**:
```
Scale Down:
  Stabilization Window: 300 seconds
  Select Policy: Max
  Policies:
    - Type: Percent  Value: 50  Period: 60 seconds
```

**What this means**:
- Scale-down waits **5 minutes** (300s) to avoid flapping
- Can reduce replicas by max 50% every 60 seconds
- Scale-up is immediate (no stabilization window)

**🎓 Key KCNA concept**: Stabilization prevents "thrashing" (rapid scale up/down cycles).

---

## ✅ Checkpoint 2: HPA Configured

Run verification:
```bash
./verify.sh checkpoint2
```

**Expected**:
```
✅ HPA 'api-hpa' exists
✅ HPA TARGETS populated (12%)
✅ Checkpoint 2 passed!
```

---

**🎉 Lab 5.2 Complete!** HPA is now monitoring CPU and ready to scale.

**Next**: Generate load to trigger automatic scaling.

---

# Lab 5.3: Load Testing & Scaling (30 minutes)

## Goal

Generate sustained load to trigger HPA scale-up, then observe scale-down after load stops.

---

## Step 1: Open Monitoring Dashboard

Open a **dedicated terminal** for monitoring:

```bash
cd day-05-observability-autoscaling/
./scripts/monitor-hpa.sh
```

**What you'll see**:
- Real-time HPA status (CPU %, replicas)
- List of API Pods with their status
- Scaling events detection (🔼 SCALING UP / 🔽 SCALING DOWN)
- Color-coded indicators (green = healthy, yellow = near target, red = over target)

**Keep this terminal visible** during the lab.

---

## Step 2: Generate Load

Open a **second terminal** and run the load generator:

```bash
cd day-05-observability-autoscaling/
./scripts/generate-load.sh
```

**Default behavior**: 20 req/s for 5 minutes

**What the script does**:
- Sends POST and GET requests to `/api/tasks`
- Shows progress bar with elapsed time
- Displays success/failed request counts
- Auto-stops after duration (or press Ctrl+C)

**Script output example**:
```
🔥 Task API Load Generator
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Rate:     20 req/s (40 total req/s with POST+GET)
Duration: 300 seconds (5 min)
Press Ctrl+C to stop early
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Progress: [==========          ] 40% | 120s/300s | Requests: 960
```

---

## Step 3: Observe Scale-Up (2-3 minutes)

**In the monitoring terminal**, watch for these events:

### Phase 1: CPU Increases (0-60s)
- `TARGETS`: 12% → 35% → 58% → 75%
- HPA detects: "CPU above 50% target"
- Status: Red line in monitor dashboard

### Phase 2: HPA Decides to Scale (60-90s)
- `DESIRED` changes: 2 → 3 replicas
- New Pod starts: `api-deployment-xxx` in `Pending` state

### Phase 3: New Pod Becomes Ready (90-120s)
- Pod transitions: `Pending` → `ContainerCreating` → `Running`
- Readiness probe passes (checks `/health`)
- `REPLICAS`: 2 → 3
- **🔼 SCALING UP: 2 → 3 replicas** (green alert in monitor)

### Phase 4: CPU Distributes (120-180s)
- CPU per Pod: 75% → 50% → 35% (load spreads across 3 Pods)
- `TARGETS` returns to green zone (~30-40%)

**If CPU stays > 50%**: HPA may scale to 4 or 5 replicas (up to `maxReplicas`)

---

## Step 4: Advanced Load Test (Optional)

If you want to force scale to `maxReplicas`, run **aggressive load**:

```bash
# In the load generator terminal (stop previous with Ctrl+C if running)
./scripts/generate-load.sh 50 120
# 50 req/s for 2 minutes
```

**Expected**: HPA scales to 4 or 5 replicas within 2-3 minutes.

---

## Step 5: Stop Load & Observe Scale-Down

When the load generator stops (or you press Ctrl+C):

### Phase 1: CPU Drops Immediately (0-30s)
- `TARGETS`: 75% → 20% → 8%
- Status: Green in monitor

### Phase 2: Stabilization Window (0-5 min)
- HPA waits **5 minutes** before scaling down
- `DESIRED` stays at current replicas (e.g., 3)
- This prevents flapping if load returns

**💡 You'll see**: "Low CPU detected, but waiting for stabilization window"

### Phase 3: Scale-Down Triggered (after 5 min)
- `DESIRED` changes: 3 → 2 replicas
- One Pod receives `SIGTERM` (graceful shutdown)
- Pod transitions: `Running` → `Terminating` → removed
- **🔽 SCALING DOWN: 3 → 2 replicas**

### Phase 4: Further Scale-Down (after another 5 min)
- If CPU stays low and `REPLICAS > minReplicas`
- HPA scales down to `minReplicas: 1`

**⏱️ Patience required**: Full scale-down takes 10-15 minutes total.

---

## Step 6: Verify Scaling History

```bash
kubectl describe hpa api-hpa | tail -20
```

**Look for Events section**:
```
Events:
  Type    Reason             Message
  ----    ------             -------
  Normal  SuccessfulRescale  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  New size: 2; reason: All metrics below target
```

**🎓 Learning**: Events log shows HPA's decision history.

---

## ✅ Checkpoint 3: Scaling Verified

Run verification:
```bash
./verify.sh checkpoint3
```

**Expected**:
```
✅ HPA is managing replicas
✅ HPA has scaled up (replicas > minReplicas)
✅ Checkpoint 3 passed!
```

**If "HPA at minimum replicas"**: This is OK if you just stopped the load test. HPA will scale up again next time load increases.

---

**🎉 Lab 5.3 Complete!** You've witnessed automatic scaling in action.

**Next**: Perform a rolling update to deploy a new version without downtime.

---

# Lab 5.4: Rolling Update (20 minutes)

## Goal

Update the API from `v1.0.0` to `v1.1.0` with zero downtime using Kubernetes rolling update strategy.

---

## Step 1: Verify Current Version

```bash
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
```

**Expected output**:
```
ghcr.io/the-byte-sized/task-api:v1.0.0
```

---

## Step 2: Review Rolling Update Strategy

```bash
kubectl get deployment api-deployment -o yaml | grep -A 5 "strategy:"
```

**Expected output**:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 25%
    maxSurge: 25%
```

**What this means**:
- **maxUnavailable**: Max 25% of Pods can be unavailable during update (for 2 replicas = 0.5 ≈ 0 Pods)
- **maxSurge**: Max 25% extra Pods can exist during update (for 2 replicas = 0.5 ≈ 1 Pod)
- Result: Kubernetes creates 1 new Pod before terminating any old Pods

**🎓 KCNA concept**: This ensures **zero downtime** (service always has Pods Ready).

---

## Step 3: Open Monitoring Terminals

### Terminal 1: Watch Rollout Status
```bash
kubectl rollout status deployment/api-deployment --watch
```

### Terminal 2: Watch Pods
```bash
watch -n 1 'kubectl get pods -l app=api -o wide'
```

### Terminal 3: Test Service Availability
```bash
while true; do
  RESPONSE=$(curl -s -H "Host: capstone.local" http://$(minikube ip)/api/health || echo "FAIL")
  if echo "$RESPONSE" | grep -q "healthy"; then
    echo "[$(date +%H:%M:%S)] ✅ API healthy"
  else
    echo "[$(date +%H:%M:%S)] ❌ API failed"
  fi
  sleep 1
done
```

**Keep all 3 terminals visible** during the update.

---

## Step 4: Trigger Rolling Update

In a **fourth terminal**, update the image:

```bash
kubectl set image deployment/api-deployment \
  api=ghcr.io/the-byte-sized/task-api:v1.1.0 \
  --record
```

**Expected output**:
```
deployment.apps/api-deployment image updated
```

---

## Step 5: Observe Rolling Update Process

**In Terminal 1 (rollout status)**:
```
Waiting for deployment "api-deployment" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "api-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "api-deployment" successfully rolled out
```

**In Terminal 2 (pods watch)**:

### Phase 1: New Pod Created (0-10s)
```
NAME                             READY   STATUS              AGE
api-deployment-v1-xxx            2/2     Running             10m
api-deployment-v1-yyy            2/2     Running             10m
api-deployment-v2-zzz            0/2     ContainerCreating   3s
```

### Phase 2: New Pod Ready (10-20s)
```
NAME                             READY   STATUS    AGE
api-deployment-v1-xxx            2/2     Running   10m
api-deployment-v1-yyy            2/2     Running   10m
api-deployment-v2-zzz            2/2     Running   15s  ← NEW
```

### Phase 3: Old Pod Terminating (20-30s)
```
NAME                             READY   STATUS        AGE
api-deployment-v1-xxx            2/2     Running       10m
api-deployment-v1-yyy            2/2     Terminating   10m  ← TERMINATING
api-deployment-v2-zzz            2/2     Running       25s
```

### Phase 4: Process Repeats (30-60s)
- Another new v2 Pod created
- Becomes Ready
- Last v1 Pod terminates
- **Result**: All Pods now v1.1.0

**In Terminal 3 (availability test)**:
```
[19:45:10] ✅ API healthy
[19:45:11] ✅ API healthy
[19:45:12] ✅ API healthy  ← NO FAILURES during entire rollout
[19:45:13] ✅ API healthy
```

**🎉 Zero downtime achieved!**

---

## Step 6: Verify New Version Deployed

```bash
# Stop the while loops in terminals (Ctrl+C)

# Check image version
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
```

**Expected output**:
```
ghcr.io/the-byte-sized/task-api:v1.1.0
```

```bash
# Check all Pods are v1.1.0
kubectl get pods -l app=api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

**Expected**: All Pods show `task-api:v1.1.0`

---

## ✅ Checkpoint 4: Rolling Update Complete

Run verification:
```bash
./verify.sh checkpoint4
```

**Expected**:
```
✅ Deployment using versioned image: ghcr.io/the-byte-sized/task-api:v1.1.0
✅ Deployment rollout complete
✅ Checkpoint 4 passed!
```

---

**🎉 Lab 5.4 Complete!** You've performed a zero-downtime rolling update.

**Next**: Learn how to rollback if the new version has issues.

---

# Lab 5.5: Rollback (10 minutes)

## Goal

Quickly revert to the previous version if the new deployment has issues.

---

## Step 1: Check Rollout History

```bash
kubectl rollout history deployment/api-deployment
```

**Expected output**:
```
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl set image deployment/api-deployment api=ghcr.io/the-byte-sized/task-api:v1.1.0 --record=true
```

**Understanding**:
- `REVISION 1`: Original v1.0.0
- `REVISION 2`: Current v1.1.0

---

## Step 2: Simulate Issue Detection

**Scenario**: "Production monitoring detects errors in v1.1.0. We need to rollback immediately."

```bash
# Check current version
echo "Current version (broken):"
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
```

---

## Step 3: Execute Rollback

```bash
kubectl rollout undo deployment/api-deployment
```

**Expected output**:
```
deployment.apps/api-deployment rolled back
```

**Watch rollback progress**:
```bash
kubectl rollout status deployment/api-deployment
```

**Expected**:
```
Waiting for deployment "api-deployment" rollout to finish...
deployment "api-deployment" successfully rolled out
```

**⏱️ Duration**: 30-60 seconds (same as rolling update)

---

## Step 4: Verify Rollback

```bash
# Check version reverted
kubectl get deployment api-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
```

**Expected output**:
```
ghcr.io/the-byte-sized/task-api:v1.0.0  ← Back to v1.0.0!
```

```bash
# Check all Pods running v1.0.0
kubectl get pods -l app=api
```

**Expected**: All Pods show age < 2 minutes (newly created during rollback)

---

## Step 5: Rollback to Specific Revision (Advanced)

You can also rollback to a specific revision:

```bash
# See all revisions
kubectl rollout history deployment/api-deployment

# Rollback to revision 2 (if needed)
kubectl rollout undo deployment/api-deployment --to-revision=2
```

**Use case**: If you have revisions 1, 2, 3 and want to skip back to 1 directly.

---

## Step 6: Understand Rollback Limitations

**⚠️ Important KCNA knowledge**:

1. **Rollback reverts Pod template only**
   - Image version ✅
   - Environment variables ✅
   - Resource limits ✅
   - ConfigMaps/Secrets ❌ (not part of Deployment revision)

2. **Rollback doesn't fix data issues**
   - Database schema changes require manual migration
   - PVC data is NOT rolled back

3. **History is limited**
   - Default: last 10 revisions kept
   - Configurable via `spec.revisionHistoryLimit`

---

**🎉 Lab 5.5 Complete!** You know how to quickly recover from bad deployments.

---

# 🤔 Theory: Why NO HPA on Frontend?

## The Question

You configured HPA on the API deployment, but not on the web frontend. Why?

---
## The Answer: Workload Characteristics Matter

### Frontend (nginx serving static files)
- **CPU usage**: ~2m per Pod (4% of 50m request)
- **Bottleneck**: Network bandwidth, NOT CPU
- **Load pattern**: Even with 1000 req/s, CPU stays < 10m
- **Scaling impact**: Adding replicas doesn't help when CPU isn't the problem

### API (Flask + PostgreSQL queries)
- **CPU usage**: ~10-80m per Pod depending on load
- **Bottleneck**: CPU (processing requests + database queries)
- **Load pattern**: CPU directly correlates with request rate
- **Scaling impact**: More replicas = more concurrent request capacity ✅

---

## When WOULD Frontend Need HPA?

If the frontend did:
- **Server-Side Rendering (SSR)**: Template processing (Jinja2, React SSR)
- **Image processing**: Resizing/compression on-the-fly
- **Complex routing logic**: Heavy computation per request
- **Authentication**: Token validation, session management

Then CPU would be significant → HPA makes sense.

---

## Better Solutions for Static Content

1. **CDN** (Content Delivery Network): Cache at edge locations
2. **Horizontal scaling via replicas** (fixed, not auto): 3-5 replicas for redundancy
3. **Load balancer**: Distribute traffic (already done via Service)

**KCNA principle**: "Scale what matters, based on actual bottlenecks."

---

# 📊 Deployment Strategies Comparison

We practiced **Rolling Update** today. Here's how it compares to other strategies:

---

## Rolling Update (What We Used)

**How it works**: Gradually replace old Pods with new ones.

**Pros**:
- ✅ Zero downtime (always have Pods Ready)
- ✅ Simple to configure (default in Kubernetes)
- ✅ Automatic rollback support
- ✅ No extra resource cost (reuses Pods)

**Cons**:
- ❌ Both versions run simultaneously (briefly)
- ❌ Rollback takes time (need to update Pods again)
- ❌ Gradual exposure means gradual error detection

**When to use**: Default choice for most applications.

---

## Blue/Green

**How it works**: Two complete environments (blue = current, green = new). Switch traffic atomically.

**Pros**:
- ✅ Instant cutover (change Service selector)
- ✅ Instant rollback (switch back to blue)
- ✅ Full testing possible before switch (green gets no traffic initially)

**Cons**:
- ❌ **2x resource cost** (both environments running)
- ❌ More complex to manage (two deployments)
- ❌ Database migrations tricky (schema must work with both versions)

**When to use**:
- High-stakes releases (financial transactions)
- When instant rollback is critical
- When you can afford 2x resources temporarily

**See**: [bonus-bluegreen.md](./bonus-bluegreen.md) for hands-on lab

---

## Canary

**How it works**: Route small % of traffic (e.g., 10%) to new version, monitor metrics, gradually increase.

**Pros**:
- ✅ **Reduced blast radius** (only 10% users affected by bugs)
- ✅ Gradual rollout (10% → 50% → 100%)
- ✅ Data-driven decisions (increase % only if metrics healthy)

**Cons**:
- ❌ Requires **traffic splitting** (Ingress feature or service mesh)
- ❌ Longer deployment time (gradual vs instant)
- ❌ Need monitoring to make decisions (can't be fully automated)

**When to use**:
- Critical services with large user base
- When you can monitor metrics in real-time
- When risk mitigation > speed

**See**: [bonus-canary.md](./bonus-canary.md) for hands-on lab

---

## Comparison Table

| Strategy | Downtime | Resource Cost | Rollback Speed | Complexity | Best For |
|----------|----------|---------------|----------------|------------|----------|
| **Rolling Update** | Zero | 1x (standard) | Minutes (re-deploy) | Low | Most apps |
| **Blue/Green** | Zero | 2x (temporary) | Seconds (switch) | Medium | High-stakes |
| **Canary** | Zero | 1.1x (temporary) | Seconds (stop increase) | High | Large user base |

---

## KCNA Exam Focus

Exam tests **understanding trade-offs**, not implementation:
- "Which strategy allows instant rollback?" → Blue/Green
- "Which minimizes user impact of bugs?" → Canary
- "Which is simplest for small teams?" → Rolling Update

---

# ✅ Day 5 Definition of Done

**You have successfully built an observable, self-scaling, production-ready system:**

✅ **Observability**: metrics-server installed, `kubectl top` working  
✅ **Resource Monitoring**: Understand CPU/memory requests vs usage  
✅ **Autoscaling**: HPA configured, tested scale-up and scale-down  
✅ **Load Testing**: Simulated traffic, observed system reaction  
✅ **Zero-Downtime Deployment**: Rolling update from v1.0.0 to v1.1.0  
✅ **Rollback**: Reverted to previous version in < 60 seconds  
✅ **Conceptual Understanding**: Know when NOT to autoscale (frontend)  
✅ **Strategy Comparison**: Understand Rolling/Blue-Green/Canary trade-offs  

**Skills mastered**:
- Reading HPA status and metrics
- Generating and monitoring load
- Interpreting scaling events
- Performing production deployments
- Making architectural decisions based on workload characteristics

---

# 🧹 Cleanup (Optional)

If you want to reset to Day 4 state:

```bash
# Remove HPA
kubectl delete hpa api-hpa

# Revert to Day 4 manifests
cd ../day-04-storage-security/
kubectl apply -f manifests/05-deployment-api.yaml
kubectl apply -f manifests/08-deployment-web.yaml

# Disable metrics-server (optional)
minikube addons disable metrics-server
```

**Or use the cleanup script**:
```bash
cd day-05-observability-autoscaling/
./scripts/cleanup-day5.sh
```

---

# 🎯 What's Next?

## Bonus Labs (If Time Permits)

1. **Blue/Green Deployment** [bonus-bluegreen.md](./bonus-bluegreen.md)
   - Deploy two environments simultaneously
   - Practice instant traffic switch
   - Experience instant rollback

2. **Canary Deployment** [bonus-canary.md](./bonus-canary.md)
   - Configure Nginx Ingress for traffic splitting
   - Route 10% traffic to new version
   - Gradually promote canary to 100%

## Beyond KCNA

After completing KCNA certification, explore:
- **Advanced observability**: Prometheus, Grafana, Jaeger
- **Service mesh**: Istio, Linkerd for advanced traffic management
- **GitOps**: ArgoCD, Flux for declarative deployments
- **Advanced HPA**: Custom metrics, external metrics adapters

---

# 📚 Additional Resources

## Official Documentation
- [HorizontalPodAutoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Deployment Strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
- [Rolling Updates](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)

## KCNA Exam Resources
- [KCNA Curriculum](https://github.com/cncf/curriculum/blob/master/kcna/README.md)
- [CNCF Glossary - Autoscaling](https://glossary.cncf.io/autoscaling/)
- [CNCF Glossary - Observability](https://glossary.cncf.io/observability/)

## Troubleshooting
- [troubleshooting.md](./troubleshooting.md) - Detailed error solutions
- [Minikube Metrics Server Issues](https://minikube.sigs.k8s.io/docs/tutorials/metrics_server/)

---

**🎉 Congratulations on completing Day 5!**

You now understand how to build systems that observe themselves, scale automatically, and deploy safely. These are critical production skills for any Kubernetes engineer.

**Good luck with your KCNA certification! 🚀**
