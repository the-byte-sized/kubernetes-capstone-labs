# Lab 2.1: ReplicaSet - From 1 to N Instances

## 🎯 Goal

Create a ReplicaSet that maintains **3 replicas** of the web Pod, demonstrating:
- Automatic cardinality management
- Self-healing behavior (Pod auto-recreation)
- Label-based selection

**Key learning**: A ReplicaSet continuously reconciles to maintain desired replica count.

---

## 📚 Prerequisites

- ✅ Day 1 completed (Pod basics)
- ✅ Minikube cluster running
- ✅ Namespace `task-tracker` exists
- ✅ Theory: Lezione 2 - Riconciliazione e control loop

**Verify environment:**
```bash
minikube status
kubectl config get-contexts
kubectl config set-context --current --namespace=task-tracker
```

---

## 🧪 Lab Steps

### Step 1: Create ReplicaSet manifest

Create `web-replicaset.yaml` (see file in this directory).

**Key sections to understand:**
- `spec.replicas: 3` → desired state
- `spec.selector.matchLabels` → how ReplicaSet finds its Pods
- `spec.template` → Pod template (identical to Day 1 Pod spec)

### Step 2: Apply ReplicaSet

```bash
kubectl apply -f web-replicaset.yaml
```

**Expected output:**
```
replicaset.apps/web-replicaset created
```

### Step 3: Observe Pod creation

```bash
kubectl get replicaset
kubectl get pods --show-labels
```

**Expected output:**
```
NAME             DESIRED   CURRENT   READY   AGE
web-replicaset   3         3         3       30s

NAME                   READY   STATUS    RESTARTS   AGE   LABELS
web-replicaset-abc12   1/1     Running   0          30s   app=web,tier=frontend
web-replicaset-def34   1/1     Running   0          30s   app=web,tier=frontend
web-replicaset-ghi56   1/1     Running   0          30s   app=web,tier=frontend
```

**Key observation:** All 3 Pods have identical labels matching the selector.

### Step 4: Test self-healing

Delete one Pod manually:

```bash
# Get Pod name
kubectl get pods

# Delete one Pod (replace with actual Pod name)
kubectl delete pod web-replicaset-abc12

# Immediately check Pods
kubectl get pods --watch
```

**Expected behavior:**
1. Pod enters `Terminating` state
2. ReplicaSet detects `current < desired` (2 < 3)
3. ReplicaSet creates a new Pod
4. After few seconds: 3 Pods Running again

**Expected output:**
```
NAME                   READY   STATUS        RESTARTS   AGE
web-replicaset-abc12   1/1     Terminating   0          2m
web-replicaset-def34   1/1     Running       0          2m
web-replicaset-ghi56   1/1     Running       0          2m
web-replicaset-xyz99   0/1     Pending       0          0s    # NEW!
web-replicaset-xyz99   0/1     ContainerCreating   0     1s
web-replicaset-xyz99   1/1     Running             0     3s
```

**Why it works:** ReplicaSet controller runs a reconciliation loop:
- **Observe**: current Pods count
- **Compare**: actual (2) vs desired (3)
- **Act**: create 1 Pod to close the gap

### Step 5: Scale ReplicaSet

Change replica count imperatively (for testing):

```bash
kubectl scale replicaset web-replicaset --replicas=5
```

**Expected output:**
```
replicaset.apps/web-replicaset scaled
```

Verify:
```bash
kubectl get replicaset
kubectl get pods
```

**Expected:**
```
NAME             DESIRED   CURRENT   READY   AGE
web-replicaset   5         5         5       5m

# 5 Pods running
```

Scale back to 3:
```bash
kubectl scale replicaset web-replicaset --replicas=3
kubectl get pods
```

**Expected:** 2 Pods terminate, 3 remain.

### Step 6: Inspect ReplicaSet details

```bash
kubectl describe replicaset web-replicaset
```

**Key sections to observe:**
- **Replicas**: desired, current, ready
- **Selector**: labels used for matching
- **Pods Status**: running/waiting/succeeded/failed
- **Events**: Pod creation/deletion events

**Sample output:**
```
Name:           web-replicaset
Namespace:      task-tracker
Selector:       app=web,tier=frontend
Labels:         app=web
Replicas:       3 current / 3 desired
Pods Status:    3 Running / 0 Waiting / 0 Succeeded / 0 Failed
Events:
  Type    Reason            Age   From                   Message
  ----    ------            ----  ----                   -------
  Normal  SuccessfulCreate  5m    replicaset-controller  Created pod: web-replicaset-abc12
  Normal  SuccessfulCreate  5m    replicaset-controller  Created pod: web-replicaset-def34
  Normal  SuccessfulCreate  5m    replicaset-controller  Created pod: web-replicaset-ghi56
```

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `kubectl get replicaset` shows `DESIRED=3, CURRENT=3, READY=3`
- [ ] `kubectl get pods` shows 3 Pods with `STATUS=Running`
- [ ] All Pods have labels `app=web,tier=frontend`
- [ ] After deleting 1 Pod, a new Pod is auto-created within 5-10 seconds
- [ ] `kubectl describe replicaset` shows recent creation events
- [ ] Scaling to 5 creates 2 new Pods, scaling to 3 removes 2 Pods

**If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts (Lezione 2 References)

### **Reconciliation loop in action:**
```
Observe: current Pods = 2
  ↓
Compare: desired Pods = 3
  ↓
Act: create 1 Pod
  ↓
Observe again... (continuous loop)
```

### **Label-based selection:**
- ReplicaSet doesn't "remember" Pod names
- It continuously queries: "How many Pods match `app=web,tier=frontend`?"
- If count < desired → create
- If count > desired → delete oldest

### **Why ReplicaSet, not bare Pods?**
- **Bare Pod**: if it dies, it's gone (no resurrection)
- **ReplicaSet**: if a Pod dies, controller recreates it
- **Self-healing** is a consequence of continuous reconciliation

---

## 🔗 Theory Mapping

From **Lezione 2**:

| Concept (slide) | Where in lab |
|-----------------|-------------|
| Desired state (`spec`) | `replicas: 3` in YAML |
| Actual state (`status`) | `kubectl get replicaset` → CURRENT column |
| Convergenza | Delete Pod → ReplicaSet recreates |
| Control loop | ReplicaSet controller (runs in control plane) |
| Labels/Selectors | `matchLabels` + Pod template labels |

---

## 🚀 Next Steps

ReplicaSet is a building block, but has a limitation:
- ✅ Maintains cardinality
- ❌ Doesn't manage **versioning** or **rolling updates**

If you change the Pod template (e.g., new image), existing Pods **won't be updated**.

**Solution**: Use a **Deployment** (Lab 2.2) which manages ReplicaSets for you and enables controlled updates.

**Continue to**: [Lab 2.2 - Deployment](../lab-2.2-deployment/README.md)

---

## 📚 Resources

- [Kubernetes ReplicaSet Docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Controller Pattern](https://kubernetes.io/docs/concepts/architecture/controller/)
- Lezione 2: Sezione "Riconciliazione e control loop"
