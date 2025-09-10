# Multi-process Django app (web/worker/scheduler) – single image
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV POETRY_VIRTUALENVS_CREATE=false
ENV STATUS_PAGE_CONFIGURATION=statuspage.k8s_configuration

WORKDIR /app

# System deps for psycopg2 & build
RUN apt-get update && apt-get install -y --no-install-recommends     build-essential libpq-dev curl ca-certificates &&     rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r requirements.txt gunicorn

# Copy app
COPY . /app

# Create a non-root user
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# Django env – point to our runtime config that reads env vars
ENV DJANGO_SETTINGS_MODULE=statuspage.statuspage.settings     STATUS_PAGE_CONFIGURATION=statuspage.k8s_configuration     PYTHONPATH=/app

# Collect static (possible switch to S3 later)
RUN python statuspage/manage.py collectstatic --noinput || true

EXPOSE 8000
CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:8000", "statuspage.wsgi"]
