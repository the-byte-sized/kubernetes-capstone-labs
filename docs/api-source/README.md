# Task Tracker API

Minimal Flask API for Kubernetes KCNA lab (Day 4).

## Purpose

This API demonstrates Kubernetes concepts:
- **Secret consumption**: Database credentials from environment variables
- **Persistent storage**: Data survives Pod restarts via PVC
- **Service discovery**: Connects to `postgres-service` via DNS
- **Health probes**: `/health` endpoint for readiness checks

## Endpoints

### Health Check
```bash
GET /health
```
Returns: `{"status": "ok"}`

### Get All Tasks
```bash
GET /api/tasks
```
Returns: Array of tasks

### Create Task
```bash
POST /api/tasks
Content-Type: application/json

{"title": "Learn Kubernetes"}
```
Returns: Created task with ID

## Environment Variables

| Variable | Default | Source |
|----------|---------|--------|
| `DB_HOST` | `postgres-service` | Secret |
| `POSTGRES_DB` | `tasktracker` | Secret |
| `POSTGRES_USER` | `taskuser` | Secret |
| `POSTGRES_PASSWORD` | (required) | Secret |

## Docker Image

Pre-built image available at:
```
ghcr.io/the-byte-sized/task-api:v1.0
```

## Local Development (Optional)

**Note**: Students don't need to build this image. It's provided pre-built.

If you want to modify the code:

```bash
# Build
docker build -t task-api:dev .

# Run locally (requires Postgres)
docker run -p 8080:8080 \
  -e DB_HOST=localhost \
  -e POSTGRES_DB=tasktracker \
  -e POSTGRES_USER=taskuser \
  -e POSTGRES_PASSWORD=password \
  task-api:dev

# Test
curl http://localhost:8080/health
```

## Architecture Notes

- **No ORM**: Uses raw psycopg2 for simplicity
- **Auto-init schema**: Creates table on startup if missing
- **No migrations**: Production apps should use Alembic/Flyway
- **Minimal error handling**: Logs errors, returns 500 (Kubernetes-friendly)
- **No authentication**: Out of scope for KCNA lab

## For Instructors

This code intentionally avoids:
- Complex error handling (focus on Kubernetes troubleshooting)
- Database migrations (students focus on PVC, not schema management)
- Connection pooling (single replica sufficient for lab)
- Advanced Flask patterns (blueprints, extensions)

The goal: **Kubernetes concepts, not application complexity**.
