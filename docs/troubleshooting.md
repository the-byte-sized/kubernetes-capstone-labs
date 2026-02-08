# Global Troubleshooting Guide

Common issues across all days and general debugging strategies.

---

## 🧐 General Troubleshooting Method

### The 4-Step Process

1. **What did you want?** (desired state in manifest)
2. **What do you have?** (actual state in cluster)
3. **Where does it stop?** (which component/layer)
4. **What says why?** (events, logs, conditions)

### Standard Diagnostic Flow

```bash
# Step 1: High-level status
kubectl get <resource>

# Step 2: Detailed info + events
kubectl describe <resource> <name>

# Step 3: Application logs (if running)
kubectl logs <pod-name>

# Step 4: Interactive debugging (if needed)
kubectl exec -it <pod-name> -- /bin/sh
```

---

## 🔴 Common Error Patterns

### Pattern: `Pending` State

**Meaning:** Scheduler can't place the Pod on a node.

**Common causes:**
- Insufficient resources (CPU/memory)
- No nodes available or all nodes `NotReady`
- Node selector/affinity not matching any node
- PersistentVolume not available (Days 4+)

**Diagnosis:**
```bash
kubectl describe pod <name> | grep -A 10 Events
```

Look for: `FailedScheduling`, `Insufficient cpu/memory`

**Fix examples:**
```bash
# Check node resources
kubectl describe node minikube | grep -A 5 "Allocated resources"

# Reduce resource requests in manifest
# Or restart Minikube with more resources
minikube delete
minikube start --memory=4096 --cpus=2
```

---

### Pattern: `ImagePullBackOff` / `ErrImagePull`

**Meaning:** Kubelet can't pull the container image.

**Common causes:**
- Typo in image name or tag
- Image doesn't exist
- Network/registry connectivity issues
- Docker Hub rate limiting
- Private registry without credentials

**Diagnosis:**
```bash
kubectl describe pod <name> | grep -i image
kubectl describe pod <name> | grep -A 10 Events
```

Look for: `Failed to pull image`, `not found`, `manifest unknown`

**Fix examples:**
```bash
# Verify image name
cat manifests/*.yaml | grep image:

# Test pull manually
minikube ssh
docker pull nginx:1.25-alpine
exit

# Check Minikube internet access
minikube ssh
ping -c 3 registry-1.docker.io
exit
```

---

### Pattern: `CrashLoopBackOff`

**Meaning:** Container starts but exits immediately. Kubernetes retries with backoff.

**Common causes:**
- Application error (wrong command, missing dependencies)
- Liveness probe failing
- Configuration issue (wrong env vars, missing files)

**Diagnosis:**
```bash
# Check current logs
kubectl logs <pod-name>

# Check previous container logs
kubectl logs <pod-name> --previous

# Check restart count
kubectl get pod <pod-name>
```

**Fix examples:**
- Fix application code/configuration
- Adjust liveness probe settings
- Check ConfigMap/Secret mounts

---

### Pattern: Running but Not Ready

**Meaning:** Container is running but readiness probe is failing.

**Impact:** Pod won't receive traffic from Service.

**Diagnosis:**
```bash
kubectl describe pod <name> | grep -A 5 Conditions
kubectl describe pod <name> | grep -i ready
kubectl logs <pod-name>
```

**Common causes:**
- Application not listening on expected port
- Readiness probe checking wrong endpoint
- Application still initializing

---

## 🌐 Networking Issues

### Service Has No Endpoints

**Symptom:**
```bash
$ kubectl get endpoints <service-name>
NAME   ENDPOINTS   AGE
web    <none>      2m
```

**Diagnosis:**
```bash
# Check Service selector
kubectl get svc <service-name> -o yaml | grep -A 3 selector

# Check Pod labels
kubectl get pods --show-labels

# Check if Pods are Ready
kubectl get pods
```

**Common fixes:**
1. **Selector mismatch:** Service selector doesn't match Pod labels
2. **Pods not Ready:** Check readiness probes
3. **Wrong namespace:** Service and Pods in different namespaces

---

### DNS Not Resolving

**Symptom:**
```bash
# Inside a Pod
$ nslookup my-service
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

nslookup: can't resolve 'my-service'
```

**Diagnosis:**
```bash
# Check CoreDNS is running
kubectl get pods -n kube-system | grep coredns

# Check Service exists
kubectl get svc <service-name>

# Test from another Pod
kubectl run test --rm -it --image=busybox -- nslookup <service-name>
```

**Common causes:**
- Service doesn't exist
- Wrong namespace (try `<service>.<namespace>.svc.cluster.local`)
- CoreDNS not running

---

### Connection Refused

**Symptom:**
```bash
$ curl my-service
curl: (7) Failed to connect to my-service port 80: Connection refused
```

**Meaning:** DNS works, but nothing listening on that port.

**Diagnosis:**
```bash
# Check Service has endpoints
kubectl get endpoints <service-name>

# Check Service ports
kubectl describe svc <service-name> | grep Port

# Check container is listening
kubectl logs <pod-name>
kubectl exec <pod-name> -- netstat -tuln
```

**Common fixes:**
- `port` vs `targetPort` mismatch in Service
- Container not listening on expected port

---

## 🚀 Minikube-Specific Issues

### Minikube Won't Start

**WSL2 (Windows):**
```bash
# Check Docker is running
docker ps

# If not, start Docker Desktop in Windows

# Then try again with explicit driver
minikube start --driver=docker
```

**Resource constraints:**
```bash
# Check Docker resources
docker info | grep -i memory

# Start with more resources
minikube delete
minikube start --memory=4096 --cpus=2 --disk-size=20g
```

---

### Ingress Not Working

**Symptom:** 404 or connection refused when accessing Ingress.

**Diagnosis:**
```bash
# Check Ingress controller is running
kubectl get pods -n ingress-nginx

# Check Ingress resource
kubectl get ingress
kubectl describe ingress <ingress-name>

# Check Service backends
kubectl get svc
kubectl get endpoints
```

**Common fixes:**
```bash
# Enable Ingress addon
minikube addons enable ingress

# Wait for controller to be Ready (30-60 seconds)
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Use Minikube tunnel (required for LoadBalancer)
minikube tunnel  # Run in separate terminal
```

---

## 📊 Resource Management

### Insufficient Resources

**Symptom:** Pods stuck in `Pending` with:
```
0/1 nodes available: insufficient cpu/memory
```

**Check current usage:**
```bash
kubectl describe node minikube | grep -A 10 "Allocated resources"
kubectl top nodes  # Requires metrics-server
kubectl top pods
```

**Solutions:**
1. **Reduce resource requests** in Pod/Deployment specs
2. **Increase Minikube resources:**
   ```bash
   minikube delete
   minikube start --memory=4096 --cpus=2
   ```
3. **Delete unused Pods/Deployments**

---

## 🔍 Debugging Tools

### Temporary Debug Pod

```bash
# Alpine with networking tools
kubectl run debug --rm -it --image=alpine -- sh

# Then inside:
apk add curl bind-tools
nslookup my-service
curl my-service
```

### BusyBox (minimal)
```bash
kubectl run debug --rm -it --image=busybox -- sh

# Test DNS
nslookup my-service

# Test connectivity
wget -O- my-service
```

### Curl image
```bash
kubectl run test --rm -it --image=curlimages/curl -- sh

# Test endpoints
curl my-service
curl my-service/api/health
```

---

## ⚙️ Configuration Issues

### ConfigMap Changes Not Reflected

**Issue:** Updated ConfigMap but Pod still shows old data.

**Cause:** ConfigMaps are mounted at Pod creation time.

**Fix:**
```bash
# Update ConfigMap
kubectl apply -f configmap.yaml

# Restart Pods (Day 1: delete and recreate)
kubectl delete pod <pod-name>
kubectl apply -f pod.yaml

# Day 2+: Rollout restart (Deployment)
kubectl rollout restart deployment <deployment-name>
```

---

### YAML Syntax Errors

**Symptom:**
```
error: error parsing manifest.yaml: error converting YAML to JSON
```

**Common causes:**
- Indentation errors (use spaces, not tabs)
- Missing colons
- Wrong nesting level

**Validate before applying:**
```bash
# Client-side validation
kubectl apply -f manifest.yaml --dry-run=client

# Or use linter
yamllint manifest.yaml
```

---

## 📚 Quick Reference

### Most Useful Commands

```bash
# 1. What's the status?
kubectl get all

# 2. Why is it failing?
kubectl describe pod <name>

# 3. What does the app say?
kubectl logs <name>

# 4. Is it a network issue?
kubectl get endpoints <service-name>

# 5. Can I access it?
kubectl port-forward pod/<name> 8080:80
```

---

## ❓ Still Stuck?

1. **Check day-specific troubleshooting:**
   - [Day 1](../day-1-foundation/troubleshooting.md)
   - [Day 2](../day-2-replication/troubleshooting.md)
   - [Day 3](../day-3-multitier/troubleshooting.md)

2. **Review official documentation:**
   - [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
   - [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
   - [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

3. **Open an issue:**
   - [GitHub Issues](https://github.com/the-byte-sized/kubernetes-capstone-labs/issues)
   - Include: `kubectl get pods`, `kubectl describe pod <name>`, `kubectl logs <name>`

---

**Back to:** [Main README](../README.md)
