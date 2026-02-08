# Lab 2.3 Troubleshooting Guide

## Common Errors & Solutions

---

### ❌ Error 1: Service created but no Endpoints

**Symptom:**
```bash
kubectl get service web-service
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web-service   ClusterIP   10.96.123.45    <none>        80/TCP    1m

kubectl get endpoints web-service
NAME          ENDPOINTS   AGE
web-service   <none>      1m
```

**Diagnosis:**

Compare Service selector with Pod labels:
```bash
# Service selector
kubectl get service web-service -o yaml | grep -A3 selector

# Pod labels
kubectl get pods --show-labels
```

**Cause 1: Label mismatch**

Service selector:
```yaml
selector:
  app: web
  tier: frontend
```

But Pods have:
```
app=web,tier=backend  # WRONG!
```

**Solution:** Fix labels in Deployment template:
```yaml
template:
  metadata:
    labels:
      app: web
      tier: frontend  # Must match Service selector
```

Apply:
```bash
kubectl apply -f web-deployment.yaml
kubectl rollout restart deployment web-deployment
```

Verify:
```bash
kubectl get endpoints web-service
```

**Cause 2: No Pods Ready**

```bash
kubectl get pods
NAME                              READY   STATUS             RESTARTS   AGE
web-deployment-7f8c9d5b6f-abc12   0/1     CrashLoopBackOff   5          5m
```

**Solution:** Fix Pod issues first (see Lab 2.1/2.2 troubleshooting), then Endpoints will populate.

**Cause 3: Wrong namespace**

Service in `task-tracker` namespace, but checking in `default`:

```bash
kubectl get endpoints web-service -n task-tracker
```

Or set context:
```bash
kubectl config set-context --current --namespace=task-tracker
```

---

### ❌ Error 2: DNS resolution fails

**Symptom:**
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
Server:         10.96.0.10
Address:        10.96.0.10:53

** server can't find web-service: NXDOMAIN
```

**Diagnosis:**

Check CoreDNS status:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Expected:** 1-2 Pods Running.

**Cause 1: CoreDNS not running**

```bash
NAME                       READY   STATUS    RESTARTS   AGE
coredns-abc123             0/1     Pending   0          10m
```

**Solution (Minikube):**
```bash
minikube addons enable dns
minikube addons list | grep dns
```

**Cause 2: Wrong DNS name format**

If Service is in `task-tracker` namespace, but you're in `default`:

```bash
# From default namespace, use FQDN:
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service.task-tracker.svc.cluster.local
```

Or switch to correct namespace:
```bash
kubectl config set-context --current --namespace=task-tracker
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
```

**Cause 3: Service doesn't exist**

```bash
kubectl get service web-service
Error from server (NotFound): services "web-service" not found
```

**Solution:**
```bash
kubectl apply -f web-service.yaml
```

---

### ❌ Error 3: curl from inside cluster fails

**Symptom:**
```bash
kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://web-service
curl: (7) Failed to connect to web-service port 80: Connection refused
```

**Diagnosis:**

Check Endpoints:
```bash
kubectl get endpoints web-service
```

**If Endpoints empty:** See Error 1 (label mismatch).

**If Endpoints exist:** Check Pod port.

**Cause: Port mismatch**

Service `targetPort` doesn't match Pod container port:

Service:
```yaml
ports:
- port: 80
  targetPort: 8080  # WRONG if container listens on 80
```

Pod:
```yaml
containers:
- name: nginx
  ports:
  - containerPort: 80  # Actual port
```

**Solution:** Fix Service `targetPort`:
```yaml
ports:
- port: 80
  targetPort: 80  # Match container port
```

Apply:
```bash
kubectl apply -f web-service.yaml
```

---

### ❌ Error 4: port-forward fails

**Symptom:**
```bash
kubectl port-forward service/web-service 8080:80
Error from server (NotFound): services "web-service" not found
```

**Cause 1: Wrong namespace**

**Solution:**
```bash
kubectl port-forward service/web-service 8080:80 -n task-tracker
```

Or set context:
```bash
kubectl config set-context --current --namespace=task-tracker
kubectl port-forward service/web-service 8080:80
```

**Cause 2: Port already in use**

```bash
kubectl port-forward service/web-service 8080:80
Unable to listen on port 8080: Listeners failed to create with the following errors: [unable to create listener: Error listen tcp 127.0.0.1:8080: bind: address already in use]
```

**Solution:** Use different local port:
```bash
kubectl port-forward service/web-service 8081:80
```

Or kill process using port 8080:
```bash
# Linux/macOS
lsof -ti:8080 | xargs kill -9

# Windows
netstat -ano | findstr :8080
taskkill /PID <PID> /F
```

---

### ❌ Error 5: Endpoints show Pod IPs but curl times out

**Symptom:**
```bash
kubectl get endpoints web-service
NAME          ENDPOINTS
web-service   10.244.0.5:80,10.244.0.6:80

kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://web-service
curl: (28) Failed to connect to web-service port 80 after 130000 ms: Timeout was reached
```

**Diagnosis:**

Check if Pods are actually Ready:
```bash
kubectl get pods -l app=web
```

**Cause: Pods not Ready (readiness probe failing)**

```
NAME                              READY   STATUS    RESTARTS   AGE
web-deployment-7f8c9d5b6f-abc12   0/1     Running   0          5m
```

**Explanation:** Pods appear in Endpoints only if **Ready**.

Check readiness probe:
```bash
kubectl describe pod web-deployment-7f8c9d5b6f-abc12
Events:
  Warning  Unhealthy  2m  kubelet  Readiness probe failed: Get "http://10.244.0.5:80/": dial tcp 10.244.0.5:80: connect: connection refused
```

**Solution:** Fix readiness probe or application startup.

Temporary workaround (for testing):
```yaml
# Remove readiness probe in Deployment
# readinessProbe:
#   httpGet:
#     path: /
#     port: 80
```

Apply:
```bash
kubectl apply -f web-deployment.yaml
```

---

### ❌ Error 6: Service ClusterIP not accessible from host

**Symptom:**
```bash
# From your laptop
curl http://10.96.123.45
curl: (7) Failed to connect to 10.96.123.45 port 80: Connection refused
```

**Cause:** ClusterIP is **internal only** (not routable from outside cluster).

**Expected behavior!** This is by design.

**Solutions:**

1. **Use port-forward (dev/debug):**
   ```bash
   kubectl port-forward service/web-service 8080:80
   curl http://localhost:8080
   ```

2. **Use NodePort Service (exposes on node IP):**
   ```yaml
   type: NodePort  # Instead of ClusterIP
   ```

3. **Use LoadBalancer Service (cloud only):**
   ```yaml
   type: LoadBalancer
   ```

4. **Use Ingress (Lab 2.4 or Day 3):**
   HTTP/HTTPS routing with hostname-based rules.

---

## Debugging Workflow for Services

```
1. kubectl get service <name>
   → Does Service exist? ClusterIP assigned?

2. kubectl get endpoints <name>
   → Are there Pod IPs listed?

3. kubectl get pods --show-labels
   → Do Pod labels match Service selector?

4. kubectl describe service <name>
   → Check Selector, Endpoints, Events

5. nslookup <service-name>
   → Does DNS resolve to ClusterIP?

6. curl http://<service-name>
   → Does connectivity work from inside cluster?
```

**Remember (Lezione 2):**
- **No Endpoints** → label mismatch or no Ready Pods
- **DNS fails** → CoreDNS issue or wrong namespace
- **Connection refused** → port mismatch or Pod not Ready
- **ClusterIP not routable from host** → expected! Use port-forward

---

## Need More Help?

1. Compare labels systematically:
   ```bash
   echo "=== Service Selector ==="
   kubectl get service web-service -o jsonpath='{.spec.selector}' | jq
   echo "
=== Pod Labels ==="
   kubectl get pods -o jsonpath='{.items[*].metadata.labels}' | jq
   ```

2. Check kube-proxy (routing):
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-proxy
   ```

3. Test direct Pod IP (bypass Service):
   ```bash
   POD_IP=$(kubectl get pod <pod-name> -o jsonpath='{.status.podIP}')
   kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://$POD_IP:80
   ```

4. Restart CoreDNS:
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

---

**Back to lab**: [Lab 2.3 README](./README.md)
