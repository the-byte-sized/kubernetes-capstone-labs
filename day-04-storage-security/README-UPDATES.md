# README Updates Required

## Critical String Replacements

The following replacements need to be made throughout `README.md`:

### 1. Service Name Fixes (CRITICAL)

```bash
# Replace ALL occurrences:
task-api-service  →  api-service
task-web-service  →  web-service
```

**Affected lines:**
- Step 5: `kubectl port-forward svc/task-api-service` → `kubectl port-forward svc/api-service`
- Step 6: `kubectl port-forward svc/task-api-service` → `kubectl port-forward svc/api-service`  
- Step 10: `kubectl get svc task-web-service` → `kubectl get svc web-service`
- Step 11: `kubectl port-forward svc/task-web-service` → `kubectl port-forward svc/web-service`
- Step 15: `service/task-api-service` → `service/api-service`
- Step 15: `service/task-web-service` → `service/web-service`
- Debug commands: `kubectl exec -it deploy/task-web -- wget -qO- http://task-api-service` → `http://api-service`
- Question 7: `task-api-service:8080` → `api-service:8080`

### 2. Deployment Name Fixes

```bash
# Replace:
deployment/task-api  →  deployment/api-deployment
deployment/task-web  →  deployment/web-deployment
deploy/task-api      →  deploy/api-deployment
deploy/task-web      →  deploy/web-deployment
```

**Affected lines:**
- Step 3: `kubectl get pods -l app=database` is WRONG → should be `kubectl get pods -l app=postgres`
- Step 15: `deployment/task-api` → `deployment/api-deployment`
- Step 15: `deployment/task-web` → `deployment/web-deployment`
- Debug commands: `deploy/task-api` → `deploy/api-deployment`
- Debug commands: `deploy/task-web` → `deploy/web-deployment`

### 3. Architecture Diagram Fix

**Current (WRONG)**:
```
Day 4: [Browser] → [Frontend nginx] → [Flask API] → [PostgreSQL + PVC]
                    (port-forward)     (ClusterIP)    (with Secret)
```

**Correct**:
```
Day 3: [Ingress capstone.local] → [web-service] + [api-service (httpbin)]
                                        ↓
Day 4: [Ingress capstone.local] → [web-service] + [api-service (Flask)] → [postgres]
       (SAME INGRESS!)              (NEW UI)       (REAL API + PVC)          (NEW TIER)
```

### 4. Add Migration Notice at Top

Add after "What We're Building" section:

```markdown
---

## ⚠️ Coming from Day 3?

**READ THIS FIRST**: [MIGRATION-FROM-DAY3.md](./MIGRATION-FROM-DAY3.md)

**Quick transition**:
```bash
# Clean Day 3 mock services (Ingress stays!)
kubectl delete deployment web-deployment api-deployment
kubectl delete service web-service api-service

# Apply Day 4 (uses same service names)
kubectl apply -f manifests/

# Ingress still works!
curl -H "Host: capstone.local" http://$(minikube ip)/
```

**What changed**: Backend implementation (httpbin → Flask+DB), service names UNCHANGED.

---
```

### 5. Update Step 11 (Frontend Access)

**Replace current Step 11 with**:

```markdown
### Step 11: Access Frontend via Ingress

**Day 4 maintains Ingress continuity from Day 3!**

```bash
# Deploy Ingress (if not already from Day 3)
kubectl apply -f manifests/10-ingress.yaml

# Wait for Ingress to be ready
kubectl get ingress capstone-ingress
# Expected: ADDRESS column populated

# Add to /etc/hosts (one-time setup)
echo "$(minikube ip) capstone.local" | sudo tee -a /etc/hosts
```

**Access in browser**: [http://capstone.local](http://capstone.local)

**Expected**:
- Page loads with purple gradient background
- Title: "📝 Task Tracker"
- Input field to add tasks
- List of existing tasks (if any from Step 5)
- Bottom shows: "Frontend (nginx) → API Service (Flask) → DB Service (PostgreSQL)"

**Alternative (if Ingress not working)**: Use port-forward:
```bash
kubectl port-forward svc/web-service 8081:80
# Then open: http://localhost:8081
```
```

### 6. Update "What's Next (Day 5)" Section

**Replace**:
```markdown
## What's Next (Day 5)

Tomorrow we'll add:
- **Ingress**: Expose frontend with domain name (no more port-forward!)
```

**With**:
```markdown
## What's Next (Day 5)

Tomorrow we'll enhance the existing application:
- **Ingress evolution**: Already working! Day 5 adds TLS/HTTPS
```

### 7. Update Step 3 Label Selector

**Line**: `kubectl get pods -l app=database -w`

**Should be**: `kubectl get pods -l app=postgres -w`

(Because the Deployment uses `app: postgres`, not `app: database`)

### 8. Update Expected Output Step 15

**Current**:
```
# - deployment/postgres (1/1)
# - deployment/task-api (2/2)
# - deployment/task-web (2/2)
```

**Correct**:
```
# - deployment/postgres (1/1)
# - deployment/api-deployment (2/2)
# - deployment/web-deployment (3/3)
```

---

## Automated Fix Script

If you want to apply all fixes automatically:

```bash
cd day-04-storage-security/

# Backup original
cp README.md README.md.backup

# Apply fixes
sed -i 's/task-api-service/api-service/g' README.md
sed -i 's/task-web-service/web-service/g' README.md
sed -i 's/deployment\/task-api/deployment\/api-deployment/g' README.md
sed -i 's/deployment\/task-web/deployment\/web-deployment/g' README.md
sed -i 's/deploy\/task-api/deploy\/api-deployment/g' README.md
sed -i 's/deploy\/task-web/deploy\/web-deployment/g' README.md
sed -i 's/app=database/app=postgres/g' README.md

# Verify changes
git diff README.md
```

---

## Manual Review Required

- [ ] Architecture diagram (lines 20-25)
- [ ] Migration notice (add after line 27)
- [ ] Step 11 complete rewrite (lines ~180-200)
- [ ] "What's Next" section (lines ~450)
- [ ] Step 15 expected output (lines ~235)
