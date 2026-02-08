# Kubernetes Capstone Labs

Progressive Kubernetes laboratory series: building a multi-tier **Task Tracker** application from basic Pod to production-ready deployment.

**Target audience:** Researchers, Developers, DevOps Engineers, Architects, System Administrators  
**Alignment:** KCNA (Kubernetes and Cloud Native Associate) certification-ready  
**Environment:** Minikube on WSL2 (Ubuntu) or macOS  
**Duration:** 5 days (40 hours total)

---

## 🎯 Final Architecture

By Day 5, you'll have built and operated:

```
[Browser/Client]
       ↓
   [Ingress] (path-based routing)
       ↓
   ┌───────────────────────┐
   ↓                       ↓
[Frontend nginx]    [API Service]
(reverse proxy)     (httpbin/Flask)
       ↓                   ↓
   [ConfigMap]         [Secret]
                           ↓
                    [PostgreSQL]
                    (StatefulSet + PVC)
```

**Routing:**
- `/` → Frontend (nginx)
- `/api` → Backend API
- Database: internal only (ClusterIP)

---

## 📚 Learning Path

### **Day 1: Foundation**
**Concepts:** Pod, ConfigMap, kubectl basics, desired vs actual state  
**Output:** Single nginx Pod serving custom HTML  
**Verification:** `kubectl port-forward` + browser access

### **Day 2: Replication & High Availability**
**Concepts:** Deployment, ReplicaSet, Service (ClusterIP), DNS, scaling  
**Output:** 3-replica web deployment with stable internal endpoint  
**Verification:** Service discovery, load balancing across replicas

### **Day 3: Multi-tier Architecture**
**Concepts:** Multi-component apps, Ingress, ConfigMap as config, path-based routing  
**Output:** Frontend + API with external access via Ingress  
**Verification:** `curl` tests for `/` and `/api` paths, DNS resolution

### **Day 4: Stateful Workloads** (not in this initial release)
**Concepts:** StatefulSet, PersistentVolume, Secret, database initialization  
**Output:** PostgreSQL with persistent data + API CRUD operations  

### **Day 5: Production Readiness** (not in this initial release)
**Concepts:** ResourceQuota, LimitRange, NetworkPolicy, probes, monitoring  
**Output:** Production-grade deployment with security and observability  

---

## 🛠️ Prerequisites

### Required Tools
- **Minikube** v1.30+ ([installation guide](https://minikube.sigs.k8s.io/docs/start/))
- **kubectl** v1.35+ ([installation guide](https://kubernetes.io/docs/tasks/tools/))
- **Git** (for cloning this repository)

### Environment Setup
- **Windows:** WSL2 with Ubuntu 20.04+ (bash shell)
- **macOS:** Terminal with bash or zsh
- **Linux:** Any modern distribution

### Verification
```bash
# Check Minikube
minikube version

# Check kubectl
kubectl version --client

# Start Minikube (if not running)
minikube start --driver=docker --kubernetes-version=v1.35.0

# Verify cluster
kubectl get nodes
```

---

## 🚀 How to Use This Repository

### Quick Start
```bash
# Clone repository
git clone https://github.com/the-byte-sized/kubernetes-capstone-labs.git
cd kubernetes-capstone-labs

# Day 1: Start with foundation
cd day-1-foundation/
cat README.md  # Read objectives and steps

# Apply manifests
kubectl apply -f manifests/

# Verify
./verify.sh
```

### Using Git Tags for Checkpoints
Each day has two tags: `start` and `end`

```bash
# Jump to Day 2 starting point (includes Day 1 complete)
git checkout day-2-start
cd day-2-replication/

# See Day 2 solution
git checkout day-2-end
```

### Daily Workflow
1. **Read `README.md`** in the day folder (objectives, concepts)
2. **Apply manifests** in order: `kubectl apply -f manifests/`
3. **Run verification**: `./verify.sh`
4. **Troubleshoot** if needed: check `troubleshooting.md`
5. **Observe state**: use `kubectl get`, `describe`, `logs`

---

## 📖 Repository Structure

```
kubernetes-capstone-labs/
├── README.md                    # ← You are here
├── docs/
│   ├── commands-cheatsheet.md   # Essential kubectl commands
│   ├── troubleshooting.md       # Global troubleshooting guide
│   └── architecture.md          # Application architecture evolution
│
├── day-1-foundation/
│   ├── README.md                # Day 1 objectives & guide
│   ├── manifests/
│   │   ├── 01-configmap-html.yaml
│   │   └── 02-pod-web.yaml
│   ├── verify.sh                # Automated verification
│   └── troubleshooting.md       # Day-specific issues
│
├── day-2-replication/
│   ├── README.md
│   ├── manifests/
│   │   ├── 01-configmap-html.yaml
│   │   ├── 02-deployment-web.yaml
│   │   └── 03-service-web.yaml
│   ├── verify.sh
│   └── troubleshooting.md
│
└── day-3-multitier/
    ├── README.md
    ├── manifests/
    │   ├── 01-configmap-nginx-proxy.yaml
    │   ├── 02-deployment-web.yaml
    │   ├── 03-service-web.yaml
    │   ├── 04-deployment-api.yaml
    │   ├── 05-service-api.yaml
    │   └── 06-ingress.yaml
    ├── verify.sh
    └── troubleshooting.md
```

---

## 🎓 KCNA Alignment

This lab series covers these KCNA exam domains:

- **Kubernetes Fundamentals (44%):** Pods, Deployments, Services, ConfigMaps, Secrets
- **Container Orchestration (28%):** Scheduling, scaling, self-healing, DNS
- **Cloud Native Application Delivery (16%):** Ingress, multi-tier apps, configuration management
- **Cloud Native Architecture (12%):** Declarative model, stateless vs stateful, observability

---

## 🔍 Key Learning Principles

### 1. Declarative Model
You declare **desired state** in YAML manifests. Kubernetes continuously reconciles **actual state** to match.

### 2. Observability First
Before changing anything, observe:
```bash
kubectl get <resource>      # High-level status
kubectl describe <resource> # Detailed info + events
kubectl logs <pod>          # Application logs
```

### 3. Troubleshooting Method
**Step 1:** What is desired state? (read the spec)  
**Step 2:** What is actual state? (check status)  
**Step 3:** Where does convergence stop? (events, conditions)

### 4. Verification Over Assumption
Every change must be verified with concrete commands and expected output.

---

## 🆘 Getting Help

### Common Issues
- **Minikube won't start:** Check Docker/VM driver, disk space, resources
- **Pod stuck in Pending:** Check scheduler events: `kubectl describe pod <name>`
- **Service not reachable:** Verify Endpoints: `kubectl get endpoints <service>`
- **Ingress 404/503:** Check controller is running: `kubectl get pods -n ingress-nginx`

### Resources
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [KCNA Exam Curriculum](https://github.com/cncf/curriculum/blob/master/kcna/README.md)
- Repository issues: [Create an issue](https://github.com/the-byte-sized/kubernetes-capstone-labs/issues)

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Based on the **Kubernetes + Cloud Native** course (KCNA-ready) designed for hands-on learning with progressive complexity.

**Instructor:** Claudio Cortese  
**Organization:** [The Byte-sized](https://github.com/the-byte-sized)

---

## 🏁 Ready to Start?

```bash
cd day-1-foundation/
cat README.md
```

**Let's build something real!** 🚀
