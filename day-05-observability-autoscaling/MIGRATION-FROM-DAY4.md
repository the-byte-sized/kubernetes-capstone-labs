# Migration from Day 4 to Day 5

This guide explains the differences between Day 4 and Day 5 setups.

---

## What Changed?

### Image Tags: `:latest` → Versioned

**Day 4**:
```yaml
image: ghcr.io/the-byte-sized/task-api:latest
```

**Day 5**:
```yaml
image: ghcr.io/the-byte-sized/task-api:v1.0.0
```

**Why**: Versioned tags enable controlled rollouts and rollbacks.

---

### New Resource: HorizontalPodAutoscaler

**Day 5 adds**:
- `manifests/09-hpa-api.yaml` (NEW)
- Configures autoscaling for API deployment
- Target: Keep CPU at 50% of requests

**Day 4 had**: Fixed 2 replicas (no autoscaling)

---

### Deployment Changes

**Added to manifests**:
- `version: v1.0.0` label on Pods (for tracking)
- `imagePullPolicy: Always` (force pull even if tag exists locally)

**Everything else unchanged**:
- Resource requests/limits (same)
- Probes (same)
- Environment variables (same)

---

## What Stayed the Same?

✅ **Unchanged resources** (can reuse from Day 4):
- Secret (`00-secret-postgres.yaml`)
- PVC (`01-pvc-postgres.yaml`)
- Services (`03-service-postgres.yaml`, `05-service-api.yaml`, `07-service-web.yaml`)
- Ingress (`08-ingress.yaml`)
- RBAC (`10-rbac-readonly.yaml`)
- Postgres deployment (`02-deployment-postgres.yaml`)

**Data preserved**: PostgreSQL PVC data is NOT touched.

---

## Side-by-Side Comparison

### API Deployment

| Aspect | Day 4 | Day 5 |
|--------|-------|-------|
| **Image** | `task-api:latest` | `task-api:v1.0.0` |
| **Replicas** | Fixed: 2 | HPA-managed: 1-5 |
| **Version label** | None | `version: v1.0.0` |
| **Pull policy** | IfNotPresent (default) | Always |
| **Resource requests** | cpu: 100m, mem: 128Mi | Same |
| **Probes** | readiness + liveness | Same |

### Web Deployment

| Aspect | Day 4 | Day 5 |
|--------|-------|-------|
| **Image** | `task-web:latest` | `task-web:v1.0.0` |
| **Replicas** | Fixed: 3 | Fixed: 3 (no HPA) |
| **Version label** | None | `version: v1.0.0` |
| **Pull policy** | IfNotPresent | Always |
| **Everything else** | Same | Same |

---

## Migration Strategies

### Option A: Fresh Start (Safest)

**When to use**: If Day 4 had issues or you want a clean slate.

```bash
# 1. Save data (optional)
kubectl exec -it $(kubectl get pod -l app=postgres -o name | head -1) -- \
  pg_dump -U taskuser tasktracker > backup.sql

# 2. Delete workloads (keeps PVC)
kubectl delete deployment api-deployment web-deployment postgres
kubectl delete service api-service web-service postgres-service
kubectl delete ingress capstone-ingress

# 3. Apply Day 5
cd day-05-observability-autoscaling/
kubectl apply -f manifests/

# 4. Verify
kubectl get pods
# Expected: All Pods Running with new names
```

**Result**: New Pods, but same data (PVC reused).

---

### Option B: In-Place Update (Fastest)

**When to use**: If Day 4 is stable and working.

```bash
cd day-05-observability-autoscaling/

# 1. Update API deployment (triggers rolling update)
kubectl apply -f manifests/04-deployment-api-v1.yaml
kubectl rollout status deployment/api-deployment

# 2. Update Web deployment
kubectl apply -f manifests/06-deployment-web-v1.yaml
kubectl rollout status deployment/web-deployment

# 3. Add HPA
kubectl apply -f manifests/09-hpa-api.yaml

# 4. Verify
kubectl get hpa api-hpa
# Expected: TARGETS showing percentage (not <unknown>)
```

**Result**: Zero downtime, Pods updated via rolling update.

---

### Option C: Hybrid (Selective)

**When to use**: If only specific components had issues.

```bash
# Update only what you need, e.g.:

# Just API:
kubectl apply -f manifests/04-deployment-api-v1.yaml
kubectl apply -f manifests/09-hpa-api.yaml

# Or just add HPA (keep existing deployment):
kubectl apply -f manifests/09-hpa-api.yaml
```

---

## Verification Checklist

After migration, verify:

```bash
# 1. Pods Running
kubectl get pods
# Expected: All Pods Running, using v1.0.0 images

# 2. HPA configured
kubectl get hpa api-hpa
# Expected: TARGETS showing percentage (e.g., 12%/50%)

# 3. Services working
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Expected: {"status":"healthy",...}

# 4. Data preserved (if migrating from Day 4)
curl -H "Host: capstone.local" http://$(minikube ip)/api/tasks
# Expected: Your existing tasks from Day 4

# 5. Metrics available
kubectl top pods
# Expected: CPU/Memory values (not <unknown>)
```

---

## Rollback to Day 4 (If Needed)

If you need to go back:

```bash
# 1. Remove HPA
kubectl delete hpa api-hpa

# 2. Revert to Day 4 manifests
cd ../day-04-storage-security/
kubectl apply -f manifests/05-deployment-api.yaml
kubectl apply -f manifests/08-deployment-web.yaml

# 3. Verify
kubectl get pods
# Expected: Pods running with :latest images
```

---

## Troubleshooting Migration

### Issue: Pods stuck in `ImagePullBackOff`

**Cause**: Versioned images (`v1.0.0`, `v1.1.0`) don't exist in registry.

**Solution**:
```bash
# Check if images exist
docker images | grep task-api

# If missing, create tags:
docker tag ghcr.io/the-byte-sized/task-api:latest ghcr.io/the-byte-sized/task-api:v1.0.0
docker push ghcr.io/the-byte-sized/task-api:v1.0.0

# Or use :latest temporarily:
kubectl set image deployment/api-deployment api=ghcr.io/the-byte-sized/task-api:latest
```

### Issue: HPA shows `<unknown>/50%`

**Cause**: Metrics not available yet.

**Solution**:
```bash
# Install metrics-server
./scripts/setup-metrics.sh

# Wait 30s
kubectl get hpa api-hpa
# Should now show percentage
```

### Issue: Data lost after migration

**Cause**: PVC was deleted (shouldn't happen with Option A/B).

**Check**:
```bash
kubectl get pvc postgres-pvc
# If STATUS=Bound: Data is safe
# If missing: PVC was deleted (restore from backup)
```

**Prevention**: Never run `kubectl delete pvc` unless explicitly cleaning up.

---

## FAQ

**Q: Will migration cause downtime?**  
A: Option B (in-place update) = zero downtime (rolling update). Option A = brief downtime during re-creation.

**Q: Will I lose my database data?**  
A: No, PVC is preserved in both options unless explicitly deleted.

**Q: Can I keep using `:latest` tags?**  
A: Yes, but defeats the purpose of Day 5 (controlled rollouts/rollbacks require versions).

**Q: Do I need to retag images locally?**  
A: Only if images are pulled from local minikube registry. If using GHCR, tags already exist.

**Q: Can I skip Day 5 and go to Day 6?**  
A: Not recommended. Day 6 may assume HPA and versioned images exist.

---

**📚 Reference**: See [README.md](./README.md) for full Day 5 lab instructions.
