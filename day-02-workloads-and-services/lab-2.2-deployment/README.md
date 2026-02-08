# Lab 2.2: Deployment - Managing Change

## 🎯 Goal

Migrate from ReplicaSet to **Deployment** and perform a **rolling update**, demonstrating:
- Zero-downtime updates
- Versioning and rollback capability
- Observing coexistence of old/new Pods during rollout

**Key learning**: Deployment manages ReplicaSets for you, enabling controlled changes.

---

## 📚 Prerequisites

- ✅ Lab 2.1 completed (ReplicaSet basics)
- ✅ ReplicaSet currently running (3 Pods)
- ✅ Theory: Lezione 2 - Deployment: governare il cambiamento

**Verify current state:**
```bash
kubectl get replicaset
kubectl get pods
```

---

## 🧪 Lab Steps

### Step 1: Clean up ReplicaSet from Lab 2.1

Delete the ReplicaSet (Deployment will manage ReplicaSets for us):

```bash
kubectl delete replicaset web-replicaset
```

**Expected output:**
```
replicaset.apps "web-replicaset" deleted
```

Verify cleanup:
```bash
kubectl get pods
# Should show no Pods (or Pods terminating)
```

### Step 2: Create Deployment manifest

Create `web-deployment.yaml` starting from this skeleton:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  labels:
    app: web
    component: deployment
spec:
  replicas: # TODO: Same as ReplicaSet - how many?
  
  selector:
    matchLabels:
      app: # TODO: Must match template labels
      tier: # TODO: Must match template labels
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  
  template:
    metadata:
      labels:
        app: # TODO: Same as selector
        tier: # TODO: Same as selector
    spec:
      containers:
      - name: nginx
        image: # TODO: nginx:1.27-alpine
        ports:
        - containerPort: # TODO: nginx port
          name: http
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
```

**Fill in the TODOs:**

1. **replicas:** `3` (same as ReplicaSet)
2. **selector.matchLabels:** `app: web` and `tier: frontend`
3. **template.metadata.labels:** MUST match selector (same as Lab 2.1)
4. **image:** `nginx:1.27-alpine`
5. **containerPort:** `80`

**Key difference from ReplicaSet:**
- Deployment has `strategy` field for controlling updates
- `RollingUpdate` means gradual replacement (no downtime)
- `maxUnavailable: 25%` = at most 1 Pod down during update (with 3 replicas)
- `maxSurge: 25%` = at most 4 Pods total during update (3 + 1)

**Helpful commands:**
```bash
kubectl explain deployment.spec.strategy
kubectl explain deployment.spec.strategy.rollingUpdate
```

**Stuck after 10 minutes?** Complete example in `web-deployment.yaml` in this directory.

### Step 3: Apply Deployment

```bash
kubectl apply -f web-deployment.yaml
```

**Expected output:**
```
deployment.apps/web-deployment created
```

### Step 4: Observe Deployment creation

```bash
kubectl get deployment
kubectl get replicaset
kubectl get pods
```

**Expected output:**
```
# Deployment shows rollout status
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
web-deployment   3/3     3            3           30s

# Deployment CREATED a ReplicaSet automatically
NAME                        DESIRED   CURRENT   READY   AGE
web-deployment-7f8c9d5b6f   3         3         3       30s

# Pods managed by the ReplicaSet
NAME                              READY   STATUS    RESTARTS   AGE
web-deployment-7f8c9d5b6f-abc12   1/1     Running   0          30s
web-deployment-7f8c9d5b6f-def34   1/1     Running   0          30s
web-deployment-7f8c9d5b6f-ghi56   1/1     Running   0          30s
```

**Key observation:**
- Deployment name: `web-deployment`
- ReplicaSet name: `web-deployment-<pod-template-hash>` (auto-generated)
- Pod names: `web-deployment-<rs-hash>-<random>`

### Step 5: Check rollout status

```bash
kubectl rollout status deployment/web-deployment
```

**Expected output:**
```
deployment "web-deployment" successfully rolled out
```

### Step 6: Inspect Deployment details

```bash
kubectl describe deployment web-deployment
```

**Key sections:**
```
Replicas:       3 desired | 3 updated | 3 total | 3 available
StrategyType:   RollingUpdate
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Image: nginx:1.27-alpine
Events:
  Normal  ScalingReplicaSet  1m  deployment-controller  Scaled up replica set web-deployment-7f8c9d5b6f to 3
```

### Step 7: Perform Rolling Update

**Change the image** to simulate an application update:

```bash
kubectl set image deployment/web-deployment nginx=nginx:1.25-alpine
```

**Expected output:**
```
deployment.apps/web-deployment image updated
```

**Immediately watch the rollout:**
```bash
kubectl rollout status deployment/web-deployment --watch
```

**Expected output:**
```
Waiting for deployment "web-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 2 old replicas are pending termination...
Waiting for deployment "web-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "web-deployment" successfully rolled out
```

### Step 8: Observe coexistence of old/new Pods

During rollout, open another terminal and watch Pods:

```bash
kubectl get pods --watch
```

**Expected behavior:**
```
NAME                              READY   STATUS              RESTARTS   AGE
web-deployment-7f8c9d5b6f-abc12   1/1     Running             0          5m   # OLD
web-deployment-7f8c9d5b6f-def34   1/1     Running             0          5m   # OLD
web-deployment-7f8c9d5b6f-ghi56   1/1     Running             0          5m   # OLD
web-deployment-8a9b0c1d2e-xyz99   0/1     ContainerCreating   0          2s   # NEW
web-deployment-8a9b0c1d2e-xyz99   1/1     Running             0          5s   # NEW ready
web-deployment-7f8c9d5b6f-abc12   1/1     Terminating         0          5m   # OLD terminating
web-deployment-8a9b0c1d2e-aaa11   0/1     ContainerCreating   0          1s   # NEW
web-deployment-8a9b0c1d2e-aaa11   1/1     Running             0          4s   # NEW ready
web-deployment-7f8c9d5b6f-def34   1/1     Terminating         0          5m   # OLD terminating
...
```

**Key observation:**
- **Old Pods** stay Running until **new Pods** are Ready
- **No downtime**: at least `desired - maxUnavailable` Pods always available
- **Gradual transition**: controlled by `RollingUpdateStrategy`

### Step 9: Verify new ReplicaSet created

```bash
kubectl get replicaset
```

**Expected output:**
```
NAME                        DESIRED   CURRENT   READY   AGE
web-deployment-8a9b0c1d2e   3         3         3       2m   # NEW (active)
web-deployment-7f8c9d5b6f   0         0         0       10m  # OLD (scaled down)
```

**Why 2 ReplicaSets?**
- Deployment **creates a new ReplicaSet** for each template change
- Old ReplicaSet scaled to 0 (but kept for rollback history)
- New ReplicaSet scaled to desired count (3)

### Step 10: Check rollout history

```bash
kubectl rollout history deployment/web-deployment
```

**Expected output:**
```
deployment.apps/web-deployment
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

View details of a revision:
```bash
kubectl rollout history deployment/web-deployment --revision=1
kubectl rollout history deployment/web-deployment --revision=2
```

**Expected:** Shows Pod template differences (image version).

### Step 11: Rollback to previous version

Simulate a failed deployment (rollback scenario):

```bash
kubectl rollout undo deployment/web-deployment
```

**Expected output:**
```
deployment.apps/web-deployment rolled back
```

Verify:
```bash
kubectl rollout status deployment/web-deployment
kubectl describe deployment web-deployment | grep Image
```

**Expected:** Image is back to `nginx:1.27-alpine` (revision 1).

Check ReplicaSets:
```bash
kubectl get replicaset
```

**Expected:**
```
NAME                        DESIRED   CURRENT   READY   AGE
web-deployment-7f8c9d5b6f   3         3         3       15m  # OLD (re-activated)
web-deployment-8a9b0c1d2e   0         0         0       5m   # NEW (scaled down)
```

**Key observation:** Rollback is **instant** because old ReplicaSet still exists.

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `kubectl get deployment` shows `READY=3/3, UP-TO-DATE=3, AVAILABLE=3`
- [ ] `kubectl get replicaset` shows 1 active ReplicaSet (DESIRED=3) + old ones (DESIRED=0)
- [ ] `kubectl get pods` shows 3 Pods with STATUS=Running
- [ ] Rolling update completed without errors (`kubectl rollout status`)
- [ ] During rollout, observed coexistence of old/new Pods
- [ ] `kubectl rollout history` shows at least 2 revisions
- [ ] Rollback worked: `kubectl rollout undo` restored previous image

**If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts (Lezione 2 References)

### **Deployment vs ReplicaSet:**

| Feature | ReplicaSet | Deployment |
|---------|------------|------------|
| Maintains N replicas | ✅ | ✅ |
| Self-healing | ✅ | ✅ |
| Rolling updates | ❌ | ✅ |
| Rollback capability | ❌ | ✅ |
| Versioning | ❌ | ✅ |
| **When to use** | Almost never directly | Default for stateless apps |

### **Rolling Update Strategy:**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 25%  # Max Pods that can be unavailable during update
    maxSurge: 25%        # Max extra Pods created during update
```

**Example with 3 replicas:**
- `maxUnavailable: 25%` → at most 1 Pod down (25% of 3 ≈ 0.75 → rounds to 1)
- `maxSurge: 25%` → at most 4 Pods total during rollout (3 + 1)

**Result:** At least 2 Pods always available (zero downtime).

### **Why multiple ReplicaSets?**

- Each **Pod template change** triggers new ReplicaSet creation
- Old ReplicaSets scaled to 0 but **kept in history** (default: last 10)
- Enables **instant rollback** (just scale old ReplicaSet back up)

### **Reconciliation in Deployment:**

```
User updates image
  ↓
Deployment controller detects template change
  ↓
Creates new ReplicaSet (revision 2)
  ↓
Gradually scales new ReplicaSet up (0 → 3)
Gradually scales old ReplicaSet down (3 → 0)
  ↓
Rolling update complete
```

---

## 🔗 Theory Mapping

From **Lezione 2**:

| Concept (slide) | Where in lab |
|-----------------|-------------|
| Strategia di rollout | `strategy.type: RollingUpdate` in YAML |
| Coesistenza versioni | Watch Pods during `kubectl set image` |
| ReplicaSet multipli | `kubectl get rs` shows old + new |
| Rollback | `kubectl rollout undo` |
| Osservabilità rollout | `kubectl rollout status --watch` |

---

## 🚀 Next Steps

You now have a Deployment managing 3 replicas with rollout capability.

But there's a problem:
- ✅ Pods are running
- ❌ How do we **access** them?
- ❌ Pod IPs are ephemeral (change on recreate/update)

**Solution:** Use a **Service** (Lab 2.3) to provide a **stable endpoint**.

**Continue to**: [Lab 2.3 - Service](../lab-2.3-service/README.md)

---

## 📚 Resources

- [Kubernetes Deployment Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Rolling Update Strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
- [Rollback Guide](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- Lezione 2: Sezione "Deployment: governare il cambiamento"
