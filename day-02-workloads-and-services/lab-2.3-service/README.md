# Lab 2.3: Service - Stable Endpoint

## 🎯 Goal

Create a **ClusterIP Service** to provide a **stable network endpoint** for the web Deployment, demonstrating:
- Service discovery via DNS
- Label-based Pod selection
- Endpoint management
- Port-forward for external access

**Key learning**: Services decouple consumers from ephemeral Pod IPs.

---

## 📚 Prerequisites

- ✅ Lab 2.2 completed (Deployment running)
- ✅ 3 web Pods running from Deployment
- ✅ Theory: Lezione 2 - Service: endpoint stabile, Selector e EndpointSlice

**Verify current state:**
```bash
kubectl get deployment web-deployment
kubectl get pods -l app=web
```

**Expected:** 3 Pods with `STATUS=Running`

---

## 🧪 Lab Steps

### Step 1: Observe the problem - Ephemeral Pod IPs

Get current Pod IPs:
```bash
kubectl get pods -o wide
```

**Example output:**
```
NAME                              READY   STATUS    RESTARTS   AGE   IP
web-deployment-7f8c9d5b6f-abc12   1/1     Running   0          10m   10.244.0.5
web-deployment-7f8c9d5b6f-def34   1/1     Running   0          10m   10.244.0.6
web-deployment-7f8c9d5b6f-ghi56   1/1     Running   0          10m   10.244.0.7
```

**Problem simulation:**
Delete one Pod and observe IP change:
```bash
kubectl delete pod web-deployment-7f8c9d5b6f-abc12
kubectl get pods -o wide
```

**New Pod gets a different IP:**
```
NAME                              READY   STATUS    RESTARTS   AGE   IP
web-deployment-7f8c9d5b6f-xyz99   1/1     Running   0          10s   10.244.0.8  # NEW IP!
web-deployment-7f8c9d5b6f-def34   1/1     Running   0          10m   10.244.0.6
web-deployment-7f8c9d5b6f-ghi56   1/1     Running   0          10m   10.244.0.7
```

**Conclusion:** Clients can't rely on Pod IPs (they change on recreate/rollout).

### Step 2: Create Service manifest

Create `web-service.yaml` (see file in this directory).

**Key sections:**
- `type: ClusterIP` → stable internal IP
- `selector` → matches Pods with `app=web, tier=frontend`
- `ports` → maps Service port to Pod port

### Step 3: Apply Service

```bash
kubectl apply -f web-service.yaml
```

**Expected output:**
```
service/web-service created
```

### Step 4: Inspect Service

```bash
kubectl get service web-service
```

**Expected output:**
```
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web-service   ClusterIP   10.96.123.45    <none>        80/TCP    30s
```

**Key observations:**
- **CLUSTER-IP**: stable IP (never changes)
- **TYPE**: ClusterIP (internal only)
- **PORT(S)**: 80/TCP (Service port)

Describe Service:
```bash
kubectl describe service web-service
```

**Expected output:**
```
Name:              web-service
Namespace:         default
Labels:            app=web
Selector:          app=web,tier=frontend
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.96.123.45
Port:              http  80/TCP
TargetPort:        80/TCP
Endpoints:         10.244.0.5:80,10.244.0.6:80,10.244.0.7:80  # Pod IPs!
Session Affinity:  None
Events:            <none>
```

**Key observation:** `Endpoints` shows 3 Pod IPs (matching the selector).

### Step 5: Verify Endpoints

Services use **Endpoints** to track backend Pods:

```bash
kubectl get endpoints web-service
```

**Expected output:**
```
NAME          ENDPOINTS                                 AGE
web-service   10.244.0.5:80,10.244.0.6:80,10.244.0.7:80   1m
```

**How it works:**
1. Service selector: `app=web, tier=frontend`
2. Kubernetes finds Pods matching labels
3. Adds Pod IPs to Endpoints list
4. kube-proxy configures routing rules (iptables/ipvs)

### Step 6: Test internal DNS resolution

Kubernetes provides internal DNS for Services:

**DNS format:** `<service-name>.<namespace>.svc.cluster.local`

Test DNS:
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
```

**Expected output:**
```
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   web-service.default.svc.cluster.local
Address: 10.96.123.45  # Service ClusterIP

pod "test-dns" deleted
```

**Try short name (same namespace):**
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
```

**Try FQDN:**
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service.default.svc.cluster.local
```

All should resolve to the **same ClusterIP** (10.96.123.45).

### Step 7: Test connectivity from inside cluster

Curl the Service from a temporary Pod:

```bash
kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://web-service
```

**Expected output:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</html>
pod "test-curl" deleted
```

**Key observation:** Used Service **name** (web-service), not IP!

### Step 8: Test load balancing

Service distributes traffic across all matching Pods.

Run multiple requests:
```bash
for i in {1..10}; do
  kubectl run test-curl-$i --image=curlimages/curl:8.11.1 --rm --restart=Never -- curl -s http://web-service | grep -i "welcome"
done
```

**Expected:** Requests distributed across 3 Pods (check logs).

Check which Pods received traffic:
```bash
kubectl logs -l app=web --tail=5
```

**Expected:** Access logs from multiple Pods.

### Step 9: Test port-forward for external access

**ClusterIP is internal only**. To access from your machine:

```bash
kubectl port-forward service/web-service 8080:80
```

**Expected output:**
```
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

**Keep terminal open.** In another terminal or browser:
```bash
curl http://localhost:8080
```

**Expected:** Nginx welcome page.

**Stop port-forward:** Ctrl+C in first terminal.

### Step 10: Observe endpoint updates on Pod changes

Scale Deployment:
```bash
kubectl scale deployment web-deployment --replicas=5
```

Check Endpoints immediately:
```bash
kubectl get endpoints web-service
```

**Expected:** 5 Pod IPs now (was 3).

**Example:**
```
NAME          ENDPOINTS
web-service   10.244.0.5:80,10.244.0.6:80,10.244.0.7:80,10.244.0.8:80,10.244.0.9:80
```

Scale back:
```bash
kubectl scale deployment web-deployment --replicas=3
kubectl get endpoints web-service
```

**Expected:** Back to 3 Pod IPs.

**Key observation:** Service **automatically updates** Endpoints when Pods change.

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] `kubectl get service web-service` shows `TYPE=ClusterIP` with a stable IP
- [ ] `kubectl get endpoints web-service` shows 3 Pod IPs (matching `kubectl get pods -o wide`)
- [ ] DNS resolves: `nslookup web-service` returns Service ClusterIP
- [ ] Connectivity works: `curl http://web-service` from inside cluster returns nginx page
- [ ] Port-forward works: `curl http://localhost:8080` (after `kubectl port-forward`)
- [ ] Endpoints update automatically when scaling Deployment (3 → 5 → 3)
- [ ] After deleting a Pod, Endpoints list updates to reflect new Pod IP

**If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## 🎓 Key Concepts (Lezione 2 References)

### **Service = Stable Endpoint over Ephemeral Pods**

```
Client request
  ↓
DNS: web-service → ClusterIP (10.96.123.45)
  ↓
kube-proxy: routes to one of Endpoints
  ↓
Pod IP (10.244.0.5 OR 10.244.0.6 OR 10.244.0.7)
  ↓
Nginx container
```

### **Label-based selection (dynamic):**

```yaml
# Service selector
selector:
  app: web
  tier: frontend

# Matches Pods with BOTH labels
# If Pod labels change or Pod dies, Endpoints update automatically
```

### **Why ClusterIP (not Pod IP)?**

| Accessing via | Pros | Cons |
|---------------|------|------|
| **Pod IP** | Direct | Ephemeral (changes on recreate/rollout) |
| **Service ClusterIP** | Stable, load-balanced | Internal only (need port-forward for external) |

### **Common mistake: Service without Endpoints**

If `kubectl get endpoints web-service` shows **no IPs**:
- **Cause 1:** Label mismatch (Service selector ≠ Pod labels)
- **Cause 2:** No Pods Ready (check `kubectl get pods`)
- **Cause 3:** Wrong namespace

**Debug:** Compare labels:
```bash
kubectl get service web-service -o yaml | grep -A3 selector
kubectl get pods --show-labels
```

---

## 🔗 Theory Mapping

From **Lezione 2**:

| Concept (slide) | Where in lab |
|-----------------|-------------|
| Service: endpoint stabile | ClusterIP (10.96.123.45) |
| Selector e EndpointSlice | `selector` in YAML → `kubectl get endpoints` |
| DNS interno e service discovery | `nslookup web-service` |
| Port-forward vs Service | `kubectl port-forward` for dev/debug only |
| Errore tipico: Service senza endpoint | Troubleshooting label mismatch |

---

## 🚀 Next Steps

You now have:
- ✅ Deployment managing 3 Pods
- ✅ Service providing stable endpoint
- ✅ DNS resolution working

But it's still **single-tier**. Let's build a **multi-tier application**:
- Web tier (current)
- API tier (new)
- Web calls API via Service name

**Continue to**: [Lab 2.4 - Multi-Tier Capstone](../lab-2.4-multi-tier-capstone/README.md)

---

## 📚 Resources

- [Kubernetes Service Docs](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Service ClusterIP](https://kubernetes.io/docs/concepts/services-networking/service/#type-clusterip)
- Lezione 2: Sezione "Networking di base"
