FROM python:3.11-alpine

# Install Docker client and curl for health checks
RUN apk add --no-cache docker-cli curl

# Install Python dependencies
RUN pip install --no-cache-dir docker

# Create app directory
WORKDIR /app

# Copy application
COPY simple_server.py .

# Health check using curl (more reliable than wget)
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:6969/ || exit 1

# Expose port
EXPOSE 6969

# Run the application
CMD ["python3", "simple_server.py"]