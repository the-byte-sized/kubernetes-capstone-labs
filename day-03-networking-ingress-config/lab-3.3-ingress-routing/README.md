# Lab 3.3: Ingress L7 Routing (Capstone v2)

## 🎯 Goal

Expose the capstone **web** and **api** components via a single HTTP entry point using **Ingress** with **path-based routing**.

**Key learning**: Ingress provides **Layer 7 (HTTP)** routing on top of Services. It uses host/path rules to forward traffic to the correct backend Service.

- `/` → `web-service` (frontend)
- `/api` → `api-service` (backend)

---

## 📚 Prerequisites

✅ Lab 3.2 completed: Ingress controller (ingress-nginx) is **Running** and **Ready**.

```bash
kubectl get pods -n ingress-nginx
```

**Expected:**
```
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-...                1/1     Running   0          5m
```

✅ Capstone Services exist and work internally (from Day 2 + Lab 3.1):

```bash
kubectl get svc web-service api-service
kubectl run test-api --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://api-service/get
```

**Expected:**
- `web-service` and `api-service` are ClusterIP Services.
- `curl http://api-service/get` returns JSON.

✅ Minikube IP reachable from your machine:

```bash
minikube ip
```

**Expected:** An IP address like `192.168.49.2`.

---

## 🏗️ Target Architecture

```
Client (curl/browser)
        |
        v
┌────────────────────────────────────────┐
│ Ingress (capstone-ingress)             │  Host: capstone.local
│  - /    → web-service                  │  Path rules
│  - /api → api-service                  │
└───────────────┬────────────────────────┘
                |
        ┌───────┴─────────┐
        v                 v
┌──────────────┐   ┌──────────────┐
│ web-service  │   │ api-service  │
└──────┬───────┘   └──────┬───────┘
       |                  |
  ┌────▼────┐        ┌────▼────┐
  │ web Pod │ ...    │ api Pod │ ...
  └─────────┘        └─────────┘
```

---

## 🧪 Lab Steps

### Step 1: Create Ingress manifest

Use the provided `capstone-ingress.yaml` manifest in this directory, or create your own:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: capstone-ingress
  labels:
    app: capstone
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: capstone.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

**Key points:**
- `ingressClassName: nginx` → uses the ingress-nginx controller from Lab 3.2
- `host: capstone.local` → virtual host for routing
- Two path rules: `/` → web, `/api` → api
- `rewrite-target` annotation removes path prefix when forwarding to backend

---

### Step 2: Apply the Ingress

Apply the manifest in the same namespace as your Services (default or capstone):

```bash
kubectl apply -f capstone-ingress.yaml
```

**Expected output:**
```
ingress.networking.k8s.io/capstone-ingress created
```

Verify:

```bash
kubectl get ingress
```

**Expected:**
```
NAME               CLASS   HOSTS           ADDRESS        PORTS   AGE
capstone-ingress   nginx   capstone.local  192.168.49.2   80      10s
```

> `ADDRESS` often shows the Minikube node IP. If empty, give it a few seconds and re-check.

---

### Step 3: Inspect Ingress details

Describe the Ingress to see rules and status:

```bash
kubectl describe ingress capstone-ingress
```

**Look for:**
- `Rules:` section → host `capstone.local`, paths `/` and `/api`
- `Backends:` → `web-service:80`, `api-service:80`
- `Events:` → any errors (e.g., missing IngressClass, backend not found)

If there are warnings or errors, note them; they are key for debugging.

---

### Step 4: Configure local DNS (optional but convenient)

Add an entry to your `/etc/hosts` file (requires sudo/admin rights):

```bash
MINIKUBE_IP=$(minikube ip)

echo "$MINIKUBE_IP capstone.local" | sudo tee -a /etc/hosts
```

Now `capstone.local` will resolve to the Minikube IP from your machine.

> If you cannot or do not want to edit `/etc/hosts`, you can always use `curl -H "Host: capstone.local" http://<MINIKUBE_IP>/...` in the next steps.

---

### Step 5: Test web routing (`/` → web-service)

Test using Minikube IP and Host header:

```bash
MINIKUBE_IP=$(minikube ip)

curl -H "Host: capstone.local" http://$MINIKUBE_IP/
```

**Expected:**
- Response from web tier (nginx), e.g., HTML or a custom page.

If using `/etc/hosts`, you can also test:

```bash
curl http://capstone.local/
```

---

### Step 6: Test API routing (`/api` → api-service)

Test `/api` path:

```bash
MINIKUBE_IP=$(minikube ip)

curl -H "Host: capstone.local" http://$MINIKUBE_IP/api/get
```

**Expected:** JSON from httpbin (api tier), similar to:

```json
{
  "args": {},
  "headers": {
    "Host": "capstone.local",
    ...
  },
  "url": "http://capstone.local/api/get"
}
```

If using `/etc/hosts`:

```bash
curl http://capstone.local/api/get
```

**Key observation:**
- Same IP and host, different path → different backend Service.

---

### Step 7: Observe Ingress logs

Check what the controller sees when you send requests:

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') --tail=50
```

**Look for:**
- Entries showing `"GET /"` and `"GET /api/get"`
- Backend selection for web vs api

This is useful when troubleshooting 404 or 5xx issues.

---

### Step 8: Validate fallback behavior (404)

Call an unknown path:

```bash
MINIKUBE_IP=$(minikube ip)

curl -H "Host: capstone.local" http://$MINIKUBE_IP/unknown
```

**Expected:**
- 404 from ingress-nginx (default backend), not from your web/api.

This confirms path-based routing behavior.

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `capstone-ingress` exists and shows HOST `capstone.local` and non-empty ADDRESS
- [ ] `curl -H "Host: capstone.local" http://<MINIKUBE_IP>/` returns web content
- [ ] `curl -H "Host: capstone.local" http://<MINIKUBE_IP>/api/get` returns JSON from httpbin
- [ ] Unknown paths (e.g., `/foo`) return 404 from Ingress
- [ ] Ingress controller logs show requests routed to web and api

If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

---

## 🎓 Key Concepts

### Ingress is L7 routing, not transport

- **Service (ClusterIP, NodePort)**: Handles **transport** (IP:port, TCP/UDP).
- **Ingress**: Handles **HTTP routing** (host, path, TLS).

Ingress **uses** Services as backends; it does not replace them.

### Path-based routing pattern

Simplest useful pattern for capstone:

```yaml
rules:
- host: capstone.local
  http:
    paths:
    - path: /
      pathType: Prefix
      backend:
        service:
          name: web-service
          port:
            number: 80
    - path: /api
      pathType: Prefix
      backend:
        service:
          name: api-service
          port:
            number: 80
```

- Requests to `/` go to `web-service`.
- Requests to `/api` go to `api-service`.

### Typical failure modes

- **404 from Ingress**: Rule not matched (host/path mismatch) or backend Service not configured correctly.
- **Timeout**: Rule matched, but backend Service has no endpoints (Pods not Ready or selector mismatch).

---

## 🔗 Theory Mapping (Lezione 3)

| Slide Concept | Where in Lab |
|---------------|-------------|
| Ingress: governance HTTP L7 | Overall goal & routing steps |
| Routing per path | Step 1, Step 5-6 ("/" vs "/api") |
| Sintomo: Ingress risponde 404 | Step 8 + TROUBLESHOOTING |
| Ingress dipende da Service e endpoints | Prerequisites + failure modes |
| Osservabilità: risorsa, Service, log controller | Steps 3, 7 |

---

## 📚 Official References

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress - Path types](https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types)
- [Ingress - Host based routing](https://kubernetes.io/docs/concepts/services-networking/ingress/#name-based-virtual-hosting)

---

**Previous**: [Lab 3.2 - Ingress Controller Setup](../lab-3.2-ingress-setup/README.md)  
**Next**: [Lab 3.4 - ConfigMap & Secret](../lab-3.4-configmap-secret/README.md)
