# Day 3: Networking, Ingress & Configuration

## 🎯 Learning Objectives

Make networking "real" in the capstone: Pods change, names stay stable.

Today you'll understand:
- How Kubernetes networking works under the hood
- DNS-based service discovery and troubleshooting
- HTTP exposure with Ingress and L7 routing
- External configuration with ConfigMap and Secret
- How probes impact Service endpoints

**Key insight**: The capstone evolves from "two Pods that start" to a composable mini-architecture with stable entry points, external config, and observable health signals.

---

## 📋 Prerequisites

✅ **Day 2 completed (Lab 2.4 - Multi-Tier Capstone)**:
- `web-deployment` (3 replicas) + `web-service` (ClusterIP)
- `api-deployment` (2 replicas) + `api-service` (ClusterIP)
- DNS resolution working between Pods
- Labels and selectors connecting Deployments to Services

**Verify current state:**
```bash
kubectl get deployment,service
kubectl get pods -o wide
kubectl get endpoints
```

**Expected:**
- Both Deployments show READY replicas
- Both Services have ClusterIP and endpoints populated
- All Pods in Running state with READY 1/1

---

## 🧪 Lab Sequence

### Morning: Networking Fundamentals
1. **[Lab 3.1 - DNS & Service Discovery](./lab-3.1-dns-service-discovery/)** ⭐ Start here
   - Verify DNS resolution and troubleshoot discovery issues
   - Practice: "name resolves?" and "endpoints exist?"

### Afternoon: Ingress & Configuration
2. **[Lab 3.2 - Ingress Controller Setup](./lab-3.2-ingress-setup/)**
   - Enable Ingress addon and verify controller is active

3. **[Lab 3.3 - Ingress L7 Routing](./lab-3.3-ingress-routing/)**
   - Create path-based routing (/ → web, /api → api)

4. **[Lab 3.4 - ConfigMap & Secret](./lab-3.4-configmap-secret/)**
   - Mount ConfigMap in web, inject Secret env var in api

5. **[Lab 3.5 - Probes & Endpoints](./lab-3.5-probes-endpoints/)**
   - Demonstrate readiness impact on endpoints
   - Create controlled failure with liveness probe

---

## ✅ Day 3 Definition of Done

**You can produce evidence on five points:**

1. ✅ **DNS works**: Pods have IPs and can talk to each other; Service names resolve via DNS
   ```bash
   kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service
   ```

2. ✅ **Service endpoints populated**: Services route to Ready endpoints only
   ```bash
   kubectl get endpointslice -l kubernetes.io/service-name=api-service
   ```

3. ✅ **Ingress routes L7**: HTTP requests reach correct backend based on host/path
   ```bash
   curl -H "Host: capstone.local" http://$(minikube ip)/
   curl -H "Host: capstone.local" http://$(minikube ip)/api
   ```

4. ✅ **ConfigMap/Secret consumed**: Config visible in web, env var visible in api
   ```bash
   kubectl exec deploy/web-deployment -- cat /etc/config/message
   kubectl exec deploy/api-deployment -- printenv | grep API_TOKEN
   ```

5. ✅ **Readiness changes endpoints**: Pod not Ready → endpoint empty; Pod Ready → endpoint populated
   ```bash
   kubectl get pods -o wide
   kubectl get endpointslice
   ```

---

## 🎓 KCNA Domains Covered

**Today emphasizes Fundamentals + Orchestration:**

| Domain | Weight | Topics Covered |
|--------|--------|----------------|
| **Kubernetes Fundamentals** | 46% | Networking model, DNS, Service discovery, troubleshooting |
| **Container Orchestration** | 22% | Endpoint management, Service types, readiness impact |
| **Cloud Native App Delivery** | 16% | ConfigMap/Secret, probe impact on rollout |
| **Cloud Native Architecture** | 16% | Network components (kube-proxy, CNI) - mental model only |

---

## 🧭 Three Layers Mental Model

Every networking issue localizes to one of three layers:

```
┌─────────────────────────────────────────┐
│ Layer 3: Ingress (L7 HTTP/HTTPS)        │ ← External access, host/path routing
├─────────────────────────────────────────┤
│ Layer 2: Service (Stable endpoints)     │ ← DNS names, load balancing, ClusterIP
├─────────────────────────────────────────┤
│ Layer 1: Pod Network (Connectivity)     │ ← Pod IPs, CNI, direct Pod-to-Pod
└─────────────────────────────────────────┘
```

**Troubleshooting approach:**
1. **Layer 1 broken?** Pods can't talk directly → CNI/network policy issue
2. **Layer 2 broken?** DNS resolves but no response → Service endpoints empty or port mismatch
3. **Layer 3 broken?** Ingress returns 404/timeout → Controller missing, rules not matched, or backend Service broken

---

## 🛠️ Diagnostic Commands (Day 3 Toolkit)

### DNS & Service Discovery
```bash
# Test DNS resolution
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup <service-name>

# Test connectivity via Service
kubectl run test-curl --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- curl http://<service-name>

# Check EndpointSlices (modern way)
kubectl get endpointslice
kubectl get EndpointSlice -l kubernetes.io/service-name=<service-name> -o yaml
```

### Ingress Debugging
```bash
# Check Ingress resource
kubectl get ingress
kubectl describe ingress <ingress-name>

# Check controller status
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx logs <controller-pod-name>

# Verify backend Service + endpoints
kubectl get svc,EndpointSlice
```

### ConfigMap/Secret Verification
```bash
# List config objects
kubectl get configmap,secret

# Inspect content (ConfigMap)
kubectl describe configmap <name>
kubectl get configmap <name> -o yaml

# Verify mounting in Pod
kubectl describe pod <pod-name>  # Check Volumes/Mounts
kubectl exec <pod-name> -- ls -la /path/to/mount
kubectl exec <pod-name> -- cat /path/to/file

# Verify env var (Secret)
kubectl exec <pod-name> -- printenv | grep <VAR_NAME>
```

### Probe & Endpoint Impact
```bash
# Check Pod readiness
kubectl get pods -o wide  # Look at READY column

# Check probe configuration
kubectl describe pod <pod-name>  # Look for Liveness/Readiness sections

# Watch endpoint changes
kubectl get EndpointSlice --watch

# Check probe failures in events
kubectl describe pod <pod-name>  # Look at Events
```

---

## 🚨 Common Issues & Golden Path

### Issue: "Service doesn't work"

**Golden path diagnostic:**
1. Service exists? `kubectl get svc <name>`
2. Endpoints exist? `kubectl get EndpointSlice`
3. Pods Ready? `kubectl get pods -l <selector>`
4. Selector matches? Compare Service selector to Pod labels
5. Port correct? `port` (Service) → `targetPort` → Pod `containerPort`

### Issue: "DNS doesn't resolve"

**Golden path diagnostic:**
1. CoreDNS running? `kubectl -n kube-system get pods -l k8s-app=kube-dns`
2. Service exists? `kubectl get svc <name>`
3. Right namespace? Try FQDN: `<service>.<namespace>.svc.cluster.local`
4. Test from Pod: `kubectl run test-dns ... nslookup <service>`

### Issue: "Ingress returns 404 or timeout"

**Golden path diagnostic:**
1. Controller running? `kubectl -n ingress-nginx get pods`
2. Ingress created? `kubectl get ingress`
3. Rules correct? `kubectl describe ingress` - check host/path
4. Backend Service exists? `kubectl get svc <backend-service>`
5. Backend has endpoints? `kubectl get EndpointSlice`

**Remember:** Problems "before" the API (validation, not found) vs "after" (object exists but doesn't converge). Network issues are usually "after" - the object exists, but connections are missing.

---

## 📚 Official References

- [Kubernetes Networking](https://kubernetes.io/docs/concepts/services-networking/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/service/#endpointslices)

---

## 🎯 Success Criteria

**At the end of Day 3, your capstone should:**

✅ Have stable internal networking (DNS + Service discovery)  
✅ Be accessible externally via Ingress with L7 routing  
✅ Use external configuration (no hardcoded values)  
✅ Implement health checks that affect traffic routing  
✅ Be diagnosable with evidence-based commands  

**Tomorrow (Day 4):** You'll add Postgres with persistent storage and RBAC for security. Today's stable networking and config foundation makes that possible.

---

**Previous**: [Day 2 - Workloads and Services](../day-02-workloads-and-services/)  
**Next**: [Lab 3.1 - DNS & Service Discovery](./lab-3.1-dns-service-discovery/)
