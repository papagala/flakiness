FROM python:3.11-slim

WORKDIR /app
COPY src/flaky_server.py /app/flaky_server.py

EXPOSE 8080

# CLI flags pass straight through, e.g.:
#   docker run oswaldodocker/flakiness:v0.0.1 --percentage-of-failures 20
ENTRYPOINT ["python", "/app/flaky_server.py"]
