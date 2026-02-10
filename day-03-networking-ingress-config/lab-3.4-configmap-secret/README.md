# Lab 3.4: ConfigMap & Secret (External Configuration)

## 🎯 Goal

Externalize configuration for the capstone:
- Use a **ConfigMap** to provide configuration to the **web** component.
- Use a **Secret** to inject sensitive data (e.g., API token) into the **api** component via environment variable.

**Key learning**: Configuration lives **outside** the container image. Pods become immutable; config changes by updating Kubernetes objects, not rebuilding images.

---

## 📚 Prerequisites

✅ Capstone deployments and services running:
- `web-deployment` (frontend, nginx)
- `api-deployment` (backend, httpbin or similar)
- `web-service`, `api-service`

```bash
kubectl get deployment web-deployment api-deployment
kubectl get svc web-service api-service
kubectl get pods -o wide
```

**Expected:**
- Deployments READY (web 3/3, api 2/2)
- Services ClusterIP with endpoints populated

---

## 🧪 Part A – ConfigMap for web

### Step A1: Create ConfigMap with a simple message

Use the provided `web-config.yaml` manifest in this directory:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
  labels:
    app: web
    tier: frontend
data:
  message: "Capstone Day 3 - ConfigMap OK"
```

Apply:

```bash
kubectl apply -f web-config.yaml
```

**Expected:**
```
configmap/web-config created
```

Verify:

```bash
kubectl get configmap web-config
kubectl describe configmap web-config
```

---

### Step A2: Mount ConfigMap into web Pod

We will mount the `message` key as a file inside the web container.

Use the provided `web-deployment-with-config.yaml` manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
      tier: frontend
  template:
    metadata:
      labels:
        app: web
        tier: frontend
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: web-config-volume
          mountPath: /etc/web-config
      volumes:
      - name: web-config-volume
        configMap:
          name: web-config
```

> This mounts the entire ConfigMap under `/etc/web-config`. The `message` key will be a file `/etc/web-config/message`.

Apply updated Deployment:

```bash
kubectl apply -f web-deployment-with-config.yaml
kubectl rollout status deployment web-deployment
```

**Expected:**
- New Pods created and become Ready.

---

### Step A3: Verify ConfigMap is mounted and readable

Get one web Pod name and inspect:

```bash
WEB_POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $WEB_POD | grep -A5 "Volumes"
kubectl exec $WEB_POD -- ls -l /etc/web-config
kubectl exec $WEB_POD -- cat /etc/web-config/message
```

**Expected:**
- `web-config` volume mounted at `/etc/web-config`.
- File `message` exists.
- Content: `Capstone Day 3 - ConfigMap OK`.

At this point, the web component can read configuration from the filesystem rather than from hardcoded values.

---

## 🧪 Part B – Secret for api (env var)

### Step B1: Create Secret with API token

Use the provided `api-secret.yaml` manifest:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-secret
  labels:
    app: api
    tier: backend
type: Opaque
stringData:
  API_TOKEN: "demo-token-123"
```

Apply:

```bash
kubectl apply -f api-secret.yaml
```

**Expected:**
```
secret/api-secret created
```

Verify:

```bash
kubectl get secret api-secret
kubectl describe secret api-secret
```

> `stringData` is convenient for manifests; Kubernetes stores the actual value in `data` (base64 encoded).

---

### Step B2: Inject Secret as env var into api Pod

Use the provided `api-deployment-with-secret.yaml` manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      tier: backend
  template:
    metadata:
      labels:
        app: api
        tier: backend
    spec:
      containers:
      - name: httpbin
        image: kennethreitz/httpbin:latest
        ports:
        - containerPort: 80
        env:
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: api-secret
              key: API_TOKEN
```

Apply updated Deployment:

```bash
kubectl apply -f api-deployment-with-secret.yaml
kubectl rollout status deployment api-deployment
```

**Expected:**
- New api Pods created and Ready.

---

### Step B3: Verify env var from Secret

Get one api Pod and inspect env:

```bash
API_POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $API_POD | grep -A5 "Environment"

kubectl exec $API_POD -- printenv | grep API_TOKEN
```

**Expected:**
- `Environment` section shows `API_TOKEN` from `api-secret`.
- `printenv` shows `API_TOKEN=demo-token-123`.

---

## ✅ Verification Checklist

**Pass criteria:**

- [ ] ConfigMap `web-config` exists and contains key `message`.
- [ ] Web Pods mount `/etc/web-config` and file `/etc/web-config/message` exists.
- [ ] Secret `api-secret` exists and contains key `API_TOKEN`.
- [ ] Api Pods have env var `API_TOKEN` with expected value.
- [ ] No `FailedMount` or `CreateContainerConfigError` events on web/api Pods.

If any check fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

---

## 🎓 Key Concepts

### ConfigMap vs Secret

- **ConfigMap**: Non-sensitive config (feature flags, messages, URLs without credentials).
- **Secret**: Sensitive config (passwords, tokens, keys).

**Rule of thumb**: *"If it's sensitive, it's not ConfigMap."*

### Two main consumption patterns

1. **As environment variables**
   - Simple to use in many apps.
   - Good for small sets of values.

2. **As files via volumes**
   - Useful when app expects config files.
   - Good for larger or structured config.

In this lab:
- Web: ConfigMap → volume → file.
- Api: Secret → env var.

### Updating configuration – expectations

Changing ConfigMap/Secret does **not** automatically restart Pods.

- For config via env vars: Pods need restart/rollout to pick up new values.
- For config via volume-mounted files: updates are reflected on disk, but app must re-read files.

Kubernetes gives you the **mechanism**, not application behavior.

---

## 🔗 Theory Mapping (Lezione 3)

| Slide Concept | Where in Lab |
|---------------|-------------|
| Config esterna: ConfigMap/Secret | Overall goal |
| ConfigMap – cosa contiene / non contiene | Part A (web-config) |
| Secret – non sicurezza assoluta | Part B (api-secret) |
| Due modi di consumare config: env e file | A2 (volume) + B2 (env) |
| Errore tipico: "config c'è ma app non la vede" | TROUBLESHOOTING checks |
| Aggiornare config: comportamenti realistici | Key Concepts (updating config) |

---

## 📚 Official References

- [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Configure Pods using ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Distribute Credentials Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)

---

**Previous**: [Lab 3.3 - Ingress L7 Routing](../lab-3.3-ingress-routing/README.md)  
**Next**: [Lab 3.5 - Probes & Endpoints](../lab-3.5-probes-endpoints/README.md)
