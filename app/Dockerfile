FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY static/ static/

EXPOSE 5000

ENV APP_VERSION=1.0.0

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
