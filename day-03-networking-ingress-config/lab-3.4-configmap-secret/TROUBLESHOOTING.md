# Lab 3.4 Troubleshooting: ConfigMap & Secret

## Issue 1: ConfigMap not found

### Symptom

Pod events show:

```bash
kubectl describe pod <web-pod>
```

**Events:**
```
Warning  FailedMount  ...  configmap "web-config" not found
```

### Root Causes & Fixes

#### Cause 1.1: ConfigMap not created

**Verify:**

```bash
kubectl get configmap web-config
```

**If output:**
```
Error from server (NotFound): configmaps "web-config" not found
```

**Fix:**

Apply manifest:

```bash
kubectl apply -f web-config.yaml
kubectl get configmap web-config
```

---

#### Cause 1.2: Wrong namespace

**Verify:**

```bash
kubectl get configmap --all-namespaces | grep web-config || echo "Not found"
```

If ConfigMap exists in a different namespace (e.g., `capstone`), but Deployment is in `default`, Kubernetes cannot mount it.

**Fix:**

Create ConfigMap in the same namespace as the Deployment, or move Deployment to the correct namespace.

**Example:**

```bash
kubectl -n capstone get configmap web-config
# If Deployments live in capstone, always use -n capstone
```

---

## Issue 2: ConfigMap mounted but file missing or empty

### Symptom

```bash
kubectl exec <web-pod> -- ls /etc/web-config
# Empty or key missing
```

### Root Causes & Fixes

#### Cause 2.1: Key name mismatch

**Verify:**

```bash
kubectl get configmap web-config -o yaml
```

**Expected:**

```yaml
data:
  message: "Capstone Day 3 - ConfigMap OK"
```

If your volumeMount expects a different key (e.g., via `items` or `subPath`), mismatches produce missing files.

**Fix:**

Align key names between ConfigMap and volume configuration.

Example – mount a specific key as file `config.txt`:

```yaml
volumes:
- name: web-config-volume
  configMap:
    name: web-config
    items:
    - key: message
      path: config.txt

volumeMounts:
- name: web-config-volume
  mountPath: /etc/web-config
```

Verify:

```bash
kubectl exec <web-pod> -- ls /etc/web-config
kubectl exec <web-pod> -- cat /etc/web-config/config.txt
```

---

#### Cause 2.2: Using subPath incorrectly

If you use `subPath` to mount a single file, misconfiguration can lead to empty or missing files.

**Example fix:**

```yaml
volumeMounts:
- name: web-config-volume
  mountPath: /etc/web-config/message
  subPath: message
```

This mounts only the `message` key at `/etc/web-config/message`.

---

## Issue 3: Secret not found

### Symptom

```bash
kubectl describe pod <api-pod>
```

**Events:**
```
Warning  Failed     Error: secret "api-secret" not found
``` 

### Root Causes & Fixes

#### Cause 3.1: Secret not created

**Verify:**

```bash
kubectl get secret api-secret
```

**If NotFound:**

**Fix:**

Apply Secret manifest:

```bash
kubectl apply -f api-secret.yaml
kubectl get secret api-secret
```

---

#### Cause 3.2: Typo in secret name

**Verify in Deployment:**

```bash
kubectl get deployment api-deployment -o yaml | grep -A3 API_TOKEN
```

**Fix:**

Ensure `name: api-secret` in `secretKeyRef` matches actual Secret name.

Apply updated Deployment:

```bash
kubectl apply -f api-deployment-with-secret.yaml
kubectl rollout status deployment api-deployment
```

---

## Issue 4: Env var from Secret is empty or missing

### Symptom

```bash
kubectl exec <api-pod> -- printenv | grep API_TOKEN
# No output
```

### Root Causes & Fixes

#### Cause 4.1: Wrong key in secretKeyRef

**Verify Secret keys:**

```bash
kubectl get secret api-secret -o yaml
```

**Expected:**

```yaml
data:
  API_TOKEN: <base64-encoded>
```

**Verify Deployment env:**

```bash
kubectl get deployment api-deployment -o yaml | grep -A4 API_TOKEN
```

**Fix:**

Ensure `key: API_TOKEN` matches the key in Secret data.

Apply Deployment and wait for rollout:

```bash
kubectl apply -f api-deployment-with-secret.yaml
kubectl rollout status deployment api-deployment
```

Then re-check:

```bash
kubectl exec <api-pod> -- printenv | grep API_TOKEN
```

---

#### Cause 4.2: Pod not restarted after Secret change

Env vars are injected at container startup. If you changed the Secret **after** Pods were created, existing Pods keep old values.

**Fix:**

Trigger a rollout:

```bash
kubectl rollout restart deployment api-deployment
kubectl rollout status deployment api-deployment
```

Then check env again:

```bash
kubectl exec <api-pod> -- printenv | grep API_TOKEN
```

---

## Issue 5: Pod in CreateContainerConfigError

### Symptom

```bash
kubectl get pods -l app=api
```

**Output:**
```
NAME                              READY   STATUS                       RESTARTS   AGE
api-deployment-...                0/1     CreateContainerConfigError   0          10s
```

### Root Cause

Configuration problem (often Secret/ConfigMap reference).

### Fix

Describe Pod:

```bash
kubectl describe pod <api-pod>
```

Look at Events:

- Secret not found.
- Key not found.
- Volume reference invalid.

Fix underlying reference (name/key), re-apply Deployment, and wait for rollout.

---

## Issue 6: Config updated but app behavior unchanged

### Symptom

You modify ConfigMap or Secret, but the application still shows old behavior.

### Explanation

- For **env var** consumption, Pods must be restarted.
- For **volume-mounted** files, app must re-read the file.

### Fix

1. For env vars:

```bash
kubectl rollout restart deployment api-deployment
kubectl rollout status deployment api-deployment
```

2. For files:
- Confirm file content updated:

```bash
kubectl exec <web-pod> -- cat /etc/web-config/message
```

- Ensure the application actually reads the file again (some apps load config only at startup).

---

## Quick Diagnostic Checklist

Use this sequence when config "does not work":

```bash
# 1. Objects exist?
kubectl get configmap web-config
kubectl get secret api-secret

# 2. Correct namespace?
kubectl get configmap,secret --all-namespaces | egrep 'web-config|api-secret'

# 3. Deployment references correct names/keys?
kubectl get deployment web-deployment -o yaml | grep -A5 web-config
kubectl get deployment api-deployment -o yaml | grep -A5 API_TOKEN

# 4. Pod has volumes/env as expected?
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $WEB_POD | grep -A10 "Volumes"
kubectl describe pod $API_POD | grep -A10 "Environment"

# 5. Files/env visible inside container?
kubectl exec $WEB_POD -- ls -l /etc/web-config
kubectl exec $WEB_POD -- cat /etc/web-config/message
kubectl exec $API_POD -- printenv | grep API_TOKEN

# 6. Recent Events?
kubectl describe pod $WEB_POD | grep -A10 "Events"
kubectl describe pod $API_POD | grep -A10 "Events"
```

---

## Additional Resources

- [Configure Pods Using ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)

---

**Back to**: [Lab 3.4 README](./README.md)
