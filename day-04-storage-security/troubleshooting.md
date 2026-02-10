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

**Frontend Issues:**
- [Frontend Pod not starting](#frontend-pod-not-starting)
- [Browser shows "Cannot connect to API"](#browser-shows-cannot-connect-to-api)
- [Port-forward "address already in use"](#port-forward-address-already-in-use)
- [Page loads but is blank](#page-loads-but-is-blank)
- [Tasks don't appear after adding](#tasks-dont-appear-after-adding)

**RBAC Issues:**
- [403 on allowed action](#403-on-allowed-action)
- [can-i says "yes" but command fails](#can-i-says-yes-but-command-fails)
- [ServiceAccount not working](#serviceaccount-not-working)

---

## Storage Issues

### PVC Pending (won't bind)

**Symptom:** `kubectl get pvc` shows STATUS = Pending for > 1 minute

**Diagnosis:**
```bash
kubectl describe pvc postgres-pvc
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
kubectl delete pvc postgres-pvc
kubectl apply -f manifests/02-pvc-postgres.yaml

# Verify
kubectl get pvc -w
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
kubectl delete pvc postgres-pvc
kubectl apply -f manifests/02-pvc-postgres.yaml
```

---

### Postgres CrashLoopBackOff

**Symptom:** `kubectl get pods` shows Postgres in CrashLoopBackOff

**Diagnosis:**
```bash
kubectl logs -l app=database --tail=50
kubectl describe pod -l app=database
```

#### Cause 1: PVC not bound

**Logs show:** `permission denied` or `cannot mount volume`

**Fix:** Check PVC status:
```bash
kubectl get pvc
# STATUS must be Bound before Pod can start

# If Pending, see "PVC Pending" section above
```

#### Cause 2: Secret not found

**Logs show:** `environment variable POSTGRES_PASSWORD is not set`

**Fix:**
```bash
# Check Secret exists
kubectl get secret postgres-secret

# If not found, create it:
kubectl apply -f manifests/01-secret-postgres.yaml

# Restart Postgres
kubectl rollout restart deploy postgres
```

#### Cause 3: Data directory corruption

**Logs show:** `database files are incompatible with server`

**Fix:** Delete PVC and start fresh (WARNING: loses data):
```bash
kubectl delete deploy postgres
kubectl delete pvc postgres-pvc
kubectl apply -f manifests/02-pvc-postgres.yaml
kubectl apply -f manifests/03-deployment-postgres.yaml
```

---

### Data lost after Pod restart

**Symptom:** Tasks disappear after `kubectl delete pod`

#### Cause 1: PVC was deleted

**Check:**
```bash
kubectl get pvc
# postgres-pvc must exist
```

**Prevention:** Never delete PVC unless you want to lose data

#### Cause 2: Using emptyDir instead of PVC

**Check Deployment:**
```bash
kubectl get deploy postgres -o yaml | grep -A5 volumes:
# Should show persistentVolumeClaim, not emptyDir
```

**Fix:** Ensure Deployment uses PVC (see manifest 03-deployment-postgres.yaml)

---

## API Issues

### API returns 500 Internal Server Error

**Symptom:** `curl http://localhost:8080/api/tasks` returns 500 (via port-forward)

**Diagnosis:**
```bash
kubectl logs -l app=api --tail=50
```

#### Cause 1: Cannot connect to database

**Logs show:** `could not connect to server` or `connection refused`

**Possible fixes:**

**A) Postgres not ready:**
```bash
kubectl get pods -l app=database
# Must show READY 1/1, STATUS Running

# Check Postgres logs:
kubectl logs -l app=database
```

**B) Postgres Service not created:**
```bash
kubectl get svc postgres-service
kubectl get endpoints postgres-service
# Endpoints should show an IP address

# If Service missing:
kubectl apply -f manifests/04-service-postgres.yaml
```

**C) Wrong DB credentials in env:**
```bash
# Check API environment variables
kubectl exec deploy/task-api -- env | grep POSTGRES
# Should show:
# POSTGRES_HOST=postgres-service
# POSTGRES_USER=taskuser
# POSTGRES_PASSWORD=taskpass
# POSTGRES_DB=tasktracker

# If wrong, check Secret:
kubectl get secret postgres-secret -o jsonpath='{.data}' | jq
```

#### Cause 2: Wrong Secret keys

**Logs show:** `KeyError: 'POSTGRES_PASSWORD'` or similar

**Fix:** Check Secret has all required keys:
```bash
kubectl get secret postgres-secret -o jsonpath='{.data}' | jq
# Must have: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB

# If keys missing, reapply Secret:
kubectl apply -f manifests/01-secret-postgres.yaml
kubectl rollout restart deploy task-api
```

---

### API returns 404 Not Found

**Symptom:** `curl http://localhost:8080/api/tasks` returns 404

**Diagnosis:**
```bash
kubectl get svc task-api-service
kubectl describe svc task-api-service
```

#### Cause: Service selector mismatch

**Check Service selector matches Pod labels:**
```bash
# Check Service selector
kubectl get svc task-api-service -o yaml | grep selector -A2

# Check Pod labels
kubectl get pods -l app=api --show-labels

# Selector must match Pod labels (app=api)
```

**Fix:**
```bash
# If mismatch, reapply Service:
kubectl apply -f manifests/06-service-api.yaml
```

#### Cause: Endpoints empty

**Check:**
```bash
kubectl get endpoints task-api-service
# Should show IP addresses

# If empty, Pod is not Ready or selector is wrong
kubectl get pods -l app=api
```

---

### API CrashLoopBackOff

**Symptom:** API Pod keeps restarting

**Diagnosis:**
```bash
kubectl logs -l app=api --tail=50
kubectl describe pod -l app=api
```

#### Cause: Image pull error

**Events show:** `Failed to pull image` or `ImagePullBackOff`

**Fix:**
```bash
# Check image is public
docker pull ghcr.io/the-byte-sized/task-api:latest

# If fails, image may not be public
# Go to: https://github.com/orgs/the-byte-sized/packages
# Set visibility to Public
```

#### Cause: Secret not found

**Logs show:** `Secret "postgres-secret" not found`

**Fix:**
```bash
kubectl apply -f manifests/01-secret-postgres.yaml
kubectl rollout restart deploy task-api
```

---

## Frontend Issues

### Frontend Pod not starting

**Symptom:** `kubectl get pods -l app=web` shows `ImagePullBackOff` or `CrashLoopBackOff`

**Diagnosis:**
```bash
kubectl describe pod -l app=web
kubectl logs -l app=web --tail=50
```

#### Cause 1: Image pull error

**Events show:** `Failed to pull image ghcr.io/the-byte-sized/task-web:latest`

**Fix:**
```bash
# Test image pull manually
docker pull ghcr.io/the-byte-sized/task-web:latest

# If fails, image is not public
# Go to: https://github.com/orgs/the-byte-sized/packages/container/task-web/settings
# Change visibility to Public

# Delete pods to retry
kubectl delete pod -l app=web
```

#### Cause 2: nginx cannot resolve API service

**Logs show:** `host not found in upstream "task-api-service"`

**Fix:**
```bash
# Verify API service exists
kubectl get svc task-api-service
# Expected: ClusterIP with port 8080

# If missing:
kubectl apply -f manifests/06-service-api.yaml

# Restart frontend
kubectl rollout restart deploy task-web
```

---

### Browser shows "Cannot connect to API"

**Symptom:** Frontend loads but displays: "⚠️ Impossibile connettersi all'API"

**Diagnosis:**
```bash
# Test from within frontend pod
FRONTEND_POD=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $FRONTEND_POD -- wget -qO- http://task-api-service:8080/api/health
```

#### Cause 1: API Service not found

**wget output:** `bad address 'task-api-service'`

**Fix:**
```bash
# Create API service
kubectl apply -f manifests/06-service-api.yaml

# Verify
kubectl get svc task-api-service
kubectl get endpoints task-api-service
```

#### Cause 2: API pods not ready

**wget output:** `Connection refused` or timeout

**Fix:**
```bash
# Check API pods
kubectl get pods -l app=api
# Must show READY 1/1

# If not ready, check logs
kubectl logs -l app=api --tail=50
```

#### Cause 3: API unhealthy

**wget returns error or non-200 status**

**Fix:**
```bash
# Check API health directly
kubectl port-forward svc/task-api-service 8080:8080 &
curl http://localhost:8080/api/health
kill %1

# If unhealthy, see "API returns 500" section above
```

---

### Port-forward "address already in use"

**Symptom:** `kubectl port-forward svc/task-web-service 8080:80` errors: "bind: address already in use"

#### Cause: Port 8080 is occupied

**Fix - Option 1: Use different port**
```bash
kubectl port-forward svc/task-web-service 8081:80
# Then open http://localhost:8081
```

**Fix - Option 2: Kill existing port-forward**
```bash
# Find and kill port-forward processes
pkill -f "port-forward.*task-web"

# Or find process using port
lsof -ti:8080 | xargs kill -9

# Then retry
kubectl port-forward svc/task-web-service 8080:80
```

---

### Page loads but is blank

**Symptom:** Browser shows blank/white page, no content

**Diagnosis:**
```bash
# Open browser console (F12) and check for JavaScript errors

# Verify nginx is serving correct files
kubectl exec -it deploy/task-web -- ls -la /usr/share/nginx/html/
# Should show: index.html
```

#### Cause: Missing index.html

**ls output:** No index.html file

**Fix:** Image is corrupted, re-pull:
```bash
kubectl delete pod -l app=web
# Kubernetes will recreate with fresh image pull
```

#### Cause: JavaScript error

**Browser console shows errors**

**Fix:** Clear browser cache and reload:
```bash
# Chrome/Edge: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
# Firefox: Ctrl+F5 (Windows) or Cmd+Shift+R (Mac)
```

---

### Tasks don't appear after adding

**Symptom:** Click "Aggiungi" but task doesn't show in list

**Diagnosis:**
```bash
# Check browser console (F12) for errors

# Test API directly
kubectl port-forward svc/task-api-service 8082:8080 &
curl -X POST http://localhost:8082/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Test"}'
kill %1
```

#### Cause 1: API error

**curl returns 500 or error**

**Fix:** See "API returns 500" section above

#### Cause 2: Database not persisting

**curl succeeds but subsequent GET returns empty**

**Fix:**
```bash
# Check Postgres is running
kubectl get pods -l app=database

# Check PVC is bound
kubectl get pvc postgres-pvc

# Check API logs for DB errors
kubectl logs -l app=api --tail=50 | grep -i error
```

#### Cause 3: Frontend not auto-refreshing

**Task exists in API but not visible in browser**

**Fix:** Wait 5 seconds (auto-refresh interval) or manually refresh browser (F5)

---

## RBAC Issues

### 403 on allowed action

**Symptom:** `kubectl auth can-i get pods` says "yes" but actual command gets 403

**Diagnosis:**
```bash
kubectl describe rolebinding readonly-binding
```

#### Cause 1: Wrong namespace in RoleBinding

**RoleBinding is in different namespace than target resources**

**Check:**
```bash
kubectl get rolebinding -A | grep readonly
# Ensure it's in "default" namespace
```

**Fix:**
```bash
# Reapply RBAC manifest:
kubectl delete rolebinding readonly-binding
kubectl apply -f manifests/07-rbac-readonly.yaml
```

#### Cause 2: Wrong subject

**RoleBinding points to wrong ServiceAccount**

**Check:**
```bash
kubectl describe rolebinding readonly-binding
# Check "Subjects" section matches:
# Kind: ServiceAccount
# Name: readonly-sa
# Namespace: default
```

**Fix:** Edit RoleBinding:
```bash
kubectl edit rolebinding readonly-binding
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
kubectl get pods

# Then try action as ServiceAccount
kubectl get pods --as=system:serviceaccount:default:readonly-sa
```

---

### ServiceAccount not working

**Symptom:** Pod can't access Kubernetes API despite having ServiceAccount

#### Cause: ServiceAccount not mounted

**Check Pod spec:**
```bash
kubectl get pod <pod-name> -o yaml | grep serviceAccountName
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

## Quick Reference: Diagnostic Commands

```bash
# Storage
kubectl get pvc,pv,sc
kubectl describe pvc postgres-pvc

# Pods
kubectl get pods
kubectl describe pod <name>
kubectl logs <pod-name> --tail=50
kubectl logs <pod-name> --previous  # Previous crash logs

# Services and connectivity
kubectl get svc,endpoints
kubectl describe svc <name>

# Test connectivity between pods
kubectl exec -it <pod> -- wget -qO- http://<service>:<port>/path

# RBAC
kubectl get sa,role,rolebinding
kubectl describe rolebinding <name>
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>

# Secrets
kubectl get secret <name>
kubectl describe secret <name>
kubectl get secret <name> -o jsonpath='{.data}' | jq

# Events (recent)
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Frontend specific
kubectl logs -l app=web --tail=30
kubectl exec -it deploy/task-web -- cat /etc/nginx/conf.d/default.conf
kubectl exec -it deploy/task-web -- wget -qO- http://task-api-service:8080/api/health
```

---

## Still Stuck?

1. **Run verification:** `./verify.sh` to see which check fails
2. **Check Events:** `kubectl get events --sort-by='.lastTimestamp'`
3. **Review manifests:** Compare your files with originals in repo
4. **Fresh start:** Delete all resources and redeploy:
   ```bash
   kubectl delete all --all
   kubectl delete pvc --all
   kubectl delete secret --all
   # Then reapply from manifests/01-* through 09-*
   ```

---

## External Resources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [PVC Troubleshooting](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#troubleshooting)
- [RBAC Troubleshooting](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#troubleshooting)
- [nginx Troubleshooting](https://nginx.org/en/docs/debugging_log.html)
- [Minikube Docs](https://minikube.sigs.k8s.io/docs/)
