# Field Runbook — EO/IR stack v1.4.2

## Starter defects and fixes

Line numbers refer to the supplied starter files.

| File / starter lines | Defect | Fix |
|---|---|---|
| `docker-compose.yml` 4–7, 29–30 | Database and AWS credentials in YAML; Postgres exposed on host. | Require DB values from ignored `.env`; remove unused AWS key and host DB port. Rotate exposed sample credentials. |
| `docker-compose.yml` 14, 18–21 | Worker healthcheck always passed. | Real `/status` + checksum probe every 3s, 3 retries. |
| `docker-compose.yml` 24, 32–35 | Wrong `localhost:9001` URL and isolated networks. | Use `inference_worker:9000`; API joins the internal service network. |
| `docker-compose.yml` 31–33 | Services started before dependencies were ready. | Wait for healthy worker and database. |
| `vision_api/app.py` 10–18, 49–56 | One startup-only worker check kept the API degraded after an early failure. | Check live worker status on every health and detection request. |
| `inference_worker/worker.py` 15–25; `models/manifest.json` 8 | Model hash mismatch; cache path was not writable by non-root. | Correct fixture hash; reject malformed/mismatched artifacts; write cache under `/tmp`. |
| `Dockerfile` 1–11; missing `.dockerignore` | Large image, root runtime, unnecessary files in build context. | Digest-pinned slim base, numeric UID/GID 10001, minimal copies, ignore local files. CI enforces <220 MB. |
| `.github/workflows/ci.yml` 14, 22–27 | Test failures ignored, no model gate, mutable `latest`, no runtime smoke. | Tests + hash gate, Compose smoke/corruption check, size gate, pinned actions and SHA/version tags. |
| Air-gap scripts absent | No offline packaging, integrity, or architecture validation. | Bundle images/config/model, verify detached and per-file SHA256, reject architecture mismatch before image load. |

## First start and 15-minute field rollback

Before first start, run `cp .env.example .env`, set a unique `POSTGRES_PASSWORD`, then run `docker compose up -d --build`. Keep each release bundle and its `.sha256` sidecar in a trusted location; a checksum only authenticates the bundle if the sidecar arrives through a trusted, separate channel.

1. **0–2 min:** Stop promotion. Record `docker compose ps` and worker logs. Keep the prior verified bundle and image.
2. **2–5 min:** Confirm the worker is unhealthy. Save failed release ID, checksums, and logs for diagnosis.
3. **5–9 min:** Run `docker compose down` (never `-v`). Deploy the previous bundle with `deploy_airgap.sh <previous-bundle.tar.gz>`; verify the detached checksum and bundled `SHA256SUMS` before image loading. Keep `.env` and the database volume.
4. **9–12 min:** Confirm `docker compose ps` shows healthy services. Deployment uses the previous bundle’s versioned image; its model is baked into that image, so restoring only a host model file is not a rollback.
5. **12–15 min:** Verify `/health` is healthy and `/api/v1/detect` returns 200. Record the rollback and leave the failed release quarantined.

## CUDA / TensorRT and architecture

The challenge engine is a portable test fixture, not a real TensorRT engine. For field releases, build and validate separate engines for x86_64 lab GPUs and aarch64 Jetson Orin; record GPU capability, JetPack/L4T, CUDA, TensorRT, plugins, and engine architecture in the signed release manifest. The air-gap script checks container image architecture before loading; production packaging must also compare the real model’s declared architecture and runtime versions. Pin base images by digest and validate deserialization, warmup, and representative inference on each target before promotion.