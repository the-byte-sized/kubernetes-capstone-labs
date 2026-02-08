# Lab 2.1 Troubleshooting Guide

## Common Errors & Solutions

---

### ❌ Error 1: ReplicaSet created but Pods stuck in Pending

**Symptom:**
```bash
kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
web-replicaset-abc12   0/1     Pending   0          2m
web-replicaset-def34   0/1     Pending   0          2m
web-replicaset-ghi56   0/1     Pending   0          2m
```

**Diagnosis:**
```bash
kubectl describe pod web-replicaset-abc12
```

Look for **Events** section:

**Cause 1: Insufficient resources**
```
Events:
  Warning  FailedScheduling  2m  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
```

**Solution:**
- Reduce resource requests in `web-replicaset.yaml`:
  ```yaml
  resources:
    requests:
      memory: "32Mi"  # Lower than 64Mi
      cpu: "50m"      # Lower than 100m
  ```
- Or increase Minikube resources:
  ```bash
  minikube stop
  minikube delete
  minikube start --cpus=2 --memory=4096
  ```

**Cause 2: Node not Ready**
```bash
kubectl get nodes
NAME       STATUS     ROLES           AGE   VERSION
minikube   NotReady   control-plane   10m   v1.28.3
```

**Solution:**
```bash
minikube status
# If not running:
minikube start
```

---

### ❌ Error 2: ReplicaSet shows 0/3 Pods ready

**Symptom:**
```bash
kubectl get replicaset
NAME             DESIRED   CURRENT   READY   AGE
web-replicaset   3         3         0       5m
```

**Diagnosis:**
```bash
kubectl get pods
kubectl describe pod web-replicaset-abc12
```

**Cause 1: ImagePullBackOff**
```
Events:
  Warning  Failed  2m  kubelet  Failed to pull image "nginx:1.27-alpine": rpc error: ...
```

**Solution:**
- Check image name typo in YAML
- Verify internet connection:
  ```bash
  minikube ssh
  ping google.com
  ```
- Use a known working image:
  ```yaml
  image: nginx:1.25-alpine
  ```

**Cause 2: CrashLoopBackOff**
```
NAME                   READY   STATUS             RESTARTS      AGE
web-replicaset-abc12   0/1     CrashLoopBackOff   5 (2m ago)    5m
```

**Check logs:**
```bash
kubectl logs web-replicaset-abc12
```

**Common cause:** Resource limits too low, container OOM killed.

**Solution:** Increase memory limit:
```yaml
limits:
  memory: "256Mi"  # Increase from 128Mi
```

**Cause 3: Readiness probe failing**
```
Events:
  Warning  Unhealthy  2m  kubelet  Readiness probe failed: Get "http://10.244.0.5:80/": dial tcp 10.244.0.5:80: connect: connection refused
```

**Solution:**
- Increase `initialDelaySeconds` in readinessProbe:
  ```yaml
  readinessProbe:
    httpGet:
      path: /
      port: 80
    initialDelaySeconds: 10  # Increase from 3
  ```

---

### ❌ Error 3: ReplicaSet not recreating deleted Pods

**Symptom:**
```bash
kubectl delete pod web-replicaset-abc12
kubectl get pods
# Only 2 Pods remain, no new Pod created
```

**Diagnosis:**
```bash
kubectl get replicaset -o yaml | grep -A5 selector
```

**Cause: Label mismatch**

ReplicaSet selector:
```yaml
selector:
  matchLabels:
    app: web
    tier: frontend
```

But Pod template labels:
```yaml
template:
  metadata:
    labels:
      app: web
      # Missing: tier: frontend
```

**Solution:**

Ensure **exact match** between selector and template labels:

```yaml
selector:
  matchLabels:
    app: web
    tier: frontend

template:
  metadata:
    labels:
      app: web
      tier: frontend  # Must match!
```

Reapply:
```bash
kubectl delete replicaset web-replicaset
kubectl apply -f web-replicaset.yaml
```

---

### ❌ Error 4: "ReplicaSet has been modified" warning

**Symptom:**
```bash
kubectl apply -f web-replicaset.yaml
Warning: resource replicasets/web-replicaset is missing the kubectl.kubernetes.io/last-applied-configuration annotation
```

**Cause:** ReplicaSet was created imperatively or modified outside kubectl apply.

**Solution:**

Delete and recreate (safe in lab environment):
```bash
kubectl delete replicaset web-replicaset
kubectl apply -f web-replicaset.yaml
```

Or force update:
```bash
kubectl apply -f web-replicaset.yaml --force
```

---

### ❌ Error 5: Pods exist but ReplicaSet shows DESIRED=3, CURRENT=0

**Symptom:**
```bash
kubectl get replicaset
NAME             DESIRED   CURRENT   READY   AGE
web-replicaset   3         0         0       1m

kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
web-replicaset-abc12   1/1     Running   0          10m
```

**Cause:** Orphan Pods (created before ReplicaSet, or labels changed).

**Diagnosis:**
```bash
kubectl get pods --show-labels
```

Check if Pod labels match ReplicaSet selector.

**Solution:**

Delete orphan Pods:
```bash
kubectl delete pod --all
```

ReplicaSet will recreate them with correct labels.

---

## Debugging Workflow

When something doesn't work:

```
1. kubectl get replicaset
   → Check DESIRED vs CURRENT vs READY

2. kubectl get pods
   → Check STATUS (Pending, CrashLoopBackOff, Running?)

3. kubectl describe replicaset <name>
   → Check Events section for creation failures

4. kubectl describe pod <name>
   → Check Events for scheduling, image pull, probe failures

5. kubectl logs <pod-name>
   → Check application logs if container started
```

**Remember (Lezione 2):**
- **Pending** → scheduler problem (resources, taints)
- **ImagePullBackOff** → runtime problem (image name, registry)
- **CrashLoopBackOff** → application problem (OOM, config, probe)
- **Running but not Ready** → readiness probe failing

---

## Need More Help?

If issues persist:

1. Check cluster health:
   ```bash
   minikube status
   kubectl get nodes
   kubectl cluster-info
   ```

2. Restart Minikube:
   ```bash
   minikube stop
   minikube start
   ```

3. Check namespace:
   ```bash
   kubectl config get-contexts
   kubectl config set-context --current --namespace=task-tracker
   ```

4. View ReplicaSet controller logs (advanced):
   ```bash
   kubectl logs -n kube-system -l component=kube-controller-manager
   ```

---

**Back to lab**: [Lab 2.1 README](./README.md)
