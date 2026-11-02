#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:-1.4.2}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Version must be semantic (for example 1.4.2).' >&2; exit 2; }
TAG="eoir-stack:${VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUNDLE_DIR="$WORK/release_v${VERSION}"
OUT="$ROOT/release_v${VERSION}.tar.gz"
mkdir -p "$BUNDLE_DIR/models"
MANIFEST_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/models/manifest.json")"
[[ "$MANIFEST_VERSION" == "$VERSION" ]] || { echo "Requested release $VERSION does not match model manifest $MANIFEST_VERSION" >&2; exit 1; }
EXPECTED_MODEL_SHA="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/models/manifest.json")"
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_MODEL_SHA="$(sha256sum "$ROOT/models/eo_detector_fp16.engine" | awk '{print $1}')"
else
  ACTUAL_MODEL_SHA="$(shasum -a 256 "$ROOT/models/eo_detector_fp16.engine" | awk '{print $1}')"
fi
[[ -n "$EXPECTED_MODEL_SHA" && "$ACTUAL_MODEL_SHA" == "$EXPECTED_MODEL_SHA" ]] || { echo 'Model does not match manifest checksum.' >&2; exit 1; }
docker image inspect "$TAG" >/dev/null
POSTGRES_IMAGE="postgres:15.19-alpine3.24@sha256:54e0dd8e8cddcdbb9156c2486eed5a43eccb7214d7c6828097d41ce049fb3984"
docker image inspect "$POSTGRES_IMAGE" >/dev/null
APP_ARCH="$(docker image inspect "$TAG" --format '{{.Architecture}}')"
DB_ARCH="$(docker image inspect "$POSTGRES_IMAGE" --format '{{.Architecture}}')"
[[ "$APP_ARCH" == "$DB_ARCH" ]] || { echo "Image architecture mismatch: app=$APP_ARCH postgres=$DB_ARCH" >&2; exit 1; }
MODEL_ARCH="$(sed -n 's/.*"target_arch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/models/manifest.json")"
case "$MODEL_ARCH" in
  portable_test_fixture) ;;
  amd64|x86_64) [[ "$APP_ARCH" == amd64 ]] || { echo "Model architecture $MODEL_ARCH does not match image $APP_ARCH" >&2; exit 1; } ;;
  arm64|aarch64|aarch64_jetpack5) [[ "$APP_ARCH" == arm64 ]] || { echo "Model architecture $MODEL_ARCH does not match image $APP_ARCH" >&2; exit 1; } ;;
  *) echo "Unsupported or missing model target_arch: $MODEL_ARCH" >&2; exit 1 ;;
esac
printf '%s\n' "$APP_ARCH" > "$BUNDLE_DIR/IMAGE_ARCH"
docker save "$TAG" "$POSTGRES_IMAGE" -o "$BUNDLE_DIR/images.tar"
cp "$ROOT/docker-compose.yml" "$ROOT/.env.example" "$ROOT/deploy_airgap.sh" "$BUNDLE_DIR/"
cp "$ROOT/models/manifest.json" "$ROOT/models/eo_detector_fp16.engine" "$BUNDLE_DIR/models/"
cat > "$BUNDLE_DIR/README.txt" <<EOF
EO/IR release ${VERSION}. Extract the bundle. From the extracted release folder, run:
bash ./deploy_airgap.sh ../release_v${VERSION}.tar.gz
Create .env beside the archive and replace its placeholder password. Transfer the detached
.sha256 sidecar separately through a trusted channel.
EOF
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$BUNDLE_DIR" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
else
  (cd "$BUNDLE_DIR" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS)
fi
tar -czf "$OUT" -C "$WORK" "release_v${VERSION}"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$ROOT" && sha256sum "release_v${VERSION}.tar.gz" > "release_v${VERSION}.tar.gz.sha256")
else
  (cd "$ROOT" && shasum -a 256 "release_v${VERSION}.tar.gz" > "release_v${VERSION}.tar.gz.sha256")
fi
echo "Created $OUT and detached checksum."