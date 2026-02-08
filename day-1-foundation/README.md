# Day 1: Foundation

**Goal:** Understand Kubernetes basics by deploying a single Pod with custom HTML served by nginx.

**KCNA Domains:** Kubernetes Fundamentals (90%), Cloud Native Architecture (10%)

---

## 🎯 Learning Objectives

By the end of Day 1, you will:

1. Understand what a **Pod** is (the smallest deployable unit in Kubernetes)
2. Know how to define resources using **YAML manifests**
3. Use **ConfigMap** to inject configuration into a Pod
4. Apply the **declarative model**: desired state → actual state
5. Use basic `kubectl` commands: `apply`, `get`, `describe`, `logs`, `port-forward`
6. Follow the **troubleshooting method**: get → describe → events → logs

---

## 📚 Key Concepts

### Pod
- **Smallest schedulable unit** in Kubernetes
- Contains one or more containers that share network and storage
- Ephemeral: can be replaced, IP address may change
- Managed by the kubelet on a worker node

### ConfigMap
- Stores **non-sensitive configuration** as key-value pairs
- Can be injected into Pods as:
  - Environment variables
  - Files mounted into containers
- Decouples configuration from container images

### Declarative Model
- You declare **desired state** in YAML manifests
- Kubernetes continuously works to make **actual state** match desired state
- This is called **reconciliation**

### kubectl Commands (Day 1 essentials)
```bash
kubectl apply -f <file>        # Create/update resources
kubectl get pods               # List Pods
kubectl describe pod <name>    # Detailed info + events
kubectl logs <pod>             # Container logs
kubectl port-forward <pod> <local-port>:<pod-port>  # Access Pod locally
kubectl delete pod <name>      # Delete Pod
```

---

## 🛠️ What We're Building

**Architecture (Day 1):**
```
[Your Browser]
       ↓ port-forward
   [Pod: web]
       ↓
   [nginx container]
       ↓
   [HTML from ConfigMap]
```

**Components:**
- **ConfigMap `web-html`**: Contains custom HTML file
- **Pod `web`**: Runs nginx, mounts ConfigMap as `/usr/share/nginx/html/index.html`

**Access method:** `kubectl port-forward` (temporary, for testing)

---

## 🚀 Step-by-Step Guide

### Prerequisites Check
```bash
# Verify Minikube is running
minikube status

# If not running, start it
minikube start

# Verify kubectl connection
kubectl get nodes
# Expected: 1 node in Ready state
```

---

### Step 1: Create ConfigMap with HTML Content

**Navigate to day-1-foundation:**
```bash
cd day-1-foundation/
```

**Apply the ConfigMap** (this one is pre-built for you):
```bash
kubectl apply -f manifests/01-configmap-html.yaml
```

**Expected output:**
```
configmap/web-html created
```

**Verify it exists:**
```bash
kubectl get configmap web-html
```

**Expected:**
```
NAME       DATA   AGE
web-html   1      10s
```

**Optional - Inspect the content:**
```bash
kubectl describe configmap web-html
```

You'll see the HTML content stored under the `index.html` key.

---

### Step 2: Create Pod Manifest

Now create `02-pod-web.yaml` starting from this skeleton:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
    tier: frontend
    day: "1"
spec:
  containers:
  - name: nginx
    image: # TODO: nginx image with Alpine Linux
    ports:
    - containerPort: # TODO: nginx port
      name: http
      protocol: TCP
    volumeMounts:
    - name: html-content
      mountPath: /usr/share/nginx/html
      readOnly: true
    resources:
      requests:
        memory: "32Mi"
        cpu: "50m"
      limits:
        memory: "64Mi"
        cpu: "100m"
  volumes:
  - name: html-content
    configMap:
      name: # TODO: ConfigMap name from Step 1
      items:
      - key: index.html
        path: index.html
```

**Fill in the 3 TODOs:**

1. **image:** We need nginx with Alpine Linux (lightweight version)
   - Go to [Docker Hub nginx page](https://hub.docker.com/_/nginx)
   - Click on "Tags" tab
   - Look for tags with pattern `<version>-alpine`
   - We want version `1.25`
   - Final format: `nginx:1.25-alpine`

2. **containerPort:** What port does nginx listen on by default?
   - Hint: Standard HTTP port is `80`
   - This tells Kubernetes which port the container exposes

3. **configMap.name:** What did we name the ConfigMap in Step 1?
   ```bash
   # Check existing ConfigMaps
   kubectl get configmap
   # Look for the one we just created (it's called "web-html")
   ```

**Understanding the structure:**
- `volumeMounts`: Tells the container where to mount the ConfigMap content
- `volumes`: Defines the ConfigMap as a volume source
- `mountPath: /usr/share/nginx/html`: nginx's default web root directory

**Helpful commands to explore:**
```bash
# Learn Pod structure
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.image
kubectl explain pod.spec.volumes.configMap

# Example: See what the 'image' field expects
kubectl explain pod.spec.containers.image
```

**Stuck after 10 minutes?** A complete working example is available in `manifests/02-pod-web.yaml` in this directory.

---

### Step 3: Apply Pod Manifest

```bash
# Apply your Pod manifest
kubectl apply -f 02-pod-web.yaml
```

**Expected output:**
```
pod/web created
```

---

### Step 4: Verify Pod is Running

```bash
# Check Pod status
kubectl get pods
```

**Expected output:**
```
NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          10s
```

**What to look for:**
- `READY: 1/1` → 1 container ready out of 1 total
- `STATUS: Running` → Pod is executing
- If status is `Pending`, `ContainerCreating`, or `ImagePullBackOff`, see [Troubleshooting](#troubleshooting)

---

### Step 5: Inspect Pod Details

```bash
# Get detailed information
kubectl describe pod web
```

**Key sections to review:**
1. **Labels**: `app=web` (used for selection later)
2. **Containers**: Image, ports, mounts
3. **Volumes**: ConfigMap reference
4. **Events**: Shows what Kubernetes did (pulled image, started container, etc.)

**Events example:**
```
Events:
  Type    Reason     Age   Message
  ----    ------     ----  -------
  Normal  Scheduled  30s   Successfully assigned default/web to minikube
  Normal  Pulling    29s   Pulling image "nginx:1.25-alpine"
  Normal  Pulled     25s   Successfully pulled image
  Normal  Created    25s   Created container nginx
  Normal  Started    24s   Started container nginx
```

---

### Step 6: Access the Application

**Method 1: Port-forward (recommended for Day 1)**
```bash
# Forward local port 8080 to Pod port 80
kubectl port-forward pod/web 8080:80
```

**Expected output:**
```
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

**Open browser:** [http://localhost:8080](http://localhost:8080)

**Expected:** HTML page with "Welcome to Task Tracker - Day 1: Foundation"

**To stop port-forward:** Press `Ctrl+C`

---

**Method 2: Check logs**
```bash
# View nginx access logs
kubectl logs web
```

After accessing via browser, you should see:
```
127.0.0.1 - - [08/Feb/2026:11:30:00 +0000] "GET / HTTP/1.1" 200 ...
```

---

### Step 7: Run Automated Verification

```bash
# Make script executable (first time only)
chmod +x verify.sh

# Run verification
./verify.sh
```

**Expected output:**
```
=== Day 1 Verification ===
[1/3] Checking Pod status...
✅ Pod Running
[2/3] Checking ConfigMap...
✅ ConfigMap exists
[3/3] Checking HTML content...
✅ HTML content correct

🎉 Day 1 verification PASSED!
```

---

## 🔎 Observation Exercises

### Exercise 1: Understand Desired vs Actual State

```bash
# View the spec (desired state)
kubectl get pod web -o yaml | grep -A 10 "spec:"

# View the status (actual state)
kubectl get pod web -o yaml | grep -A 20 "status:"
```

**Question:** What's the difference between `spec` and `status`?

<details>
<summary><strong>💡 Click to reveal answer</strong></summary>

<br>

**Answer:** 
- `spec` = what you **asked for** (desired state)
- `status` = what Kubernetes **achieved** (actual state)

**Why this matters:**
- The API server stores both `spec` and `status`
- Controllers continuously work to make `status` match `spec`
- This is the core of Kubernetes' **reconciliation loop**
- When troubleshooting, you compare desired vs actual to find where convergence failed

</details>

---

### Exercise 2: Understand Idempotency

```bash
# Apply the same manifests again
kubectl apply -f manifests/01-configmap-html.yaml
kubectl apply -f 02-pod-web.yaml
```

**You will likely see:**
```
configmap/web-html unchanged
pod/web configured
```

**⚠️ Important Note:** Modern kubectl (v1.28+, especially v1.35) often shows `configured` even when no functional changes occur. This is due to **Server-Side Apply (SSA)** tracking metadata more strictly.

**What idempotency really means:**

Idempotency is about **outcome**, not the message kubectl prints:

1. ✅ **No duplicates created** (still 1 Pod named "web", not 2 or 3)
2. ✅ **Same functional state** (Pod spec unchanged)
3. ✅ **Safe to reapply** (no errors, no data loss)

**Verify true idempotency:**

```bash
# Count Pods before
kubectl get pods | grep web | wc -l
# Output: 1

# Apply again
kubectl apply -f 02-pod-web.yaml

# Count Pods after
kubectl get pods | grep web | wc -l
# Output: 1 (not 2!) ← This proves idempotency

# Verify Pod spec unchanged
kubectl get pod web -o jsonpath='{.spec.containers[0].image}'
# Output: nginx:1.25-alpine (same as manifest)
```

**Question:** Why does kubectl say "configured" instead of "unchanged"?

<details>
<summary><strong>💡 Click to reveal answer</strong></summary>

<br>

**Answer:** Server-Side Apply (SSA) in Kubernetes 1.22+ is more conservative. It reports `configured` when:
- Metadata annotations are updated (even system-managed ones like `last-applied-configuration`)
- Field managers are reconciled (SSA tracks which tool manages which field)
- Default values are explicitly set by the API server

**This does NOT mean the Pod was modified functionally.**

**Key insight:** kubectl v1.35 (and v1.28+) prioritizes **correctness** over cosmetic messages. It will say `configured` even when the only change is metadata that doesn't affect the Pod's behavior.

**For production:** Both `unchanged` and `configured` are success states. Only `error` indicates a problem.

**Further reading:** [Kubernetes Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)

</details>

---

### Exercise 3: Delete and Observe Reconciliation (Preview)

```bash
# Delete the Pod
kubectl delete pod web

# Check status
kubectl get pods
```

**Expected:** Pod is gone (because we created a "naked Pod" without a controller)

**Question:** What would happen if this Pod was managed by a Deployment?

<details>
<summary><strong>💡 Click to reveal answer</strong></summary>

<br>

**Answer:** Kubernetes would **automatically recreate** it within seconds.

**Why?** 
- **Deployment** → **ReplicaSet** → **Pod** (ownership chain)
- The ReplicaSet controller constantly watches the number of running Pods
- When `actual replicas < desired replicas`, it creates new Pods
- This is **self-healing** — one of Kubernetes' core features

**What you'd see:**
```bash
kubectl delete pod web
# Pod deleted

kubectl get pods
# NAME                   READY   STATUS    AGE
# web-xxxxxxxxx-yyyyy    1/1     Running   3s  ← New Pod, different name
```

**You'll experience this firsthand in Day 2** when we introduce Deployments and test self-healing by intentionally deleting Pods.

**Key concept:** "Naked Pods" (Pods without controllers) don't get recreated. Always use **Deployments** in production for resilience.

</details>

---

## ⚠️ Troubleshooting

See detailed troubleshooting guide: [troubleshooting.md](troubleshooting.md)

### Quick Diagnosis

**Pod stuck in `Pending`:**
```bash
kubectl describe pod web | grep -A 5 Events
```
Look for: `FailedScheduling`, resource constraints, or node issues.

**Pod stuck in `ImagePullBackOff`:**
```bash
kubectl describe pod web | grep -i image
```
Check: Image name, tag, network connectivity.

**Pod `Running` but page not loading:**
```bash
# Check logs
kubectl logs web

# Verify port-forward is active
kubectl port-forward pod/web 8080:80
```

---

## ✅ Definition of Done

You've completed Day 1 when:

1. ✅ ConfigMap `web-html` exists: `kubectl get configmap web-html`
2. ✅ Pod `web` is Running: `kubectl get pod web`
3. ✅ HTML is accessible via `kubectl port-forward pod/web 8080:80` → [http://localhost:8080](http://localhost:8080)
4. ✅ You can explain: Pod, ConfigMap, desired state, actual state, idempotency
5. ✅ Verification script passes: `./verify.sh`

---

## 📚 Further Reading

- [Kubernetes Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Declarative Management](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
- [Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)

---

## ➡️ Next: Day 2 - Workloads and Services

**Preview:** Tomorrow we'll move from a single Pod to a **Deployment** with 3 replicas, add a **Service** for stable networking, and see Kubernetes **self-healing** in action.

```bash
cd ../day-02-workloads-and-services/
cat README.md
```

---

**Questions?** Open an issue or check the [global troubleshooting guide](../docs/troubleshooting.md).
