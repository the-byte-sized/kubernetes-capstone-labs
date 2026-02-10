# NetworkPolicy (Advanced Topic)

⚠️ **Not Required for Day 4 Core Lab**  
This is optional advanced material for students who finish early or want to explore further.

---

## What is NetworkPolicy?

NetworkPolicy is a Kubernetes resource that controls traffic flow between Pods at the IP/port level.

**Think of it as:** A firewall for Pod-to-Pod communication

**Default behavior:** In most Kubernetes clusters, all Pods can talk to all Pods (no restrictions)

**With NetworkPolicy:** You define explicit allow rules; everything else is denied

---

## Prerequisites

⚠️ **Critical:** NetworkPolicy requires a CNI (Container Network Interface) plugin that supports it.

**Minikube default (bridge CNI):** Does **NOT** support NetworkPolicy  
**Supported CNIs:** Calico, Cilium, Weave Net

### Check if Your Cluster Supports NetworkPolicy

```bash
# Check current CNI
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# If empty, NetworkPolicy won't work
```

### Enable Calico in Minikube (Optional)

⚠️ **This will delete your cluster and restart from scratch!**

```bash
# Delete existing cluster
minikube delete

# Start with Calico CNI
minikube start --cni=calico --kubernetes-version=v1.35.0

# Verify Calico is running
kubectl get pods -n kube-system | grep calico
# Expected: Multiple calico-* pods in Running state

# You'll need to redo Day 1-4 setup
```

---

## Use Case: Isolate Database

In our capstone, we want:
- ✅ **API can connect to Postgres** (allowed)
- ❌ **Web frontend cannot connect to Postgres** (denied)
- ❌ **Any other Pod cannot connect to Postgres** (denied)

This is the principle of **least privilege** for network access.

---

## NetworkPolicy Manifest

```yaml
# network-policy-postgres.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-isolation
  namespace: capstone
spec:
  # Apply to Pods with label app=postgres
  podSelector:
    matchLabels:
      app: postgres
  
  # Policy types
  policyTypes:
  - Ingress  # Control incoming traffic
  
  # Ingress rules (who can connect TO postgres)
  ingress:
  - from:
    # Only allow traffic from Pods with label app=api
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 5432
```

### What This Does

1. **Target:** Pods with `app=postgres` label
2. **Rule:** Only accept TCP connections on port 5432 from Pods with `app=api`
3. **Implicit deny:** All other traffic is blocked (default deny once NetworkPolicy exists)

---

## Apply and Test

### Step 1: Apply NetworkPolicy

```bash
# Only if you have Calico/Cilium/Weave enabled!
kubectl apply -f network-policy-postgres.yaml

# Verify
kubectl get networkpolicy -n capstone
kubectl describe networkpolicy postgres-isolation -n capstone
```

### Step 2: Test from API (Should Work)

The API should still be able to connect to Postgres:

```bash
# Create a task via API
curl -X POST http://capstone.local/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Test with NetworkPolicy"}'

# Expected: Success (API → Postgres allowed)
```

### Step 3: Test from Web Pod (Should Fail)

Try to connect directly from the web Pod (should timeout):

```bash
# Get web Pod name
WEB_POD=$(kubectl get pods -n capstone -l app=web -o jsonpath='{.items[0].metadata.name}')

# Try to connect to Postgres (should fail)
kubectl exec -n capstone $WEB_POD -- nc -zv postgres-service 5432

# Expected: Connection timed out or refused (blocked by NetworkPolicy)
```

### Step 4: Test from Temporary Debug Pod (Should Fail)

```bash
# Create debug Pod
kubectl run debug -n capstone --image=busybox --rm -it -- sh

# Inside the Pod, try to connect:
nc -zv postgres-service 5432

# Expected: Connection refused (blocked)
# Exit with: exit
```

---

## Understanding the Policy

### PodSelector (Target)

```yaml
podSelector:
  matchLabels:
    app: postgres
```

**Meaning:** This policy applies to Pods with label `app=postgres`

### Ingress Rules (Who Can Connect)

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: api
```

**Meaning:** Only Pods with label `app=api` can connect

### Implicit Deny

Once a NetworkPolicy exists for a Pod, **all traffic not explicitly allowed is denied**.

---

## Common Patterns

### Allow Traffic from Specific Namespace

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: production
  - podSelector:
      matchLabels:
        app: api
```

### Allow Traffic from Anywhere (External)

```yaml
ingress:
- from:
  - namespaceSelector: {}  # All namespaces
  - podSelector: {}        # All pods
```

### Deny All Traffic (Lockdown)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}  # Applies to all Pods
  policyTypes:
  - Ingress
  - Egress
  # No ingress/egress rules = deny all
```

---

## Egress (Outbound Traffic)

You can also control **outbound** traffic from Pods:

```yaml
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**This allows API to:**
- Connect to Postgres on port 5432
- Use DNS (required for `postgres-service` resolution)
- Blocks all other outbound connections

---

## Debugging NetworkPolicy

### Check if Policy is Applied

```bash
kubectl get networkpolicy -n capstone
kubectl describe networkpolicy postgres-isolation -n capstone
```

### Verify CNI Support

```bash
# Check CNI pods
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# If empty, NetworkPolicy is silently ignored (no error!)
```

### Test Connectivity

```bash
# From Pod A to Pod B
kubectl exec -n capstone <pod-a> -- nc -zv <service-b> <port>

# Expected: Connection succeeded (allowed) or timed out (denied)
```

### Check Logs (Calico)

```bash
# Calico logs show dropped packets
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50 | grep DROP
```

---

## Why Not in Core Lab?

1. **Setup complexity:** Requires CNI change (cluster recreation)
2. **Silent failure:** If CNI doesn't support it, policy does nothing (confusing)
3. **Day 4 focus:** Storage + RBAC are core KCNA topics; NetworkPolicy is advanced

**For KCNA exam:** You need to understand NetworkPolicy **concepts**, not implement it hands-on.

---

## KCNA Exam Tips

**What you need to know:**
- NetworkPolicy controls **Pod-to-Pod traffic**
- Requires CNI plugin support (Calico, Cilium, Weave)
- Default behavior: allow all (until policy exists)
- Once policy exists: default deny (must explicitly allow)
- Can control **Ingress** (incoming) and **Egress** (outgoing)
- Uses **label selectors** to target Pods

**You DON'T need to:**
- Memorize exact YAML syntax
- Debug complex policy rules
- Understand CNI internals

---

## Further Reading

- [Kubernetes NetworkPolicy Docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico NetworkPolicy Guide](https://docs.tigera.io/calico/latest/network-policy/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [KCNA Curriculum - Networking](https://github.com/cncf/curriculum/blob/master/kcna/README.md)

---

## Summary

✅ **NetworkPolicy** is a powerful tool for zero-trust networking  
⚠️ **Requires** CNI plugin support  
🎓 **For KCNA:** Understand concepts, not hands-on mastery  
🔧 **For Production:** Essential for multi-tenant clusters

**Back to Day 4:** Focus on PVC and RBAC first. NetworkPolicy is a bonus for later.
