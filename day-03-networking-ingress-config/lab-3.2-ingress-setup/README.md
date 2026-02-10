# Lab 3.2: Ingress Controller Setup (Minikube)

## 🎯 Goal

Enable the **Ingress controller** in Minikube and verify it is **Running** and **Ready** to process Ingress resources.

**Key learning**: An Ingress resource **does nothing** without a controller. Today, the controller is provided by the Minikube `ingress` addon (ingress-nginx).

---

## 📚 Prerequisites

✅ Minikube cluster running

```bash
minikube status
```

**Expected (example):**
```
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

✅ kubectl context points to Minikube

```bash
kubectl config current-context
```

**Expected:** `minikube`

✅ Capstone workloads from Day 2 are present (web + api + Services)

```bash
kubectl get ns
kubectl get deployment,svc
```

**Expected:** Deployments and Services created in previous labs (e.g., `web-deployment`, `api-deployment`, `web-service`, `api-service`).

---

## 🧪 Lab Steps

### Step 1: Check Ingress addon status

List Minikube addons:

```bash
minikube addons list | grep ingress
```

**Expected (before enabling):**
```
ingress                   disabled
```

If already enabled:
```
ingress                   enabled
```

> If `ingress` risulta già **enabled**, puoi saltare allo Step 3.

---

### Step 2: Enable Ingress addon

Enable the Ingress addon (this deploys ingress-nginx controller):

```bash
minikube addons enable ingress
```

**Expected output (excerpt):**
```
🔎  Verifying ingress addon...
🌟  The 'ingress' addon is enabled
```

This creates resources in the `ingress-nginx` namespace.

---

### Step 3: Verify Ingress controller Pods

List Pods in `ingress-nginx` namespace:

```bash
kubectl get pods -n ingress-nginx
```

**Expected (example):**
```
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-847c8c99d7-abc12   1/1     Running   0          1m
```

**Key checks:**
- At least one `ingress-nginx-controller` Pod
- STATUS = `Running`
- READY = `1/1`

If Pods are `Pending` or `CrashLoopBackOff`, see TROUBLESHOOTING.

---

### Step 4: Inspect controller Pod details (optional)

Describe the controller Pod to understand what runs:

```bash
kubectl describe pod -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
```

**Look at:**
- `Containers:` section → image (nginx-based Ingress controller)
- `Events:` → any warnings or errors (resource constraints, scheduling issues)

This is useful later when debugging Ingress behavior.

---

### Step 5: Check IngressClass (concept)

List IngressClasses:

```bash
kubectl get ingressclass
```

**Expected (example):
```
NAME    CONTROLLER                      PARAMETERS   AGE
nginx   k8s.io/ingress-nginx            <none>       1m
```

This tells us:
- There is an IngressClass named `nginx`
- It is handled by the `k8s.io/ingress-nginx` controller

In this lab we rely on the default configuration; we do **not** need to customize IngressClass.

---

### Step 6: Sanity check: controller logs

Read a few lines from the controller logs:

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') --tail=20
```

**Expected:**
- No crash loops
- Logs mention watching Ingress resources, updating configuration

You do **not** need to understand every log line; this is a quick check that the controller is alive and processing.

---

## ✅ Verification Checklist

**Pass criteria (all must be true):**

- [ ] `minikube addons list` shows `ingress` as **enabled**
- [ ] At least one `ingress-nginx-controller` Pod is `Running` and `Ready 1/1`
- [ ] `kubectl get ingressclass` returns at least one class (e.g., `nginx`)
- [ ] Controller logs show normal startup (no continuous errors)

If any check fails, go to [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

---

## 🎓 Key Concepts

### Ingress resource vs Ingress controller

- **Ingress (resource)**: Declarative object describing HTTP/HTTPS routing (host/path → Service).
- **Ingress controller**: Component that **implements** those rules (e.g., ingress-nginx, Traefik, HAProxy).

**Without a controller**, creating an Ingress resource is like writing firewall rules on a post-it: they exist on paper, but no one applies them.

### Why an addon in Minikube?

- Minikube is a single-node learning cluster.
- The `ingress` addon provides a ready-to-use ingress-nginx controller.
- In real clusters (cloud, on-prem), the controller is usually installed via Helm or operator.

### Where it fits in the three-layer model

```
┌─────────────────────────────────────────┐
│ Layer 3: Ingress (L7 HTTP/HTTPS)        │ ← You enabled this today
├─────────────────────────────────────────┤
│ Layer 2: Service (ClusterIP, NodePort)  │ ← Day 2 focus
├─────────────────────────────────────────┤
│ Layer 1: Pod Network (CNI, Pod IPs)     │ ← Underlying connectivity
└─────────────────────────────────────────┘
```

From now on, when you create an Ingress resource, the controller will translate those rules into nginx configuration and start routing external HTTP traffic into the cluster.

---

## 🔗 Theory Mapping (Lezione 3)

| Slide Concept | Where in Lab |
|---------------|-------------|
| Ingress: perche serve davvero | Goal & Key Concepts sections |
| Ingress resource vs Ingress Controller | Step 2-3 + Key Concepts |
| IngressClass - chi si prende carico | Step 5 (get ingressclass) |
| Errori comuni: controller non presente | TROUBLESHOOTING Issue 1 |

---

## 📚 Official References

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-controllers)
- [Minikube Ingress Addon](https://minikube.sigs.k8s.io/docs/handbook/ingress/)

---

**Previous**: [Lab 3.1 - DNS & Service Discovery](../lab-3.1-dns-service-discovery/README.md)  
**Next**: [Lab 3.3 - Ingress L7 Routing](../lab-3.3-ingress-routing/README.md)
