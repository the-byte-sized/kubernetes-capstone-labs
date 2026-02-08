# Lab 2.2 Troubleshooting Guide

## Common Errors & Solutions

---

### ❌ Error 1: Rollout stuck (never completes)

**Symptom:**
```bash
kubectl rollout status deployment/web-deployment --watch
Waiting for deployment "web-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
# Stuck here for >5 minutes
```

**Diagnosis:**
```bash
kubectl get pods
kubectl describe deployment web-deployment
```

**Cause 1: New Pods not becoming Ready**

```bash
kubectl get pods
NAME                              READY   STATUS             RESTARTS   AGE
web-deployment-new-abc12          0/1     ImagePullBackOff   0          5m
web-deployment-old-xyz99          1/1     Running            0          10m
```

**Solution:**
- Check image name typo: `kubectl describe pod <pod-name>`
- Verify image exists:
  ```bash
  docker pull nginx:1.25-alpine
  ```
- Rollback to working version:
  ```bash
  kubectl rollout undo deployment/web-deployment
  ```

**Cause 2: Readiness probe failing**

```bash
kubectl describe pod web-deployment-new-abc12
Events:
  Warning  Unhealthy  2m  kubelet  Readiness probe failed: Get "http://10.244.0.5:80/": context deadline exceeded
```

**Solution:**
- Increase readiness probe timeouts:
  ```yaml
  readinessProbe:
    httpGet:
      path: /
      port: 80
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5  # Add this
  ```
- Apply and retry:
  ```bash
  kubectl apply -f web-deployment.yaml
  ```

---

### ❌ Error 2: "Deployment has minimum availability" warning

**Symptom:**
```bash
kubectl describe deployment web-deployment
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Progressing    True    NewReplicaSetAvailable
  Available      False   MinimumReplicasUnavailable
```

**Diagnosis:**
```bash
kubectl get pods
```

**Cause:** Too many Pods unavailable during rollout (violates `maxUnavailable`).

**Check strategy:**
```bash
kubectl get deployment web-deployment -o yaml | grep -A3 strategy
```

**Solution:**

Adjust `maxUnavailable` to allow more Pods down:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1     # Absolute number instead of percentage
    maxSurge: 1
```

Or use percentage:
```yaml
maxUnavailable: 50%  # More permissive
```

Apply:
```bash
kubectl apply -f web-deployment.yaml
```

---

### ❌ Error 3: Rollback fails with "no rollout history found"

**Symptom:**
```bash
kubectl rollout undo deployment/web-deployment
error: no rollout history found for deployment "web-deployment"
```

**Cause:** Deployment is too new (no previous revisions).

**Verification:**
```bash
kubectl rollout history deployment/web-deployment
```

**Expected output:**
```
REVISION  CHANGE-CAUSE
1         <none>
```

Only 1 revision = nothing to rollback to.

**Solution:**
- Rollback only works after **at least 2 revisions** exist
- Perform an update first:
  ```bash
  kubectl set image deployment/web-deployment nginx=nginx:1.25-alpine
  kubectl rollout status deployment/web-deployment
  # Now you can rollback
  kubectl rollout undo deployment/web-deployment
  ```

---

### ❌ Error 4: Multiple ReplicaSets all scaled to 0

**Symptom:**
```bash
kubectl get replicaset
NAME                        DESIRED   CURRENT   READY   AGE
web-deployment-7f8c9d5b6f   0         0         0       10m
web-deployment-8a9b0c1d2e   0         0         0       5m

kubectl get pods
No resources found in task-tracker namespace.
```

**Diagnosis:**
```bash
kubectl get deployment web-deployment
```

**Cause 1: Deployment scaled to 0**
```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
web-deployment   0/0     0            0           10m
```

**Solution:**
```bash
kubectl scale deployment web-deployment --replicas=3
```

**Cause 2: Deployment deleted**

**Solution:**
```bash
kubectl apply -f web-deployment.yaml
```

---

### ❌ Error 5: Rollout creates too many Pods (resource exhaustion)

**Symptom:**
```bash
kubectl get pods
NAME                              READY   STATUS    RESTARTS   AGE
web-deployment-new-abc12          0/1     Pending   0          2m
web-deployment-new-def34          0/1     Pending   0          2m
web-deployment-old-xyz99          1/1     Running   0          10m
web-deployment-old-aaa11          1/1     Running   0          10m
web-deployment-old-bbb22          1/1     Running   0          10m
# 5 Pods total, but only 3 desired!
```

**Diagnosis:**
```bash
kubectl describe pod web-deployment-new-abc12
Events:
  Warning  FailedScheduling  2m  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
```

**Cause:** `maxSurge` allows extra Pods, but cluster has insufficient resources.

**Solution 1:** Reduce `maxSurge`:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 0  # No extra Pods during rollout
```

**Solution 2:** Reduce resource requests:
```yaml
resources:
  requests:
    memory: "32Mi"
    cpu: "50m"
```

**Solution 3:** Increase Minikube resources:
```bash
minikube stop
minikube delete
minikube start --cpus=2 --memory=4096
```

---

### ❌ Error 6: Old Pods never terminate during rollout

**Symptom:**
```bash
kubectl get pods
NAME                              READY   STATUS    RESTARTS   AGE
web-deployment-new-abc12          1/1     Running   0          5m
web-deployment-old-xyz99          1/1     Running   0          15m  # Still running!
```

**Both old and new Pods coexist indefinitely.**

**Diagnosis:**
```bash
kubectl describe deployment web-deployment
```

**Cause:** Deployment spec has wrong `replicas` count or label mismatch.

**Check replicas:**
```bash
kubectl get deployment web-deployment -o yaml | grep replicas
```

Expected: `replicas: 3`

If higher (e.g., `replicas: 6`), both old and new Pods stay to reach total.

**Solution:**
```bash
kubectl scale deployment web-deployment --replicas=3
```

**Check labels:**
```bash
kubectl get pods --show-labels
```

Verify old Pods have **same labels** as Deployment selector. If not, they're orphans.

**Solution:**
```bash
kubectl delete pod <old-pod-name>
```

---

## Debugging Workflow for Rollouts

```
1. kubectl rollout status deployment/<name> --watch
   → Is rollout progressing?

2. kubectl get pods
   → Are new Pods Running and Ready?

3. kubectl describe deployment <name>
   → Check Conditions and Events

4. kubectl describe pod <new-pod-name>
   → Why is new Pod not Ready? (image, probe, resources)

5. kubectl rollout history deployment/<name>
   → Check revisions

6. kubectl rollout undo deployment/<name>
   → Rollback if needed
```

**Remember (Lezione 2):**
- **Pending** → scheduler problem (resources)
- **ImagePullBackOff** → wrong image name/tag
- **CrashLoopBackOff** → application issue
- **Running but not Ready** → readiness probe failing
- **Rollout stuck** → new Pods not becoming Ready

---

## Need More Help?

1. Check Deployment events:
   ```bash
   kubectl describe deployment web-deployment
   ```

2. Compare old vs new ReplicaSets:
   ```bash
   kubectl get replicaset -o wide
   kubectl describe replicaset <new-rs-name>
   ```

3. Force delete stuck rollout:
   ```bash
   kubectl rollout undo deployment/web-deployment
   kubectl delete replicaset <stuck-rs-name>
   ```

4. Start fresh:
   ```bash
   kubectl delete deployment web-deployment
   kubectl apply -f web-deployment.yaml
   ```

---

**Back to lab**: [Lab 2.2 README](./README.md)
