# Task Tracker Web Frontend

Minimal frontend for the Task Tracker application used in Kubernetes KCNA labs.

## Features

- **Single-page application**: Pure HTML/CSS/JavaScript (no framework dependencies)
- **Real-time updates**: Auto-refresh tasks every 5 seconds
- **Clean UI**: Gradient design, responsive layout
- **API integration**: Communicates with Flask API backend via nginx proxy
- **Kubernetes-ready**: Designed for multi-tier deployment

## Architecture

```
┌──────────────────┐
│   Browser        │
└────────┬─────────┘
         │ HTTP
         ▼
┌──────────────────┐
│   nginx (Port 80)│  ← This container
│   - Serves HTML  │
│   - Proxies /api │
└────────┬─────────┘
         │ /api/* → http://task-api-service:8080/api/*
         ▼
┌──────────────────┐
│  task-api Flask  │
│  (Port 8080)     │
└────────┬─────────┘
         │ SQL
         ▼
┌──────────────────┐
│  PostgreSQL      │
│  (Port 5432)     │
└──────────────────┘
```

## Local Development

### Test with Docker

```bash
# Build image
docker build -t ghcr.io/the-byte-sized/task-web:latest .

# Run locally (requires API running)
docker run --rm -p 8081:80 \
  --network task-net \
  ghcr.io/the-byte-sized/task-web:latest

# Open browser
open http://localhost:8081
```

### Test with Python HTTP Server (development only)

```bash
# Serve static files
python3 -m http.server 8000

# Note: API calls will fail without backend
# Use for UI-only testing
```

## Configuration

### API Endpoint

The frontend expects the API at `/api/*`, which nginx proxies to:

```nginx
location /api/ {
    proxy_pass http://task-api-service:8080/api/;
    # ...
}
```

**In Kubernetes**: `task-api-service` must be the name of the API Service.

### Environment Variables

No environment variables needed. Configuration is baked into `nginx.conf`.

## Building for Production

### Manual Build

```bash
# Build multi-arch image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/the-byte-sized/task-web:latest \
  --push .
```

### GitHub Actions

A workflow is configured in `.github/workflows/build-web.yml` to automatically build and push on commits to `day-4-storage-security` branch.

**Triggers**:
- Push to `docs/web-source/*`
- Manual workflow dispatch

**Output**: `ghcr.io/the-byte-sized/task-web:latest`

## Deployment in Kubernetes

See `day-04-storage-security/lab-4.4-frontend/` for complete manifests.

### Quick Deploy

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: ghcr.io/the-byte-sized/task-web:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: task-web-service
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

### Access

**Via port-forward** (Day 4):
```bash
kubectl port-forward svc/task-web-service 8080:80
open http://localhost:8080
```

**Via Ingress** (Day 5):
```bash
# After configuring Ingress
open http://tasktracker.local
```

## Files

- `index.html`: Single-page application (HTML + CSS + JavaScript)
- `nginx.conf`: Nginx configuration (static files + API proxy)
- `Dockerfile`: Multi-stage build for production image
- `README.md`: This file

## Troubleshooting

### Frontend loads but "Cannot connect to API"

**Cause**: API Service not reachable from nginx container.

**Fix**:
```bash
# Verify API Service exists
kubectl get svc task-api-service

# Check if API is responding
kubectl run test --rm -it --image=curlimages/curl:8.11.1 -- \
  curl http://task-api-service:8080/api/tasks

# Check nginx logs
kubectl logs -l app=web
```

### Tasks don't appear after adding

**Cause**: API not saving to database or database issue.

**Fix**:
```bash
# Check API logs
kubectl logs -l app=api

# Verify DB connection
kubectl exec -it deployment/task-api -- \
  env | grep POSTGRES

# Test API directly
kubectl port-forward svc/task-api-service 8080:8080
curl http://localhost:8080/api/tasks
```

### Nginx returns 502 Bad Gateway

**Cause**: API Service name mismatch in `nginx.conf`.

**Fix**: Ensure `proxy_pass` URL matches your API Service name:
```nginx
proxy_pass http://task-api-service:8080/api/;
#              ^^^^^^^^^^^^^^^^^ Must match Service name
```

## Design Choices

### Why no JavaScript framework?

- **Focus on Kubernetes**: Labs teach K8s concepts, not React/Vue
- **Zero build step**: Students can edit HTML directly
- **Minimal size**: 10KB HTML vs 500KB+ bundle
- **Easy debugging**: View source works, no sourcemaps needed

### Why nginx instead of serving from API?

- **Separation of concerns**: Static files ≠ API logic
- **Performance**: nginx serves static assets faster than Flask
- **Real-world pattern**: Typical microservices architecture
- **Scalability**: Can scale web and API independently

### Why auto-refresh instead of WebSocket?

- **Simplicity**: Polling is easier to understand for students
- **Stateless**: No persistent connections to manage
- **Good enough**: 5-second refresh is acceptable for demo

## Future Enhancements (out of scope for KCNA)

- [ ] Delete task functionality
- [ ] Mark task as complete
- [ ] Filtering/sorting
- [ ] Dark mode toggle
- [ ] WebSocket for real-time updates
- [ ] Service Worker for offline support

## License

MIT License - see repository root for details.

## Related

- API Backend: `docs/api-source/`
- Kubernetes Manifests: `day-04-storage-security/lab-4.4-frontend/`
- Lab Instructions: `day-04-storage-security/README.md`
