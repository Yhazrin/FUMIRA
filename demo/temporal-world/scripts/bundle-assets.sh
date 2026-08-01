#!/usr/bin/env bash
# bundle-assets.sh — Download Three.js r170 + QRCode.js into public/vendor/
# so that the WKWebView can run fully offline.
#
# Usage:  bash scripts/bundle-assets.sh
# Idempotent: re-downloads only if files are missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/public/vendor"

THREE_VERSION="0.170.0"
THREE_CDN="https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}"
# 1.5.1 is the last version that ships build/qrcode.min.js (browser UMD bundle).
# 1.5.4 removed the build/ directory; its lib/browser.min.js is CJS, not browser-ready.
QRCODE_CDN="https://cdn.jsdelivr.net/npm/qrcode@1.5.1/build/qrcode.min.js"

# ── helpers ────────────────────────────────────────────────────
log() { printf "\033[1;36m[bundle]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[bundle]\033[0m %s\n" "$*" >&2; exit 1; }

download() {
  local url="$1" dest="$2"
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    log "  exists: $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  log "  downloading: $url"
  if command -v curl &>/dev/null; then
    curl -fSL --retry 3 --retry-delay 2 -o "$dest" "$url" || err "curl failed: $url"
  elif command -v wget &>/dev/null; then
    wget -q -O "$dest" "$url" || err "wget failed: $url"
  else
    err "Neither curl nor wget found. Install one to continue."
  fi
  # Verify non-empty
  [ -s "$dest" ] || err "Downloaded empty file: $dest"
}

# ── Create directories ─────────────────────────────────────────
mkdir -p "$VENDOR_DIR/addons"

# ── Three.js core ──────────────────────────────────────────────
log "Bundling Three.js r${THREE_VERSION} ..."

# Full (unminified) build — useful for debug
download "${THREE_CDN}/build/three.module.js"     "$VENDOR_DIR/three.module.js"

# Minified build — production default
download "${THREE_CDN}/build/three.module.min.js"  "$VENDOR_DIR/three.module.min.js"

# ── Three.js addons (only what desktop.html imports) ───────────
log "Bundling Three.js addons ..."
download "${THREE_CDN}/examples/jsm/controls/OrbitControls.js"  "$VENDOR_DIR/addons/OrbitControls.js"

# WebGLRenderer is part of three core in r170 — no separate addon file needed.
# Create a thin re-export shim so the importmap "three/addons/" path resolves cleanly.
if [ ! -f "$VENDOR_DIR/addons/WebGLRenderer.js" ]; then
  log "  creating shim: addons/WebGLRenderer.js (re-exports from core)"
  cat > "$VENDOR_DIR/addons/WebGLRenderer.js" <<'SHIM'
// Re-export WebGLRenderer from three core.
// In r170+ the renderer lives inside the main bundle.
export { WebGLRenderer } from '../three.module.min.js';
SHIM
fi

# ── QRCode.js ──────────────────────────────────────────────────
log "Bundling QRCode.js ..."
download "$QRCODE_CDN" "$VENDOR_DIR/qrcode.min.js"

# ── Vendor manifest ────────────────────────────────────────────
log "Generating vendor manifest ..."
MANIFEST="$VENDOR_DIR/manifest.json"

# Collect all files with SHA-256 hashes
{
  echo "{"
  echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"threeVersion\": \"${THREE_VERSION}\","
  echo "  \"files\": {"

  first=true
  while IFS= read -r -d '' file; do
    rel="${file#$VENDOR_DIR/}"
    hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
    size=$(wc -c < "$file" | tr -d ' ')
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    printf '    "%s": { "sha256": "%s", "size": %s }' "$rel" "$hash" "$size"
  done < <(find "$VENDOR_DIR" -type f -not -name 'manifest.json' -print0 | sort -z)

  echo ""
  echo "  }"
  echo "}"
} > "$MANIFEST"

log "Manifest written: $MANIFEST"
log "Done. All vendor assets bundled in: $VENDOR_DIR"
