#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Fussel.app into dist/.
# Usage: scripts/build.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch arm64
swift build -c release --arch x86_64

mkdir -p dist
lipo -create \
  .build/arm64-apple-macosx/release/Fussel \
  .build/x86_64-apple-macosx/release/Fussel \
  -output dist/Fussel-bin

"$ROOT/scripts/bundle.sh" dist/Fussel-bin "${1:-0.0.0}"
