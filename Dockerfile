# Dockerfile for github.com/epnasis/gce-demo (using Gunicorn with 1 worker)

# 1. Base Image: Use a recent, slim, supported Python version
FROM python:3.12-slim

# 2. Working Directory: Set a working directory inside the container
WORKDIR /app

# 3. Install Dependencies: Copy requirements first for caching, then install
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip -r requirements.txt
# Installs Flask and Gunicorn from your requirements.txt

# 4. Copy Application Code: Copy main.py, templates/, etc.
COPY . .

# 5. Expose Port: Document the internal port Gunicorn will use
EXPOSE 8080

# 6. Run Command: Use Gunicorn with 1 worker, binding to internal port 8080
CMD ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:8080", "main:app"]