"""Task Tracker API - Minimal Flask app for Kubernetes lab

This API demonstrates:
- Connection to PostgreSQL via environment variables
- Basic CRUD operations (GET/POST)
- Health check endpoint
- Auto-initialization of database schema

Designed for KCNA training - focus is on Kubernetes concepts,
not application complexity.
"""

from flask import Flask, request, jsonify
import psycopg2
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_db_connection():
    """Create database connection from environment variables."""
    return psycopg2.connect(
        host=os.getenv('DB_HOST', 'postgres-service'),
        database=os.getenv('POSTGRES_DB', 'tasktracker'),
        user=os.getenv('POSTGRES_USER', 'taskuser'),
        password=os.getenv('POSTGRES_PASSWORD')
    )

def init_database():
    """Initialize database schema if it doesn't exist.
    
    This runs once at startup. In production, you'd use
    proper migrations (Alembic, Flyway, etc).
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id SERIAL PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        logger.info("Database schema initialized")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        # Don't crash - let Kubernetes restart and retry

# Initialize DB on startup
init_database()

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for Kubernetes probes."""
    return jsonify({"status": "ok"}), 200

@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """Get all tasks."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, created_at FROM tasks ORDER BY id")
        tasks = [
            {
                "id": row[0],
                "title": row[1],
                "created_at": row[2].isoformat() if row[2] else None
            }
            for row in cursor.fetchall()
        ]
        cursor.close()
        conn.close()
        return jsonify(tasks), 200
    except Exception as e:
        logger.error(f"Error fetching tasks: {e}")
        return jsonify({
            "error": "Database error",
            "hint": "Check logs with: kubectl logs -n capstone deploy/api"
        }), 500

@app.route('/api/tasks', methods=['POST'])
def create_task():
    """Create a new task."""
    try:
        data = request.get_json()
        if not data or 'title' not in data:
            return jsonify({"error": "Missing 'title' field"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO tasks (title) VALUES (%s) RETURNING id, created_at",
            (data['title'],)
        )
        result = cursor.fetchone()
        task_id = result[0]
        created_at = result[1].isoformat() if result[1] else None
        conn.commit()
        cursor.close()
        conn.close()
        
        return jsonify({
            "id": task_id,
            "title": data['title'],
            "created_at": created_at
        }), 201
    except Exception as e:
        logger.error(f"Error creating task: {e}")
        return jsonify({
            "error": "Database error",
            "hint": "Check logs with: kubectl logs -n capstone deploy/api"
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
