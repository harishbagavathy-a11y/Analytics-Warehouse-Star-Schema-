FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies if required (gcc/libpq are provided by psycopg2-binary)
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --default-timeout=120 -r requirements.txt

COPY src ./src
COPY sql ./sql
COPY docs ./docs

RUN mkdir -p /app/data /app/logs

CMD ["python", "src/load_warehouse.py"]
