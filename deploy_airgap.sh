#!/usr/bin/env bash
set -euo pipefail
BUNDLE="${1:?usage: deploy_airgap.sh /path/to/release_vX.Y.Z.tar.gz}"
BUNDLE="$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")"
SIDECAR="${BUNDLE}.sha256"
[[ -f "$SIDECAR" ]] || { echo "Missing detached checksum: $SIDECAR" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$(dirname "$BUNDLE")" && sha256sum --check --strict "$(basename "$SIDECAR")")
else
  (cd "$(dirname "$BUNDLE")" && shasum -a 256 -c "$(basename "$SIDECAR")")
fi
BASE="$(cd "$(dirname "$BUNDLE")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$BUNDLE" -C "$TMP"
DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'release_v*' -print -quit)"
[[ -n "$DIR" && -f "$DIR/SHA256SUMS" && -f "$DIR/IMAGE_ARCH" ]]
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIR" && sha256sum --check --strict SHA256SUMS)
else
  (cd "$DIR" && shasum -a 256 -c SHA256SUMS)
fi
EXPECTED_MODEL_SHA="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/models/manifest.json")"
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_MODEL_SHA="$(sha256sum "$DIR/models/eo_detector_fp16.engine" | awk '{print $1}')"
else
  ACTUAL_MODEL_SHA="$(shasum -a 256 "$DIR/models/eo_detector_fp16.engine" | awk '{print $1}')"
fi
[[ -n "$EXPECTED_MODEL_SHA" && "$ACTUAL_MODEL_SHA" == "$EXPECTED_MODEL_SHA" ]] || { echo 'Model checksum does not match its manifest.' >&2; exit 1; }
EXPECTED_ARCH="$(cat "$DIR/IMAGE_ARCH")"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in x86_64) HOST_ARCH=amd64 ;; aarch64) HOST_ARCH=arm64 ;; esac
case "$EXPECTED_ARCH" in x86_64) EXPECTED_ARCH=amd64 ;; aarch64) EXPECTED_ARCH=arm64 ;; esac
[[ "$EXPECTED_ARCH" == "$HOST_ARCH" ]] || { echo "Bundle architecture $EXPECTED_ARCH does not match host $HOST_ARCH" >&2; exit 1; }
MODEL_ARCH="$(sed -n 's/.*"target_arch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/models/manifest.json")"
case "$MODEL_ARCH" in
  portable_test_fixture) ;;
  amd64|x86_64) [[ "$HOST_ARCH" == amd64 ]] || { echo "Model architecture $MODEL_ARCH does not match host $HOST_ARCH" >&2; exit 1; } ;;
  arm64|aarch64|aarch64_jetpack5) [[ "$HOST_ARCH" == arm64 ]] || { echo "Model architecture $MODEL_ARCH does not match host $HOST_ARCH" >&2; exit 1; } ;;
  *) echo "Unsupported or missing model target_arch: $MODEL_ARCH" >&2; exit 1 ;;
esac
if [[ ! -f "$BASE/.env" ]]; then
  cp "$DIR/.env.example" "$BASE/.env"
  echo "Created $BASE/.env. Replace the placeholder password, then rerun deployment." >&2
  exit 2
fi
if grep -Eq '^[[:space:]]*POSTGRES_PASSWORD=replace-with-' "$BASE/.env"; then
  echo 'Refusing placeholder POSTGRES_PASSWORD; edit .env before deployment.' >&2
  exit 2
fi
docker load -i "$DIR/images.tar"
cp "$DIR/docker-compose.yml" "$BASE/docker-compose.yml"
mkdir -p "$BASE/models"
cp "$DIR/models/manifest.json" "$DIR/models/eo_detector_fp16.engine" "$BASE/models/"
VERSION="$(basename "$DIR" | sed 's/^release_v//')"
(cd "$BASE" && IMAGE_TAG="$VERSION" docker compose up -d --no-build --pull never)