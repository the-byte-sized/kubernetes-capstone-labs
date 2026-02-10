# Lab 3.3 Troubleshooting: Ingress L7 Routing

## Issue 1: Ingress returns 404 for all paths

### Symptom

```bash
MINIKUBE_IP=$(minikube ip)

curl -H "Host: capstone.local" http://$MINIKUBE_IP/
# or
curl -H "Host: capstone.local" http://$MINIKUBE_IP/api/get
```

**Output:**
```
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
...
</body>
</html>
```

### Root Causes & Fixes

#### Cause 1.1: Host header mismatch

Ingress rule expects `host: capstone.local`.

**Verify:**
```bash
kubectl get ingress capstone-ingress -o yaml | grep -A3 host:
```

**Fix:**

- If you cannot edit `/etc/hosts`, always send the correct Host header:

```bash
MINIKUBE_IP=$(minikube ip)

curl -H "Host: capstone.local" http://$MINIKUBE_IP/
```

- If you changed the host in YAML, use that host instead of `capstone.local`.

---

#### Cause 1.2: Path not matching

**Verify:**
```bash
kubectl describe ingress capstone-ingress
```

**Look for paths:**
```
Paths:
  /       web-service:80 (Prefix)
  /api    api-service:80 (Prefix)
```

**Fix:**

- Ensure you are calling exactly `/` or `/api` (or compatible patterns).
- For example, calling `/v1/api` will not match `/api` with `pathType: Prefix` as expected.

Test with explicit paths:

```bash
curl -H "Host: capstone.local" http://$MINIKUBE_IP/
curl -H "Host: capstone.local" http://$MINIKUBE_IP/api/get
```

If using regex-style paths or `rewrite-target`, ensure the patterns are correct.

---

#### Cause 1.3: IngressClass mismatch

**Symptom:** Ingress exists, but controller ignores it.

**Verify:**

```bash
kubectl get ingress capstone-ingress -o jsonpath='{.spec.ingressClassName}'
kubectl get ingressclass
```

**Expected:** IngressClass referenced by `ingressClassName` exists and is managed by `k8s.io/ingress-nginx`.

**Fix Options:**

1. Use the existing IngressClass name (common in Minikube: `nginx`):

```yaml
spec:
  ingressClassName: nginx
```

2. If no IngressClass is set and your cluster has a default, you can remove `ingressClassName`.

Apply changes:

```bash
kubectl apply -f capstone-ingress.yaml
```

Then check Events:

```bash
kubectl describe ingress capstone-ingress
```

---

## Issue 2: Ingress times out (504/timeout)

### Symptom

```bash
curl -H "Host: capstone.local" http://$MINIKUBE_IP/api/get
```

**Output:**
```
upstream timed out (110: Connection timed out)
```

Or curl shows timeout.

### Root Causes & Fixes

#### Cause 2.1: Backend Service has no endpoints

**Verify:**

```bash
kubectl get svc api-service
kubectl get endpoints api-service
kubectl get endpointslice -l kubernetes.io/service-name=api-service
```

**If endpoints are empty:**
```
NAME          ENDPOINTS   AGE
api-service   <none>      10m
```

**Fix:**

Follow the same pattern as Lab 3.1 troubleshooting:
- Check Service selector vs Pod labels.
- Check Pods are Ready.

```bash
kubectl get svc api-service -o jsonpath='{.spec.selector}' | jq
kubectl get pods -l app=api --show-labels
kubectl describe pod -l app=api
```

Update Service selector or fix probes so Pods become Ready.

---

#### Cause 2.2: Wrong port in Ingress backend

**Verify:**

```bash
kubectl describe ingress capstone-ingress | grep -A2 'Backends'
```

**Expected:**
```
Backend:  web-service:80 (10.96.x.x:80)
Backend:  api-service:80 (10.96.y.y:80)
```

Check Service ports:

```bash
kubectl describe svc api-service
kubectl describe svc web-service
```

**Fix:**

Ensure Ingress backend `port.number` matches Service `port`, not `targetPort`.

Example:

```yaml
backend:
  service:
    name: api-service
    port:
      number: 80  # Must equal .spec.ports[0].port in Service
```

If Service port is different (e.g., 8080), adjust accordingly.

Apply updated Ingress:

```bash
kubectl apply -f capstone-ingress.yaml
```

---

## Issue 3: Ingress responds with web content for `/api`

### Symptom

```bash
curl -H "Host: capstone.local" http://$MINIKUBE_IP/api/get
```

**Output:** HTML page from web component instead of JSON from API.

### Root Causes & Fixes

Most likely the path rule for `/api` is not matching correctly or order is incorrect.

#### Cause 3.1: Overlapping paths

**Verify:**

```bash
kubectl describe ingress capstone-ingress
```

If you have:

```yaml
- path: /
  pathType: Prefix
  backend: web-service
- path: /api
  pathType: Prefix
  backend: api-service
```

With `Prefix`, `/api` should still match the `/api` rule, but some misconfigurations or extra rules can alter behavior.

**Fix:**

Use more explicit order and patterns if needed (or temporarily remove extra rules):

```yaml
paths:
- path: /api
  pathType: Prefix
  backend:
    service:
      name: api-service
      port:
        number: 80
- path: /
  pathType: Prefix
  backend:
    service:
      name: web-service
      port:
        number: 80
```

Re-apply and test.

---

## Issue 4: ADDRESS column empty for Ingress

### Symptom

```bash
kubectl get ingress
```

**Output:**
```
NAME               CLASS   HOSTS           ADDRESS   PORTS   AGE
capstone-ingress   nginx   capstone.local           80      2m
```

### Root Causes & Fixes

This can be transient; controller might not have updated status yet.

1. Wait a few seconds and re-check:

```bash
kubectl get ingress
```

2. Ensure controller is Running and Ready:

```bash
kubectl get pods -n ingress-nginx
```

3. Check controller logs:

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') --tail=50
```

If the controller is healthy, lack of ADDRESS is often cosmetic in local clusters. You can still use `minikube ip` + Host header.

---

## Issue 5: Ingress works internally but not from host

### Symptom

- `curl` from a Pod inside the cluster to Ingress Service works.
- `curl` from your laptop to `http://<MINIKUBE_IP>/...` fails.

### Root Causes & Fixes

1. **Local firewall or VPN** blocking traffic
   - Ensure your OS firewall or corporate VPN is not blocking the Minikube IP.

2. **Wrong IP used**
   - Always use `minikube ip` to get the correct IP.

3. **Host header missing**
   - If you rely on Host-based rules, always set the header:

```bash
curl -H "Host: capstone.local" http://$(minikube ip)/
```

---

## Quick Diagnostic Checklist

Use this checklist when Ingress misbehaves:

```bash
# 1. Ingress resource exists?
kubectl get ingress capstone-ingress

# 2. Ingress details correct?
kubectl describe ingress capstone-ingress

# 3. Ingress controller Running and Ready?
kubectl get pods -n ingress-nginx

# 4. Backend Services exist?
kubectl get svc web-service api-service

# 5. Backend endpoints populated?
kubectl get endpoints web-service api-service
kubectl get endpointslice -l kubernetes.io/service-name=web-service
kubectl get endpointslice -l kubernetes.io/service-name=api-service

# 6. Test from inside cluster
kubectl run test-ingress -n default --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- \
  curl -H "Host: capstone.local" http://<INGRESS-SERVICE-IP>/

# 7. Inspect controller logs
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') --tail=50
```

---

## Additional Resources

- [Ingress Troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/#debugging-ingress)
- [Ingress NGINX - FAQ](https://kubernetes.github.io/ingress-nginx/troubleshooting/)

---

**Back to**: [Lab 3.3 README](./README.md)
