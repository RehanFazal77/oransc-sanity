FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY focom_controller.py .

CMD ["kopf", "run", "--standalone", "--liveness=http://0.0.0.0:8080/healthz", "focom_controller.py"]
