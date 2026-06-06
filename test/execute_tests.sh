#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${TEST_IMAGE:-emojizasu-test:latest}"
ADDON_SO="$REPO/imd/target/release/libemojizasu_imd.so"

echo "==> building test-variant addon on host..."
( cd "$REPO/imd" && cargo build --release --features test-variant )
[ -f "$ADDON_SO" ] || { echo "build produced no $ADDON_SO" >&2; exit 1; }

if ! podman image exists "$IMAGE"; then
    echo "==> building container image ($IMAGE)..."
    podman build -t "$IMAGE" "$REPO/test/container"
fi

echo "==> running suite in container..."
exec podman run --rm \
    -v "$REPO":/src:ro \
    -v "$ADDON_SO":/addon/libemojizasu_imd_test.so:ro \
    "$IMAGE" \
    bash /src/test/container/start.sh
