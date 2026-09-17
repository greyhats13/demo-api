FROM python:3.13-slim AS builder

WORKDIR /app

COPY app/requirements.txt .

# Install into one folder, so the runtime stage copy only the packages.
RUN pip install --no-cache-dir --target /deps -r requirements.txt

FROM gcr.io/distroless/python3-debian13:nonroot

WORKDIR /app

# The base python deosnt look into /deps, so we add it othe import path
ENV PYTHONPATH=/deps \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY --from=builder /deps /deps
COPY app/ .   

EXPOSE 8080

# No shell in distroless, so exec form only. THe base entrypoint is already the python binary
# Access log goes to stdout, so ECS send it to Cloudwatch
CMD ["-m", "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app:app"]
