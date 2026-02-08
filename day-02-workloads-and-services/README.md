# Day 2: Workloads and Services

## 🎯 Learning Objectives

By the end of Day 2, you will:

- ✅ Understand the **ReplicaSet** pattern for maintaining desired replica count
- ✅ Use **Deployments** to manage rolling updates and rollbacks
- ✅ Create **Services** for stable network endpoints
- ✅ Implement **service discovery** using DNS
- ✅ Build a **multi-tier application** (web → api) with proper networking

---

## 📚 Theory Foundation (Lezione 2)

This lab day implements concepts from **Lezione 2 - Dal cluster ai primi workload reali**:

- **Paradigma dichiarativo**: desired state vs actual state
- **Riconciliazione**: control loop (observe → compare → act)
- **Workload objects**: Pod → ReplicaSet → Deployment
- **Networking**: Service, ClusterIP, selector/endpoint
- **Debugging method**: `get → describe → events → logs`

---

## 🧪 Lab Structure

### **Lab 2.1 - ReplicaSet: From 1 to N instances**
📂 `lab-2.1-replicaset/`

- Create ReplicaSet to maintain 3 replicas
- Test self-healing (delete Pod → auto-recreated)
- **Gap filled**: automatic cardinality

### **Lab 2.2 - Deployment: Managing change**
📂 `lab-2.2-deployment/`

- Migrate from ReplicaSet to Deployment
- Perform rolling update (nginx → nginx:alpine)
- Observe coexistence of old/new Pods
- **Gap filled**: zero-downtime updates

### **Lab 2.3 - Service: Stable endpoint**
📂 `lab-2.3-service/`

- Create ClusterIP Service for web
- Verify internal DNS resolution
- Test port-forward for external access
- **Gap filled**: service discovery

### **Lab 2.4 - Multi-Tier Capstone: web → api**
📂 `lab-2.4-multi-tier-capstone/`

- Add API component (httpbin/echo server)
- Create Service for API
- Web calls API via Service name (not IP)
- **DoD Day 2**: `curl web → web calls API → API responds`

---

## 🔧 Prerequisites

Before starting Day 2 labs:

### ✅ Day 1 completed:
- Minikube cluster running
- kubectl configured
- Completed Day 1 labs (Pod basics)
- Comfortable with `get`, `describe`, `logs`

### ✅ Theory review:
- Read Lezione 2 slides (sections: Riconciliazione, Workload Objects, Networking)
- Understand: desired state, reconciliation loop, spec vs status

### ✅ Environment check:
```bash
# Verify cluster
minikube status
kubectl cluster-info

# Verify namespace (reuse from Day 1)
kubectl get namespace task-tracker

# If needed, recreate
kubectl create namespace task-tracker
kubectl config set-context --current --namespace=task-tracker
```

---

## 🎓 Learning Path

### **Progression:**
```
Day 1: Pod (single instance)
  ↓
Day 2 Lab 2.1: ReplicaSet (N instances, self-healing)
  ↓
Day 2 Lab 2.2: Deployment (versioning, rollout)
  ↓
Day 2 Lab 2.3: Service (stable endpoint)
  ↓
Day 2 Lab 2.4: Multi-tier (web → api)
```

### **Concepts layering:**
- **Lab 2.1**: Cardinality ("how many?")
- **Lab 2.2**: Change management ("how to update?")
- **Lab 2.3**: Networking ("how to reach?")
- **Lab 2.4**: Composition ("how to connect components?")

---

## 📋 Daily Definition of Done (DoD)

At the end of Day 2, you should have:

✅ **Running workloads:**
- 3 web Pods managed by Deployment
- 2 API Pods managed by Deployment

✅ **Stable networking:**
- ClusterIP Service for web
- ClusterIP Service for API
- DNS resolution working (`nslookup web-service`, `nslookup api-service`)

✅ **Multi-tier communication:**
- web Pod can call API via Service name
- API responds correctly
- `curl http://web-service/api-test` returns API response

✅ **Verification commands:**
```bash
# Check Deployments
kubectl get deployment
kubectl rollout status deployment/web-deployment
kubectl rollout status deployment/api-deployment

# Check Services
kubectl get service
kubectl get endpoints

# Test DNS
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web-service
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup api-service

# Test connectivity
kubectl port-forward service/web-service 8080:80
curl http://localhost:8080/api-test
```

✅ **Skills demonstrated:**
- Created and scaled ReplicaSets
- Performed rolling update
- Connected services via DNS
- Debugged networking issues (Service without endpoints)

See [DAILY-DOD.md](./DAILY-DOD.md) for detailed checklist.

---

## 🔗 Resources

### **Official Kubernetes Docs:**
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

### **KCNA Alignment:**
- **Kubernetes Fundamentals (46%)**: ReplicaSet, Deployment, reconciliation
- **Container Orchestration (22%)**: workload lifecycle, scheduling
- **Cloud Native Architecture (16%)**: service discovery, loose coupling

---

## 🚀 Getting Started

Start with Lab 2.1:
```bash
cd day-02-workloads-and-services/lab-2.1-replicaset
cat README.md
```

---

**Previous**: [Day 1 - Pod Fundamentals](../day-01-pods-fundamentals/README.md)  
**Next**: [Lab 2.1 - ReplicaSet](./lab-2.1-replicaset/README.md)
