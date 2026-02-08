# Day 1: Troubleshooting Guide

Common issues and their solutions for Day 1 Foundation lab.

---

## 🔴 Issue 1: Pod Stuck in `Pending` State

### Symptom
```bash
$ kubectl get pod web
NAME   READY   STATUS    RESTARTS   AGE
web    0/1     Pending   0          2m
```

### Diagnosis
```bash
kubectl describe pod web | grep -A 10 Events
```

### Common Causes

**A) Insufficient resources on node**
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedScheduling  0/1 nodes are available: insufficient memory.
```

**Fix:**
```bash
# Check node resources
kubectl describe node minikube | grep -A 5 "Allocated resources"

# If Minikube has low resources, restart with more
minikube delete
minikube start --memory=4096 --cpus=2
```

**B) No nodes available**
```bash
# Check if node is Ready
kubectl get nodes
```

If node shows `NotReady`:
```bash
# Restart Minikube
minikube stop
minikube start
```

**C) Scheduler not running**
```bash
# Check control plane pods
kubectl get pods -n kube-system | grep scheduler
```

If scheduler is missing or not Running, restart Minikube.

---

## 🔴 Issue 2: Pod in `ImagePullBackOff` or `ErrImagePull`

### Symptom
```bash
$ kubectl get pod web
NAME   READY   STATUS             RESTARTS   AGE
web    0/1     ImagePullBackOff   0          3m
```

### Diagnosis
```bash
kubectl describe pod web | grep -A 5 "Events:"
```

### Common Causes

**A) Typo in image name or tag**
```
Failed to pull image "nginx:1.25-alpne": rpc error: code = NotFound
```

**Fix:**
```bash
# Check image name in manifest
cat manifests/02-pod-web.yaml | grep image

# Correct image: nginx:1.25-alpine (not "alpne")
# Edit manifest and reapply
kubectl delete pod web
kubectl apply -f manifests/02-pod-web.yaml
```

**B) Network connectivity issues**
```bash
# Test if Minikube can reach Docker Hub
minikube ssh
docker pull nginx:1.25-alpine
exit
```

If pull fails, check:
- Internet connection
- Firewall/proxy settings
- Corporate network restrictions

**C) Rate limiting from Docker Hub**

Docker Hub has rate limits for anonymous users. Wait a few minutes or authenticate:
```bash
# Create Docker Hub secret (if needed)
kubectl create secret docker-registry dockerhub \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD
```

---

## 🔴 Issue 3: Pod Running but `port-forward` Fails

### Symptom
```bash
$ kubectl port-forward pod/web 8080:80
Error from server: error forwarding port 80 to pod ..., 
uid : failed to execute portforward in network namespace ...
```

### Diagnosis
```bash
# Check if Pod is actually Running
kubectl get pod web

# Check Pod details
kubectl describe pod web
```

### Common Causes

**A) Port 8080 already in use on local machine**
```bash
# Check what's using port 8080
lsof -i :8080   # macOS/Linux
netstat -ano | findstr :8080  # Windows
```

**Fix:** Use a different port
```bash
kubectl port-forward pod/web 8081:80
# Then open: http://localhost:8081
```

**B) Pod not fully started yet**

Wait 10-20 seconds after Pod shows `Running`, then retry.

**C) Container port mismatch**

Verify the Pod is listening on port 80:
```bash
kubectl logs web
# Should show nginx starting on port 80
```

---

## 🔴 Issue 4: HTML Page Shows nginx Default, Not Custom Content

### Symptom
Browser shows "Welcome to nginx!" instead of Task Tracker page.

### Diagnosis
```bash
# Check if ConfigMap exists
kubectl get configmap web-html

# Check ConfigMap content
kubectl describe configmap web-html

# Check if Pod is using ConfigMap
kubectl describe pod web | grep -A 10 Volumes
```

### Common Causes

**A) ConfigMap not created**
```bash
# Apply ConfigMap first
kubectl apply -f manifests/01-configmap-html.yaml

# Then restart Pod to pick up the mount
kubectl delete pod web
kubectl apply -f manifests/02-pod-web.yaml
```

**B) ConfigMap created after Pod**

If you created the Pod before the ConfigMap, the volume mount will fail.

**Fix:**
```bash
# Delete and recreate in correct order
kubectl delete pod web
kubectl apply -f manifests/01-configmap-html.yaml
kubectl apply -f manifests/02-pod-web.yaml
```

**C) Wrong ConfigMap name in Pod spec**

Check Pod manifest references correct ConfigMap:
```bash
cat manifests/02-pod-web.yaml | grep -A 3 "volumes:"
```

Should show:
```yaml
volumes:
- name: html-content
  configMap:
    name: web-html  # Must match ConfigMap metadata.name
```

---

## 🔴 Issue 5: `verify.sh` Script Fails with "Permission Denied"

### Symptom
```bash
$ ./verify.sh
bash: ./verify.sh: Permission denied
```

### Fix
```bash
# Make script executable
chmod +x verify.sh

# Then run again
./verify.sh
```

---

## 🔴 Issue 6: ConfigMap Shows Old Content After Update

### Symptom
You edited `01-configmap-html.yaml` and reapplied, but Pod still shows old HTML.

### Root Cause
ConfigMaps are mounted at Pod creation time. Changes require Pod restart.

### Fix
```bash
# Update ConfigMap
kubectl apply -f manifests/01-configmap-html.yaml

# Restart Pod to pick up changes
kubectl delete pod web
kubectl apply -f manifests/02-pod-web.yaml

# Or use rollout restart (Day 2 with Deployments)
```

---

## 🔴 Issue 7: Minikube Not Starting (WSL2 on Windows)

### Symptom
```bash
$ minikube start
❌ Exiting due to DRV_NOT_HEALTHY: Found driver(s) but none were healthy.
```

### Common Causes on WSL2

**A) Docker not running**
```bash
# Check Docker
docker ps

# If error, start Docker Desktop (Windows)
# Then in WSL2:
docker ps  # Should work now
```

**B) Minikube using wrong driver**
```bash
# Force Docker driver
minikube start --driver=docker
```

**C) Conflicting Minikube profile**
```bash
# Delete old profile and start fresh
minikube delete
minikube start --driver=docker --kubernetes-version=v1.35.0
```

---

## 🜡 Issue 8: `kubectl apply` Always Shows "configured" (Not "unchanged")

### Symptom
```bash
$ kubectl delete pod web
$ kubectl apply -f manifests/02-pod-web.yaml
pod/web created

$ kubectl apply -f manifests/02-pod-web.yaml
pod/web configured  # Expected "unchanged"

$ kubectl apply -f manifests/02-pod-web.yaml
pod/web configured  # Still "configured"
```

### Is This a Problem?

**No.** This is **expected behavior** with **modern kubectl (v1.28+)** and especially **kubectl v1.35**.

### Root Cause

Starting with Kubernetes 1.22, **Server-Side Apply (SSA)** became the default. SSA:
- Tracks field ownership more granularly
- Updates metadata annotations on every apply
- Reports `configured` when any managed field is touched (even if no spec changes)

**Result:** `configured` is now more common than `unchanged`, even with identical manifests.

**This is especially true in kubectl v1.35.0** (December 2024 release), which further refines SSA behavior.

### Verify It's Not a Real Change

```bash
# 1. Apply manifest
kubectl apply -f manifests/02-pod-web.yaml

# 2. Get current Pod spec hash
BEFORE=$(kubectl get pod web -o jsonpath='{.spec}' | sha256sum)

# 3. Apply again
kubectl apply -f manifests/02-pod-web.yaml
# Output: pod/web configured

# 4. Get Pod spec hash again
AFTER=$(kubectl get pod web -o jsonpath='{.spec}' | sha256sum)

# 5. Compare
echo "Before: $BEFORE"
echo "After:  $AFTER"
# They should be IDENTICAL
```

### Understanding the Messages

| Message | Meaning | Is it OK? |
|---------|---------|-----------|
| `created` | Resource was created | ✅ Yes |
| `unchanged` | Zero changes detected (rare with SSA) | ✅ Yes |
| `configured` | Manifest applied (may update metadata) | ✅ Yes |
| `error` | Failed to apply | ❌ No (investigate) |

### Verify True Idempotency

```bash
# Count Pods before
kubectl get pods | grep web | wc -l
# Output: 1

# Apply again
kubectl apply -f manifests/
# Output: pod/web configured

# Count Pods after
kubectl get pods | grep web | wc -l
# Output: 1 (not 2!) ← This proves idempotency

# Check Pod hasn't changed functionally
kubectl get pod web -o jsonpath='{.spec.containers[0].image}'
# Output: nginx:1.25-alpine (same as manifest)
```

### Force "unchanged" Behavior (Optional)

If you want to see `unchanged` more often, use **client-side apply**:

```bash
kubectl apply -f manifests/02-pod-web.yaml --server-side=false
kubectl apply -f manifests/02-pod-web.yaml --server-side=false
# Output: pod/web unchanged (more likely)
```

**Note:** Client-side apply is the old default (pre-1.22) and may be deprecated in future Kubernetes versions.

### Bottom Line

- ✅ `configured` does **NOT** mean "something broke"
- ✅ Idempotency is about **outcome** (no duplicates), not the message
- ✅ Both `unchanged` and `configured` are success states
- ❌ Only `error` indicates a real problem

**Modern best practice:** Ignore `unchanged` vs `configured` and focus on:
1. Did the resource reach desired state? (`kubectl get`)
2. Is the application healthy? (`kubectl logs`, `curl`)

**References:**
- [Kubernetes Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)
- [kubectl v1.35 Release Notes](https://kubernetes.io/blog/2024/12/17/kubernetes-v1-35-release/)

---

## 🔍 General Troubleshooting Method

### Step 1: Check Resource Status
```bash
kubectl get all
```

### Step 2: Describe Pod for Events
```bash
kubectl describe pod web
```

Look for:
- **Events:** Recent actions and errors
- **Conditions:** Pod readiness status
- **Containers:** Image, ports, mounts

### Step 3: Check Logs
```bash
kubectl logs web
```

For previous container (if restarted):
```bash
kubectl logs web --previous
```

### Step 4: Exec into Pod (if Running)
```bash
kubectl exec -it web -- /bin/sh

# Inside container:
ls -la /usr/share/nginx/html/
cat /usr/share/nginx/html/index.html
exit
```

---

## 📚 Useful Commands

### Quick Status Check
```bash
# All resources in default namespace
kubectl get all

# Specific resource types
kubectl get pods,configmaps
```

### Watch Resources (auto-refresh)
```bash
# Watch Pod status
kubectl get pods -w

# Stop watching: Ctrl+C
```

### Cleanup
```bash
# Delete all Day 1 resources
kubectl delete -f manifests/

# Or individually
kubectl delete pod web
kubectl delete configmap web-html
```

### Full Cluster Reset (if needed)
```bash
minikube delete
minikube start --driver=docker --kubernetes-version=v1.35.0
```

---

## ❓ Still Stuck?

1. **Check YAML syntax:**
   ```bash
   # Validate YAML without applying
   kubectl apply -f manifests/ --dry-run=client
   ```

2. **Compare with repository:**
   - Make sure you're using the correct versions from GitHub
   - Check for typos in your local files

3. **Ask for help:**
   - Open an issue: [GitHub Issues](https://github.com/the-byte-sized/kubernetes-capstone-labs/issues)
   - Include output from:
     ```bash
     kubectl get pods
     kubectl describe pod web
     kubectl logs web
     kubectl version --client -o yaml
     minikube version
     ```

---

**Next:** [Day 2 Troubleshooting](../day-2-replication/troubleshooting.md)
