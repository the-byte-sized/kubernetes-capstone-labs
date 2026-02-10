# Day 4 Troubleshooting Guide

## How to Use This Guide

1. Identify your symptom in the table of contents below
2. Follow the diagnostic steps
3. Apply the fix
4. Verify with the suggested command

---

## Table of Contents

**Storage Issues:**
- [PVC Pending (won't bind)](#pvc-pending-wont-bind)
- [Postgres CrashLoopBackOff](#postgres-crashloopbackoff)
- [Data lost after Pod restart](#data-lost-after-pod-restart)

**API Issues:**
- [API returns 500 Internal Server Error](#api-returns-500-internal-server-error)
- [API returns 404 Not Found](#api-returns-404-not-found)
- [API CrashLoopBackOff](#api-crashloopbackoff)

**RBAC Issues:**
- [403 on allowed action](#403-on-allowed-action)
- [can-i says "yes" but command fails](#can-i-says-yes-but-command-fails)
- [ServiceAccount not working](#serviceaccount-not-working)

**Network Issues:**
- [Ingress returns 404](#ingress-returns-404)

---

## Storage Issues

### PVC Pending (won't bind)

**Symptom:** `kubectl get pvc` shows STATUS = Pending for > 1 minute

**Diagnosis:**
```bash
kubectl describe pvc postgres-pvc -n capstone
# Read the Events section at the bottom
```

#### Cause 1: No StorageClass

**Events show:** `no storageclass with name "" found` or similar

**Check:**
```bash
kubectl get sc
# If empty or no (default) marker, you need to specify storageClassName
```

**Fix:**
```bash
# Edit the PVC manifest
nano manifests/02-pvc-postgres.yaml

# Add or uncomment this line in spec:
spec:
  storageClassName: standard  # Use the name from 'kubectl get sc'
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

# Reapply
kubectl delete pvc postgres-pvc -n capstone
kubectl apply -f manifests/02-pvc-postgres.yaml

# Verify
kubectl get pvc -n capstone -w
```

#### Cause 2: Waiting for first consumer

**Events show:** `waiting for first consumer to be created before binding`

**This is normal!** Some StorageClasses use `WaitForFirstConsumer` volume binding mode.

**Fix:** Just deploy the Postgres Pod:
```bash
kubectl apply -f manifests/03-deployment-postgres.yaml
# PVC will automatically bind when Pod is scheduled
```

#### Cause 3: Insufficient resources

**Events show:** `no persistent volumes available for this claim`

**Fix:** Enable dynamic provisioning or create PV manually:
```bash
# Check if storage provisioner is enabled in Minikube
minikube addons list | grep storage-provisioner
# Should show: storage-provisioner: enabled

# If disabled, enable it:
minikube addons enable storage-provisioner

# Delete and recreate PVC
kubectl delete pvc postgres-pvc -n capstone
kubectl apply -f manifests/02-pvc-postgres.yaml
```

---

### Postgres CrashLoopBackOff

**Symptom:** `kubectl get pods` shows Postgres in CrashLoopBackOff

**Diagnosis:**
```bash
kubectl logs -n capstone -l app=postgres --tail=50
kubectl describe pod -n capstone -l app=postgres
```

#### Cause 1: PVC not bound

**Logs show:** `permission denied` or `cannot mount volume`

**Fix:** Check PVC status:
```bash
kubectl get pvc -n capstone
# STATUS must be Bound before Pod can start

# If Pending, see "PVC Pending" section above
```

#### Cause 2: Secret not found

**Logs show:** `environment variable POSTGRES_PASSWORD is not set`

**Fix:**
```bash
# Check Secret exists
kubectl get secret postgres-secret -n capstone

# If not found, create it:
kubectl apply -f manifests/01-secret-postgres.yaml

# Restart Postgres
kubectl rollout restart deploy postgres -n capstone
```

#### Cause 3: Data directory corruption

**Logs show:** `database files are incompatible with server`

**Fix:** Delete PVC and start fresh (WARNING: loses data):
```bash
kubectl delete deploy postgres -n capstone
kubectl delete pvc postgres-pvc -n capstone
kubectl apply -f manifests/02-pvc-postgres.yaml
kubectl apply -f manifests/03-deployment-postgres.yaml
```

---

### Data lost after Pod restart

**Symptom:** Tasks disappear after `kubectl delete pod`

#### Cause 1: PVC was deleted

**Check:**
```bash
kubectl get pvc -n capstone
# postgres-pvc must exist
```

**Prevention:** Never delete PVC unless you want to lose data

#### Cause 2: Using emptyDir instead of PVC

**Check Deployment:**
```bash
kubectl get deploy postgres -n capstone -o yaml | grep -A5 volumes:
# Should show persistentVolumeClaim, not emptyDir
```

**Fix:** Ensure Deployment uses PVC (see manifest 03-deployment-postgres.yaml)

---

## API Issues

### API returns 500 Internal Server Error

**Symptom:** `curl http://capstone.local/api/tasks` returns 500

**Diagnosis:**
```bash
kubectl logs -n capstone -l app=api --tail=50
```

#### Cause 1: Cannot connect to database

**Logs show:** `could not connect to server` or `connection refused`

**Possible fixes:**

**A) Wrong DB_HOST in Secret:**
```bash
# Check Secret
kubectl get secret postgres-secret -n capstone -o jsonpath='{.data.DB_HOST}' | base64 -d
# Expected: postgres-service

# If wrong, edit Secret:
kubectl edit secret postgres-secret -n capstone
# Change DB_HOST to: postgres-service

# Restart API
kubectl rollout restart deploy api -n capstone
```

**B) Postgres Service not created:**
```bash
kubectl get svc postgres-service -n capstone
kubectl get endpoints postgres-service -n capstone
# Endpoints should show an IP address

# If Service missing:
kubectl apply -f manifests/04-service-postgres.yaml
```

**C) Postgres not ready:**
```bash
kubectl get pods -n capstone -l app=postgres
# Must show READY 1/1, STATUS Running

# Check Postgres logs:
kubectl logs -n capstone -l app=postgres
```

#### Cause 2: Wrong Secret keys

**Logs show:** `KeyError: 'POSTGRES_PASSWORD'` or similar

**Fix:** Check Secret has all required keys:
```bash
kubectl get secret postgres-secret -n capstone -o jsonpath='{.data}' | jq
# Must have: DB_HOST, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB

# If keys missing, reapply Secret:
kubectl apply -f manifests/01-secret-postgres.yaml
kubectl rollout restart deploy api -n capstone
```

---

### API returns 404 Not Found

**Symptom:** `curl http://capstone.local/api/tasks` returns 404

**Diagnosis:**
```bash
kubectl get ingress -n capstone
kubectl describe ingress capstone-ingress -n capstone
```

#### Cause: Service selector mismatch

**Check Service selector matches Pod labels:**
```bash
# Check Service selector
kubectl get svc api-service -n capstone -o yaml | grep selector -A2

# Check Pod labels
kubectl get pods -n capstone -l app=api --show-labels

# Selector must match Pod labels (app=api)
```

**Fix:**
```bash
# If mismatch, edit Service:
kubectl edit svc api-service -n capstone
# Ensure selector has: app: api

# Or reapply:
kubectl apply -f manifests/06-service-api.yaml
```

#### Cause: Endpoints empty

**Check:**
```bash
kubectl get endpoints api-service -n capstone
# Should show IP addresses

# If empty, Pod is not Ready or selector is wrong
kubectl get pods -n capstone -l app=api
```

---

### API CrashLoopBackOff

**Symptom:** API Pod keeps restarting

**Diagnosis:**
```bash
kubectl logs -n capstone -l app=api --tail=50
kubectl describe pod -n capstone -l app=api
```

#### Cause: Image pull error

**Events show:** `Failed to pull image` or `ImagePullBackOff`

**Fix:**
```bash
# Check image name in Deployment
kubectl get deploy api -n capstone -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: ghcr.io/the-byte-sized/task-api:v1.0

# If wrong, edit:
kubectl edit deploy api -n capstone
```

#### Cause: Secret not found

**Logs show:** `Secret "postgres-secret" not found`

**Fix:**
```bash
kubectl apply -f manifests/01-secret-postgres.yaml
kubectl rollout restart deploy api -n capstone
```

---

## RBAC Issues

### 403 on allowed action

**Symptom:** `kubectl auth can-i get pods` says "yes" but actual command gets 403

**Diagnosis:**
```bash
kubectl describe rolebinding readonly-binding -n capstone
```

#### Cause 1: Wrong namespace in RoleBinding

**RoleBinding is in different namespace than target resources**

**Check:**
```bash
kubectl get rolebinding -A | grep readonly
# Ensure it's in "capstone" namespace
```

**Fix:**
```bash
# Reapply RBAC manifest:
kubectl delete rolebinding readonly-binding -n capstone
kubectl apply -f manifests/07-rbac-readonly.yaml
```

#### Cause 2: Wrong subject

**RoleBinding points to wrong ServiceAccount**

**Check:**
```bash
kubectl describe rolebinding readonly-binding -n capstone
# Check "Subjects" section matches:
# Kind: ServiceAccount
# Name: readonly-sa
# Namespace: capstone
```

**Fix:** Edit RoleBinding:
```bash
kubectl edit rolebinding readonly-binding -n capstone
```

---

### can-i says "yes" but command fails

**Symptom:** `can-i` returns yes, but actual kubectl command fails

#### Cause: Resource doesn't exist (404 vs 403)

**403** = RBAC denied (permission issue)  
**404** = Resource not found (doesn't exist)

**Check:**
```bash
# Verify resource exists first
kubectl get pods -n capstone

# Then try action as ServiceAccount
kubectl get pods -n capstone --as=system:serviceaccount:capstone:readonly-sa
```

---

### ServiceAccount not working

**Symptom:** Pod can't access Kubernetes API despite having ServiceAccount

#### Cause: ServiceAccount not mounted

**Check Pod spec:**
```bash
kubectl get pod <pod-name> -n capstone -o yaml | grep serviceAccountName
# Should show: serviceAccountName: readonly-sa
```

**Fix:** Add to Pod spec in Deployment:
```yaml
spec:
  serviceAccountName: readonly-sa
  containers:
  - name: ...
```

---

## Network Issues

### Ingress returns 404

**Symptom:** `curl http://capstone.local/api/tasks` returns 404

**Diagnosis:**
```bash
kubectl get ingress -n capstone
kubectl describe ingress capstone-ingress -n capstone
```

#### Cause: Path not matching

**Check Ingress rules:**
```bash
kubectl get ingress capstone-ingress -n capstone -o yaml
# Look for path: /api
# Ensure pathType: Prefix
```

#### Cause: Backend Service wrong

**Check Ingress backend:**
```bash
kubectl describe ingress capstone-ingress -n capstone
# Backend should point to: api-service:80
```

**Fix:**
```bash
# If Day 3 Ingress points to old httpbin, update it:
kubectl edit ingress capstone-ingress -n capstone
# Or reapply Day 3 Ingress (should already point to api-service)
```

---

## Quick Reference: Diagnostic Commands

```bash
# Storage
kubectl get pvc,pv,sc -n capstone
kubectl describe pvc postgres-pvc -n capstone

# Pods
kubectl get pods -n capstone
kubectl describe pod <name> -n capstone
kubectl logs -n capstone <pod-name>
kubectl logs -n capstone <pod-name> --previous  # Previous crash logs

# Services and connectivity
kubectl get svc,endpoints -n capstone
kubectl describe svc <name> -n capstone

# RBAC
kubectl get sa,role,rolebinding -n capstone
kubectl describe rolebinding <name> -n capstone
kubectl auth can-i <verb> <resource> -n capstone --as=system:serviceaccount:<ns>:<sa>

# Secrets
kubectl get secret <name> -n capstone
kubectl describe secret <name> -n capstone
kubectl get secret <name> -n capstone -o jsonpath='{.data}' | jq

# Events (recent)
kubectl get events -n capstone --sort-by='.lastTimestamp' | tail -20

# Ingress
kubectl get ingress -n capstone
kubectl describe ingress <name> -n capstone
```

---

## Still Stuck?

1. **Run verification:** `./verify.sh` to see which check fails
2. **Check Events:** `kubectl get events -n capstone --sort-by='.lastTimestamp'`
3. **Review manifests:** Compare your files with originals in repo
4. **Fresh start:** Delete namespace and start from Day 3:
   ```bash
   kubectl delete namespace capstone
   kubectl create namespace capstone
   # Reapply Day 3 first, then Day 4
   ```

---

## External Resources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [PVC Troubleshooting](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#troubleshooting)
- [RBAC Troubleshooting](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#troubleshooting)
- [Minikube Docs](https://minikube.sigs.k8s.io/docs/)
