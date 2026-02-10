FROM python:3.11-alpine

# Metadata
LABEL org.opencontainers.image.source=https://github.com/the-byte-sized/kubernetes-capstone-labs
LABEL org.opencontainers.image.description="Task Tracker API for Kubernetes KCNA Lab"
LABEL org.opencontainers.image.licenses=MIT

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

# Non-root user for security
RUN adduser -D -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

CMD ["python", "app.py"]
