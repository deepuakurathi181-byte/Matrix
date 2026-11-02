FROM python:3.11.18-slim-bookworm@sha256:94a8fee35252d06ab75856f15f12c7bae67b10e8a6da93c7fded82b2610926cd

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin app
COPY --chown=10001:10001 vision_api/ /app/vision_api/
COPY --chown=10001:10001 inference_worker/ /app/inference_worker/
COPY --chown=10001:10001 models/ /app/models/
USER 10001:10001
EXPOSE 8000 9000
CMD ["python", "vision_api/app.py"]