# Bonus Lab: Canary Deployment

**Duration**: 40-50 minutes  
**Difficulty**: Advanced  
**Prerequisites**: Day 5 core labs + Nginx Ingress understanding

---

## What is Canary?

Gradually route increasing percentages of traffic to the new version:
- **v1.0.0 (stable)**: 90% of traffic
- **v1.1.0 (canary)**: 10% of traffic

Monitor metrics. If canary is healthy, increase to 50%, then 100%.

**Trade-off**: Complex traffic splitting, but minimal blast radius.

---

## Goal

Deploy API v1.1.0 as a canary receiving 10% of traffic, monitor it, then promote to 100%.

---

## Step 1: Deploy Stable Version (v1.0.0)

```bash
cd day-05-observability-autoscaling/bonus-canary/

# Ensure v1.0.0 is running
kubectl apply -f ../manifests/04-deployment-api-v1.yaml
kubectl rollout status deployment/api-deployment
```

**Verify baseline**:
```bash
curl -H "Host: capstone.local" http://$(minikube ip)/api/health
# Should return: {"status":"healthy","version":"v1.0.0"}
```

---

## Step 2: Deploy Canary (v1.1.0)

```bash
cat > deployment-api-canary.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-canary
  labels:
    app: api
    track: canary
spec:
  replicas: 1  # Small replica count for 10% traffic
  selector:
    matchLabels:
      app: api
      track: canary
  template:
    metadata:
      labels:
        app: api
        track: canary
        version: v1.1.0
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

kubectl apply -f deployment-api-canary.yaml
```

**Wait for canary**:
```bash
kubectl wait --for=condition=ready pod -l track=canary --timeout=60s
```

---

## Step 3: Configure Traffic Splitting (Nginx Ingress)

**Update Service to include both stable and canary**:
```bash
cat > service-api-combined.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-service-stable
spec:
  selector:
    app: api
    # No track label = matches stable deployment only
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: api-service-canary
spec:
  selector:
    app: api
    track: canary
  ports:
  - port: 80
    targetPort: 8080
EOF

kubectl apply -f service-api-combined.yaml
```

**Update Ingress for canary routing**:
```bash
cat > ingress-canary.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: capstone-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
spec:
  ingressClassName: nginx
  rules:
  - host: capstone.local
    http:
      paths:
      - path: /api(/|\$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-service-stable
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: capstone-ingress-canary
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"  # ← 10% to canary
spec:
  ingressClassName: nginx
  rules:
  - host: capstone.local
    http:
      paths:
      - path: /api(/|\$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-service-canary
            port:
              number: 80
EOF

kubectl apply -f ingress-canary.yaml
```

---

## Step 4: Verify Traffic Split

```bash
# Send 100 requests and count versions
for i in {1..100}; do
  curl -s -H "Host: capstone.local" http://$(minikube ip)/api/health | grep -oP 'version":"\K[^"]+'
done | sort | uniq -c
```

**Expected output (approximately)**:
```
  90 v1.0.0  ← Stable
  10 v1.1.0  ← Canary
```

**🎓 Learning**: Not exactly 90/10 due to randomness, but close.

---

## Step 5: Monitor Canary Metrics

```bash
# Terminal 1: Watch canary CPU/Memory
watch -n 2 'kubectl top pods -l track=canary'

# Terminal 2: Watch canary logs for errors
kubectl logs -l track=canary --tail=50 -f

# Terminal 3: Compare error rates
kubectl logs -l app=api --tail=200 | grep -i error | wc -l
# Should be low (< 5)
```

**Decision point**: If metrics look good after 5 minutes, increase canary %.

---

## Step 6: Increase Canary to 50%

```bash
# Update canary weight
kubectl patch ingress capstone-ingress-canary -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"50"}}}'

echo "Canary now at 50% traffic"
```

**Test again**:
```bash
for i in {1..100}; do
  curl -s -H "Host: capstone.local" http://$(minikube ip)/api/health | grep -oP 'version":"\K[^"]+'
done | sort | uniq -c
```

**Expected**:
```
  50 v1.0.0
  50 v1.1.0
```

**Monitor for another 5 minutes**. If stable, promote to 100%.

---

## Step 7: Promote Canary to 100%

```bash
# Delete canary Ingress (removes traffic split)
kubectl delete ingress capstone-ingress-canary

# Update stable deployment to v1.1.0
kubectl set image deployment/api-deployment api=ghcr.io/the-byte-sized/task-api:v1.1.0

# Delete canary deployment (no longer needed)
kubectl delete deployment api-canary
kubectl delete service api-service-canary

echo "✅ Canary promoted! v1.1.0 is now 100% of traffic."
```

**Verify**:
```bash
for i in {1..20}; do
  curl -s -H "Host: capstone.local" http://$(minikube ip)/api/health | grep -oP 'version":"\K[^"]+'
done | sort | uniq -c
```

**Expected**: All v1.1.0

---

## Rollback Scenario (If Canary Fails)

If during Step 5 or 6 you detect issues:

```bash
# 1. Set canary weight to 0% (stop sending traffic)
kubectl patch ingress capstone-ingress-canary -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"0"}}}'

# 2. Or delete canary Ingress entirely
kubectl delete ingress capstone-ingress-canary

# 3. Delete broken canary
kubectl delete deployment api-canary

echo "✅ Rollback complete. 100% traffic on stable v1.0.0."
```

**Impact**: Only 10-50% of users were affected (not everyone).

---

## Key Takeaways

✅ **Pros**:
- **Reduced blast radius** (only 10% users affected by bugs)
- Gradual confidence building (10% → 50% → 100%)
- Data-driven decisions (stop at any point based on metrics)
- Can A/B test features with real users

❌ **Cons**:
- **Complex setup** (requires Ingress annotations or service mesh)
- Longer deployment time (not instant like blue/green)
- Requires monitoring to make decisions (can't be fully automated)
- Both versions serve traffic simultaneously (must handle shared state)

**When to use**:
- Large user bases (millions of requests)
- When metrics can guide decisions (error rates, latency, business KPIs)
- When risk mitigation > deployment speed
- When you have monitoring infrastructure (Prometheus, Grafana)

---

## Comparison Table

| Aspect | Rolling Update | Blue/Green | Canary |
|--------|----------------|------------|--------|
| **User impact if bug** | 100% (eventually) | 100% (instant) | 10-50% (limited) |
| **Rollback speed** | Minutes | Seconds | Seconds (set weight=0) |
| **Complexity** | Low | Medium | High |
| **Resource cost** | 1x | 2x | 1.1x |
| **Decision point** | None (automated) | Before switch | During (metrics-based) |

---

## Advanced: Custom Metrics for Canary

In production, you'd check:
- **Error rate**: Canary errors < stable errors
- **Latency**: p95 latency canary ≤ stable
- **Business metrics**: Conversion rate, revenue

**Example with Prometheus** (out of scope for KCNA):
```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: api
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  analysis:
    threshold: 10
    stepWeight: 10
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
    - name: request-duration
      thresholdRange:
        max: 500
```

**Tools**: Flagger, Argo Rollouts, Istio

---

## Cleanup

```bash
# Remove canary resources
kubectl delete deployment api-canary || true
kubectl delete service api-service-canary api-service-stable || true
kubectl delete ingress capstone-ingress-canary || true

# Restore original setup
cd ..
kubectl apply -f manifests/05-service-api.yaml
kubectl apply -f manifests/08-ingress.yaml
kubectl apply -f manifests/04-deployment-api-v1.yaml
```

---

**🎓 KCNA Tip**: Exam may ask "Which strategy minimizes user impact of bugs?" → Canary.

**📚 Reference**: 
- [Nginx Canary Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#canary)
- [CNCF Flagger](https://flagger.app/)
