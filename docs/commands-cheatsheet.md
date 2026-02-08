# Kubernetes Commands Cheat Sheet

Essential kubectl commands for the lab series. Compatible with WSL2/macOS bash/zsh.

---

## 👥 Context & Configuration

```bash
# View current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch context
kubectl config use-context minikube

# Set default namespace
kubectl config set-context --current --namespace=<namespace>
```

---

## 📝 Viewing Resources

### Get (list resources)
```bash
# All resources in current namespace
kubectl get all

# Specific resource types
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get configmaps
kubectl get ingress

# All namespaces
kubectl get pods --all-namespaces
kubectl get pods -A  # Short form

# Specific namespace
kubectl get pods -n kube-system

# Wide output (more details)
kubectl get pods -o wide

# YAML output
kubectl get pod web -o yaml

# JSON output
kubectl get pod web -o json

# Custom columns
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# Watch (auto-refresh)
kubectl get pods -w
```

### Describe (detailed info + events)
```bash
# Pod
kubectl describe pod <pod-name>

# Deployment
kubectl describe deployment <deployment-name>

# Service
kubectl describe service <service-name>

# Node
kubectl describe node minikube

# Show only events section
kubectl describe pod web | grep -A 10 Events
```

---

## 🚀 Creating & Applying Resources

```bash
# Apply single file
kubectl apply -f manifest.yaml

# Apply directory (all YAML files)
kubectl apply -f manifests/

# Apply from URL
kubectl apply -f https://example.com/manifest.yaml

# Dry run (validate without creating)
kubectl apply -f manifest.yaml --dry-run=client

# Server-side dry run (validates against API)
kubectl apply -f manifest.yaml --dry-run=server

# Create resource imperatively
kubectl create deployment web --image=nginx:1.25-alpine
kubectl create service clusterip web --tcp=80:80
```

---

## ✏️ Editing Resources

```bash
# Edit in default editor (vi/nano)
kubectl edit pod web
kubectl edit deployment web

# Set image (quick update)
kubectl set image deployment/web nginx=nginx:1.26-alpine

# Scale deployment
kubectl scale deployment web --replicas=5
```

---

## 🗑️ Deleting Resources

```bash
# Delete by name
kubectl delete pod web
kubectl delete deployment web

# Delete using manifest file
kubectl delete -f manifest.yaml
kubectl delete -f manifests/  # Directory

# Delete all resources of a type
kubectl delete pods --all
kubectl delete all --all  # Everything in namespace

# Force delete (skip graceful termination)
kubectl delete pod web --force --grace-period=0
```

---

## 🔍 Debugging & Troubleshooting

### Logs
```bash
# View logs
kubectl logs <pod-name>

# Follow logs (stream)
kubectl logs -f <pod-name>

# Last 50 lines
kubectl logs --tail=50 <pod-name>

# Logs from specific container (multi-container pod)
kubectl logs <pod-name> -c <container-name>

# Previous container instance (after restart)
kubectl logs <pod-name> --previous

# Logs since timestamp
kubectl logs <pod-name> --since=1h
```

### Exec (run commands in container)
```bash
# Interactive shell
kubectl exec -it <pod-name> -- /bin/sh
kubectl exec -it <pod-name> -- /bin/bash  # If bash available

# Single command
kubectl exec <pod-name> -- ls -la /usr/share/nginx/html
kubectl exec <pod-name> -- curl localhost

# Specific container
kubectl exec -it <pod-name> -c <container-name> -- /bin/sh
```

### Port-forward
```bash
# Forward local port to pod
kubectl port-forward pod/<pod-name> 8080:80

# Forward to deployment
kubectl port-forward deployment/<deployment-name> 8080:80

# Forward to service
kubectl port-forward service/<service-name> 8080:80

# Listen on all interfaces (not just localhost)
kubectl port-forward --address 0.0.0.0 pod/web 8080:80
```

### Events
```bash
# All events in namespace
kubectl get events

# Sort by timestamp
kubectl get events --sort-by='.lastTimestamp'

# Watch events
kubectl get events -w

# Events for specific resource
kubectl describe pod <pod-name> | grep -A 20 Events
```

---

## 🎯 Labels & Selectors

```bash
# Show labels
kubectl get pods --show-labels

# Filter by label
kubectl get pods -l app=web
kubectl get pods -l 'app in (web,api)'
kubectl get pods -l app=web,tier=frontend

# Add label
kubectl label pod web environment=dev

# Remove label
kubectl label pod web environment-

# Overwrite label
kubectl label pod web environment=prod --overwrite
```

---

## 🆘 Namespaces

```bash
# List namespaces
kubectl get namespaces
kubectl get ns  # Short form

# Create namespace
kubectl create namespace dev

# Delete namespace (deletes all resources inside)
kubectl delete namespace dev

# Set default namespace for current context
kubectl config set-context --current --namespace=dev
```

---

## 🔗 Services & Networking

```bash
# List services
kubectl get services
kubectl get svc  # Short form

# Show endpoints (backend Pods)
kubectl get endpoints
kubectl get endpoints <service-name>

# Show EndpointSlices (newer API)
kubectl get endpointslices

# Describe service
kubectl describe svc <service-name>

# Test DNS resolution from Pod
kubectl run test --rm -it --image=busybox -- nslookup <service-name>

# Test connectivity
kubectl run test --rm -it --image=curlimages/curl -- curl <service-name>
```

---

## 🛠️ Useful Combinations

### Quickly check Pod status
```bash
kubectl get pods -o wide | grep -v Running
```

### Get Pod IPs
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP
```

### Watch specific Pod
```bash
watch -n 1 kubectl get pod web
```

### Get resource requests/limits
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Check which node a Pod is on
```bash
kubectl get pod <pod-name> -o wide
```

---

## 🔧 Minikube-Specific

```bash
# Start Minikube
minikube start

# Start with specific resources
minikube start --memory=4096 --cpus=2

# Check status
minikube status

# Stop (preserves cluster state)
minikube stop

# Delete cluster
minikube delete

# SSH into node
minikube ssh

# Get Minikube IP
minikube ip

# Open service in browser
minikube service <service-name>

# List addons
minikube addons list

# Enable addon
minikube addons enable ingress

# Access dashboard
minikube dashboard
```

---

## 📊 Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kpf='kubectl port-forward'
alias ka='kubectl apply -f'

# Usage: k get pods
```

---

## 🔍 Quick Diagnostics

### "Why is my Pod not Running?"
```bash
kubectl get pod <pod-name>
kubectl describe pod <pod-name> | grep -A 10 Events
kubectl logs <pod-name>
```

### "Why is my Service not working?"
```bash
kubectl get svc <service-name>
kubectl get endpoints <service-name>
kubectl describe svc <service-name>
kubectl get pods -l <selector-from-service>
```

### "What's wrong with my cluster?"
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

---

## 📚 Additional Resources

- [Official kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [kubectl Command Reference](https://kubernetes.io/docs/reference/kubectl/)
- [JSONPath Support](https://kubernetes.io/docs/reference/kubectl/jsonpath/)

---

**Back to:** [Main README](../README.md)
