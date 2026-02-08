# Lab 2.4 Troubleshooting Guide

## 🔍 Common Issues and Solutions

This guide covers the most frequent problems encountered in Lab 2.4 (multi-tier capstone).

---

## Issue 1: API Deployment Pods not starting (Pending)

### **Symptoms:**
```bash
kubectl get pods -l app=api
```
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-7c8f9d5b6f-abc12   0/1     Pending   0          2m
api-deployment-7c8f9d5b6f-def34   0/1     Pending   0          2m
```

### **Diagnosis:**

Check Events:
```bash
kubectl describe pod -l app=api | grep -A 10 Events
```

**Common causes:**

**Cause 1: Insufficient resources**
```
Events:
  Warning  FailedScheduling  pod/api-deployment-xxx  0/1 nodes available: insufficient memory.
```

**Fix:**
```bash
# Check node capacity
kubectl describe node minikube | grep -A 5 Allocatable

# Option A: Reduce resource requests in api-deployment.yaml
resources:
  requests:
    memory: "32Mi"  # Was 64Mi
    cpu: "50m"      # Was 100m

# Option B: Increase Minikube resources
minikube stop
minikube start --memory=4096 --cpus=2

# Reapply
kubectl apply -f api-deployment.yaml
```

**Cause 2: Image pull issues (ImagePullBackOff)**

See Issue 2 below.

---

## Issue 2: API Pods in ImagePullBackOff or ErrImagePull

### **Symptoms:**
```bash
kubectl get pods -l app=api
```
```
NAME                              READY   STATUS             RESTARTS   AGE
api-deployment-7c8f9d5b6f-abc12   0/1     ImagePullBackOff   0          5m
```

### **Diagnosis:**

Check Events:
```bash
kubectl describe pod -l app=api | grep -A 5 "Failed to pull image"
```

**Common causes:**

**Cause 1: Image doesn't exist or typo in name**
```
Failed to pull image "kennethreitz/httpbinn:latest": rpc error: code = NotFound
```

**Fix:**
```bash
# Verify correct image name
# Correct: kennethreitz/httpbin:latest
# Common typo: httpbinn (double 'n')

# Edit api-deployment.yaml
image: kennethreitz/httpbin:latest

# Reapply
kubectl apply -f api-deployment.yaml
```

**Cause 2: Docker Hub rate limiting**
```
toomanyrequests: You have reached your pull rate limit
```

**Fix:**
```bash
# Option A: Use alternative registry
image: docker.io/kennethreitz/httpbin:latest

# Option B: Wait 1 hour (rate limit resets)

# Option C: Use authenticated pull (create Docker Hub account + Secret)
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=docker.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  --docker-email=YOUR_EMAIL

# Add to api-deployment.yaml:
spec:
  template:
    spec:
      imagePullSecrets:
      - name: dockerhub-secret
```

**Cause 3: Network issues (Minikube can't reach registry)**
```
Error: dial tcp: lookup registry-1.docker.io: no such host
```

**Fix:**
```bash
# Restart Minikube networking
minikube stop
minikube start

# Verify connectivity from Minikube node
minikube ssh
curl -I https://registry-1.docker.io/v2/
exit
```

---

## Issue 3: API Service has no Endpoints

### **Symptoms:**
```bash
kubectl get endpoints api-service
```
```
NAME          ENDPOINTS   AGE
api-service   <none>      2m
```

Test fails:
```bash
kubectl run test-api --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
# curl: (7) Failed to connect to api-service port 80: Connection refused
```

### **Diagnosis:**

Check Service selector:
```bash
kubectl get service api-service -o yaml | grep -A 3 selector
```

Check Pod labels:
```bash
kubectl get pods -l app=api --show-labels
```

**Common causes:**

**Cause 1: Label mismatch**

```yaml
# Service selector:
selector:
  app: api
  tier: backend

# But Pod has:
labels:
  app: httpbin  # MISMATCH!
  tier: backend
```

**Fix:**
```bash
# Ensure api-deployment.yaml template.metadata.labels match Service selector
template:
  metadata:
    labels:
      app: api       # Must match Service
      tier: backend  # Must match Service

# Reapply Deployment
kubectl apply -f api-deployment.yaml

# Wait for Pods to recreate
kubectl get pods -l app=api --watch

# Verify Endpoints
kubectl get endpoints api-service
```

**Cause 2: Pods not Ready (readiness probe failing)**

Check Pod status:
```bash
kubectl get pods -l app=api
```
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-7c8f9d5b6f-abc12   0/1     Running   0          3m  # NOT READY!
```

Check readiness probe:
```bash
kubectl describe pod -l app=api | grep -A 10 "Readiness"
```
```
Readiness probe failed: HTTP probe failed with statuscode: 404
```

**Fix:**

```bash
# Check probe path is correct
# httpbin exposes /get, not /health

# In api-deployment.yaml:
readinessProbe:
  httpGet:
    path: /get  # Correct for httpbin
    port: 80

# If using different API image, adjust path
# Example for custom app:
#   path: /health
#   path: /api/status

# Reapply
kubectl apply -f api-deployment.yaml
```

---

## Issue 4: DNS resolution fails (api-service not found)

### **Symptoms:**
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
```
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

nslookup: can't resolve 'api-service'
```

### **Diagnosis:**

Check Service exists:
```bash
kubectl get service api-service
```

Check CoreDNS:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Common causes:**

**Cause 1: Service doesn't exist**

```bash
kubectl get service api-service
# Error from server (NotFound): services "api-service" not found
```

**Fix:**
```bash
# Apply Service manifest
kubectl apply -f api-service.yaml

# Verify
kubectl get service api-service
```

**Cause 2: CoreDNS not running**

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
# No resources found or CrashLoopBackOff
```

**Fix:**
```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# If still failing, restart Minikube
minikube stop
minikube start

# Verify
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## Issue 5: curl from web Pod to API fails (connection refused)

### **Symptoms:**
```bash
# Exec into web Pod
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $WEB_POD -- /bin/sh

# Inside Pod
apk add --no-cache curl
curl http://api-service/get
# curl: (7) Failed to connect to api-service port 80: Connection refused
```

### **Diagnosis:**

From inside web Pod:
```bash
# Test DNS
nslookup api-service
# Should resolve to ClusterIP

# Test ClusterIP directly
curl http://10.96.234.56/get  # Use actual ClusterIP from kubectl get svc api-service
```

**Common causes:**

**Cause 1: API Service has no Endpoints**

See Issue 3 above.

**Cause 2: API Pods not Ready**

Even if Pods are Running, they must be Ready:

```bash
kubectl get pods -l app=api
```
```
NAME                              READY   STATUS    RESTARTS   AGE
api-deployment-7c8f9d5b6f-abc12   0/1     Running   0          5m  # 0/1 = NOT READY
```

**Fix:** Check readiness probe (see Issue 3, Cause 2).

**Cause 3: Port mismatch**

```yaml
# Service:
ports:
- port: 80
  targetPort: 8080  # WRONG! httpbin listens on 80, not 8080
```

**Fix:**
```yaml
# api-service.yaml:
ports:
- port: 80
  targetPort: 80  # Match container port
```

**Cause 4: Network policy blocking traffic (if NetworkPolicy enabled)**

Not common in basic Minikube, but possible:

```bash
kubectl get networkpolicies
# If any exist, they may block traffic
```

**Fix:**
```bash
# Temporarily remove NetworkPolicies for testing
kubectl delete networkpolicy --all
```

---

## Issue 6: Multiple API versions coexist (wrong ReplicaSet)

### **Symptoms:**

After updating API Deployment:
```bash
kubectl get replicaset -l app=api
```
```
NAME                        DESIRED   CURRENT   READY   AGE
api-deployment-7c8f9d5b6f   2         2         2       10m
api-deployment-8d9e1a2c3g   2         2         0       30s  # New version, not Ready
```

Traffic fails intermittently.

### **Diagnosis:**

Check rollout status:
```bash
kubectl rollout status deployment api-deployment
```
```
Waiting for deployment "api-deployment" rollout to finish: 2 out of 4 new replicas have been updated...
```

**Common causes:**

**Cause: New Pods failing readiness probe**

New ReplicaSet Pods not becoming Ready, blocking rollout:

```bash
kubectl describe pod -l app=api | grep -A 5 "Readiness probe failed"
```

**Fix:**

```bash
# Check new Pod logs
NEW_POD=$(kubectl get pods -l app=api --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs $NEW_POD

# Common issues:
# - Wrong image tag
# - Missing environment variable
# - Readiness probe path changed

# If update is bad, rollback:
kubectl rollout undo deployment api-deployment

# Verify rollback:
kubectl rollout status deployment api-deployment
```

---

## Issue 7: Load balancing not working (all requests go to one Pod)

### **Symptoms:**

Multiple requests, but only one API Pod shows traffic:

```bash
kubectl logs api-deployment-xxx | wc -l
# 100 requests

kubectl logs api-deployment-yyy | wc -l
# 0 requests  (!)  
```

### **Diagnosis:**

Check Service sessionAffinity:
```bash
kubectl get service api-service -o yaml | grep sessionAffinity
```

**Common causes:**

**Cause: sessionAffinity set to ClientIP**

```yaml
sessionAffinity: ClientIP
```

This pins all requests from same client IP to same Pod.

**Fix:**

```yaml
# api-service.yaml:
sessionAffinity: None  # Load-balance every request
```

```bash
kubectl apply -f api-service.yaml

# Test again
for i in {1..10}; do
  kubectl run test-lb-$i --image=curlimages/curl:8.11.1 --rm --restart=Never -- curl -s http://api-service/get
done

# Check logs
kubectl logs -l app=api --tail=20
```

---

## 🔧 General Debugging Workflow

**For any Lab 2.4 issue, follow this sequence:**

### **1. Check Deployment:**
```bash
kubectl get deployment api-deployment
# Expect: READY=2/2, AVAILABLE=2
```

### **2. Check Pods:**
```bash
kubectl get pods -l app=api -o wide
# Expect: STATUS=Running, READY=1/1
```

If not:
```bash
kubectl describe pod -l app=api
kubectl logs -l app=api
```

### **3. Check Service:**
```bash
kubectl get service api-service
# Expect: TYPE=ClusterIP, ClusterIP assigned
```

### **4. Check Endpoints:**
```bash
kubectl get endpoints api-service
# Expect: 2 Pod IPs listed
```

If empty:
```bash
# Compare selector vs Pod labels
kubectl get service api-service -o yaml | grep -A 3 selector
kubectl get pods -l app=api --show-labels
```

### **5. Test DNS:**
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
# Expect: Resolves to ClusterIP
```

### **6. Test connectivity:**
```bash
kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
# Expect: JSON response
```

### **7. Check Events:**
```bash
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

---

## 📋 Quick Reference Commands

```bash
# View all capstone resources
kubectl get all

# Restart API Deployment (if needed)
kubectl rollout restart deployment api-deployment

# Scale API
kubectl scale deployment api-deployment --replicas=3

# Delete and recreate API Service
kubectl delete service api-service
kubectl apply -f api-service.yaml

# Force delete stuck Pod
kubectl delete pod <pod-name> --force --grace-period=0

# Check resource usage
kubectl top pods
kubectl top node

# Describe everything
kubectl describe deployment api-deployment
kubectl describe service api-service
kubectl describe pod -l app=api
```

---

## 🆘 Last Resort: Clean Slate

If nothing works, reset lab:

```bash
# Delete API components
kubectl delete -f api-deployment.yaml
kubectl delete -f api-service.yaml

# Wait for cleanup
kubectl get pods -l app=api --watch
# (Ctrl+C when all gone)

# Reapply
kubectl apply -f api-deployment.yaml
kubectl apply -f api-service.yaml

# Verify
kubectl get all -l app=api
```

If Minikube itself is unstable:

```bash
minikube stop
minikube delete
minikube start --memory=4096 --cpus=2

# Reapply all Day 2 labs
cd day-02-workloads-and-services
kubectl apply -f lab-2.2-deployment/web-deployment.yaml
kubectl apply -f lab-2.3-service/web-service.yaml
kubectl apply -f lab-2.4-multi-tier-capstone/api-deployment.yaml
kubectl apply -f lab-2.4-multi-tier-capstone/api-service.yaml
```

---

**Still stuck? Check:**
- [Lab 2.4 README](./README.md) - Verify steps
- [Lezione 2 PDF](../../../docs/Lezione-2.pdf) - Theory review
- [Kubernetes Service Debugging](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
