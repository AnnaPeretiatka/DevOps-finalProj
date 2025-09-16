# Multi-process Django app (web/worker/scheduler) – single image
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1


#ENV POETRY_VIRTUALENVS_CREATE=false

WORKDIR /app

# System deps for psycopg2 & build
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libpq-dev curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip \
 && pip install --no-deps rq==1.8.1 \
 && pip install --no-deps django-rq==2.4.1 \
 && pip install --no-deps rq-scheduler==0.10.0 \
 && pip install -r requirements.txt \
 && pip install gunicorn

# Copy app code
COPY . /app

# Create a non-root user
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# outer statuspage folder
ENV PYTHONPATH=/app/statuspage
ENV DJANGO_SETTINGS_MODULE=statuspage.settings 
ENV STATUS_PAGE_CONFIGURATION=statuspage.configuration

# Collect static files
RUN python statuspage/manage.py collectstatic --noinput || true

EXPOSE 8000

# Run the WSGI server
CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:8000", "statuspage.wsgi"]
