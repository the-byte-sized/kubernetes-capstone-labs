# Lab 3.2 Troubleshooting: Ingress Controller Setup

## Issue 1: Ingress addon not enabled

### Symptom

```bash
minikube addons list | grep ingress
```

**Output:**
```
ingress                   disabled
```

Or Ingress resources exist but **no** Pods in `ingress-nginx` namespace.

### Fix

Enable the addon:

```bash
minikube addons enable ingress
```

Wait a few seconds, then verify:

```bash
kubectl get pods -n ingress-nginx
```

**Expected:** At least one `ingress-nginx-controller` Pod in `Running` state.

---

## Issue 2: Controller Pod stuck in Pending

### Symptom

```bash
kubectl get pods -n ingress-nginx
```

**Output:**
```
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-847c8c99d7-abc12   0/1     Pending   0          2m
```

### Root Cause

The Pod cannot be scheduled. Common reasons in Minikube:
- Not enough CPU or memory.
- Node not Ready.

### Fix

1. Check node status:

```bash
kubectl get nodes
```

**If node is NotReady:**
- Restart Minikube:

```bash
minikube stop
minikube start
```

2. If node is Ready but resources are low:

Stop and restart Minikube with more resources:

```bash
minikube stop
minikube start --cpus=4 --memory=8192
```

Wait for controller:

```bash
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=120s
```

**Expected:** Pod becomes `Running` and `Ready`.

3. Inspect Pod events for details:

```bash
kubectl describe pod -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
```

Look under **Events** for messages like `FailedScheduling`, `Insufficient cpu`, `Insufficient memory`.

---

## Issue 3: Controller CrashLoopBackOff

### Symptom

```bash
kubectl get pods -n ingress-nginx
```

**Output:**
```
NAME                                        READY   STATUS             RESTARTS   AGE
ingress-nginx-controller-847c8c99d7-abc12   0/1     CrashLoopBackOff   5          3m
```

### Root Causes

- Image pull failed.
- Misconfigured Minikube networking.
- Incompatible addon state.

### Fix

1. Inspect logs:

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
```

Look for:
- `ImagePullBackOff`
- `CrashLoopBackOff`
- Configuration errors

2. If image pull fails (e.g., no internet):
- Ensure your machine has internet access.
- Restart Minikube after connectivity is restored:

```bash
minikube stop
minikube start
minikube addons enable ingress
```

3. If logs are unclear, try disabling and re-enabling addon:

```bash
minikube addons disable ingress
minikube addons enable ingress
```

Then check again:

```bash
kubectl get pods -n ingress-nginx
```

---

## Issue 4: No IngressClass present

### Symptom

```bash
kubectl get ingressclass
```

**Output:**
```
No resources found in default namespace.
```

Or:
```
Error from server (NotFound): the server could not find the requested resource (get ingressclasses.networking.k8s.io)
```

### Fix

1. Ensure your cluster is recent enough (IngressClass is GA in modern Kubernetes).
2. Verify the addon created an IngressClass:

```bash
kubectl get ingressclass --all-namespaces
```

If still nothing, you can create a basic IngressClass for ingress-nginx:

```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF
```

Verify:

```bash
kubectl get ingressclass
```

**Expected:**
```
NAME    CONTROLLER
nginx   k8s.io/ingress-nginx
```

> In Minikube recent versions, this step is usually not necessary; the addon creates it automatically.

---

## Issue 5: Ingress resources show no address

### Symptom

After enabling the addon and later creating an Ingress (Lab 3.3), you see:

```bash
kubectl get ingress
```

**Output:**
```
NAME          CLASS   HOSTS           ADDRESS   PORTS   AGE
capstone      nginx   capstone.local            80      1m
```

`ADDRESS` column is empty.

### Root Cause

The controller has not yet updated the Ingress status, or the controller is not watching that namespace/class.

### Fix

1. Wait a few seconds and re-check:

```bash
kubectl get ingress
```

2. Ensure controller is Running and Ready:

```bash
kubectl get pods -n ingress-nginx
```

3. Check controller logs for that Ingress:

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') --tail=50
```

Look for entries mentioning your Ingress name.

If controller is healthy and Ingress is correct, the ADDRESS field will usually be populated with the Minikube node IP.

---

## Quick Diagnostic Script

Use this script to quickly validate your Ingress controller setup:

```bash
#!/bin/bash
set -e

echo "=== Step 1: Minikube status ==="
minikube status

echo "\n=== Step 2: Ingress addon status ==="
minikube addons list | grep ingress || true

echo "\n=== Step 3: ingress-nginx namespace ==="
kubectl get ns ingress-nginx || echo "Namespace ingress-nginx not found"

echo "\n=== Step 4: Controller Pods ==="
kubectl get pods -n ingress-nginx || echo "No Pods in ingress-nginx"

echo "\n=== Step 5: IngressClass ==="
kubectl get ingressclass || echo "No IngressClass found"

echo "\n=== Step 6: Controller logs (last 10 lines) ==="
POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  kubectl logs -n ingress-nginx "$POD" --tail=10
else
  echo "No controller Pod found"
fi
```

Save as `ingress-debug.sh`, make executable, and run:

```bash
chmod +x ingress-debug.sh
./ingress-debug.sh
```

This gives you a quick picture of whether the controller is installed, running, and ready.

---

## Additional Resources

- [Minikube Ingress Addon](https://minikube.sigs.k8s.io/docs/handbook/ingress/)
- [Ingress Controllers - Kubernetes Docs](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-controllers)

---

**Back to**: [Lab 3.2 README](./README.md)
