# Bonus Lab: Blue/Green Deployment

**Duration**: 30-40 minutes  
**Difficulty**: Intermediate  
**Prerequisites**: Day 5 core labs completed

---

## What is Blue/Green?

Two identical production environments:
- **Blue**: Current version (serving traffic)
- **Green**: New version (deployed but idle)

Switch traffic atomically by changing Service selector.

**Trade-off**: 2x resource cost for instant rollback capability.

---

## Goal

Deploy API v1.0.0 (blue) and v1.1.0 (green) simultaneously, then switch traffic from blue to green with zero downtime.

---

## Step 1: Prepare Blue Deployment

```bash
cd day-05-observability-autoscaling/bonus-bluegreen/

# Create blue deployment (v1.0.0)
cat > deployment-api-blue.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-blue
  labels:
    app: api
    version: blue
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      version: blue
  template:
    metadata:
      labels:
        app: api
        version: blue
    spec:
      containers:
      - name: api
        image: ghcr.io/the-byte-sized/task-api:v1.0.0
        ports:
        - containerPort: 8080
        envFrom:
        - secretRef:
            name: postgres-secret
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF

kubectl apply -f deployment-api-blue.yaml
```

---

## Step 2: Update Service to Target Blue

```bash
cat > service-api-bluegreen.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api
    version: blue  # ← Traffic goes to BLUE
  ports:
  - port: 80
    targetPort: 8080
EOF

kubectl apply -f service-api-bluegreen.yaml
```

**Verify blue is serving**:
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Should succeed (blue Pods responding)
```

---

## Step 3: Deploy Green (v1.1.0)

```bash
cat > deployment-api-green.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-green
  labels:
    app: api
    version: green
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      version: green
  template:
    metadata:
      labels:
        app: api
        version: green
    spec:
      containers:
      - name: api
        image: ghcr.io/the-byte-sized/task-api:v1.1.0
        ports:
        - containerPort: 8080
        envFrom:
        - secretRef:
            name: postgres-secret
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF

kubectl apply -f deployment-api-green.yaml
```

**Wait for green Pods**:
```bash
kubectl wait --for=condition=ready pod -l version=green --timeout=60s
```

---

## Step 4: Verify Both Environments Running

```bash
kubectl get pods -l app=api
```

**Expected**:
```
NAME                        READY   STATUS    VERSION
api-blue-xxx                2/2     Running   (v1.0.0)
api-blue-yyy                2/2     Running   (v1.0.0)
api-green-zzz               2/2     Running   (v1.1.0)  ← NOT serving traffic yet
api-green-www               2/2     Running   (v1.1.0)  ← NOT serving traffic yet
```

**Test green directly** (bypassing Service):
```bash
GREEN_POD=$(kubectl get pod -l version=green -o name | head -1)
kubectl port-forward $GREEN_POD 8080:8080 &
PORT_FWD_PID=$!

curl http://localhost:8080/health
# Should return: {"status":"healthy","version":"v1.1.0"}

kill $PORT_FWD_PID
```

**🎓 Learning**: Green is fully deployed and tested, but receives ZERO production traffic.

---

## Step 5: Switch Traffic to Green (THE CUT-OVER)

Open **two terminals**:

### Terminal 1: Monitor Service Availability
```bash
while true; do
  RESPONSE=$(curl -s -H "Host: capstone.local" http://$(minikube ip)/api/health)
  VERSION=$(echo $RESPONSE | grep -oP 'version":"\K[^"]+' || echo "FAIL")
  echo "[$(date +%H:%M:%S)] Version: $VERSION"
  sleep 0.5
done
```

### Terminal 2: Switch Service Selector
```bash
kubectl patch service api-service -p '{"spec":{"selector":{"version":"green"}}}'
```

**Expected output in Terminal 1**:
```
[19:50:10] Version: v1.0.0  ← Blue
[19:50:10] Version: v1.0.0
[19:50:11] Version: v1.1.0  ← INSTANT switch to Green!
[19:50:11] Version: v1.1.0
[19:50:12] Version: v1.1.0
```

**🎉 Zero downtime, instant switch!**

---

## Step 6: Monitor Green in Production

```bash
# Watch Pods
kubectl top pods -l version=green

# Check logs for errors
kubectl logs -l version=green --tail=50 --since=5m

# Monitor metrics (if issues arise)
watch -n 2 'kubectl top pods -l version=green'
```

**Simulate monitoring period**: Wait 2-5 minutes. If no issues, proceed to cleanup blue.

---

## Step 7A: Cleanup Blue (Success Scenario)

If green is healthy:

```bash
# Remove blue deployment
kubectl delete deployment api-blue

echo "✅ Blue/Green deployment complete!"
echo "Green (v1.1.0) is now the only version running."
```

---

## Step 7B: Rollback to Blue (If Green Has Issues)

If green has problems:

```bash
# INSTANT rollback (just switch selector back)
kubectl patch service api-service -p '{"spec":{"selector":{"version":"blue"}}}'

echo "✅ Rolled back to blue (v1.0.0) in < 1 second!"
```

**Observe in monitoring terminal**: Traffic instantly reverts to v1.0.0.

**Then debug green**:
```bash
# Green Pods still running (didn't delete them)
kubectl logs -l version=green --tail=100
kubectl describe pod -l version=green

# Fix issues, then try switch again when ready
```

---

## Key Takeaways

✅ **Pros**:
- Instant cut-over (1 second)
- Instant rollback (1 second)
- Full testing before switch (green can be tested via port-forward)
- No gradual exposure (either all traffic or none)

❌ **Cons**:
- **2x resource cost** (both deployments running)
- More complex manifest management (2 deployments)
- Database schema must work with BOTH versions during switch

**When to use**:
- High-stakes releases (payment systems, critical APIs)
- When instant rollback is worth the resource cost
- When you can test green thoroughly before switch

---

## Comparison with Rolling Update

| Aspect | Rolling Update | Blue/Green |
|--------|----------------|------------|
| **Resource cost** | 1x + small surge | 2x (full duplication) |
| **Switch time** | Gradual (1-2 min) | Instant (< 1 sec) |
| **Rollback time** | Re-deploy (1-2 min) | Instant (< 1 sec) |
| **Both versions live** | Briefly (during rollout) | Yes (until cleanup) |
| **Complexity** | Low | Medium |

---

## Cleanup

```bash
# Remove both deployments
kubectl delete deployment api-blue api-green

# Revert service to original (without version selector)
kubectl apply -f ../manifests/05-service-api.yaml

# Re-deploy normal API
kubectl apply -f ../manifests/04-deployment-api-v1.yaml
```

---

**🎓 KCNA Tip**: Exam may ask "Which strategy allows instant rollback with zero deployment time?" → Blue/Green.

**📚 Reference**: [Kubernetes Deployment Strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
