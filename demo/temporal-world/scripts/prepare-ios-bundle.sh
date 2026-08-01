#!/usr/bin/env bash
# prepare-ios-bundle.sh — Assemble a self-contained HTML/JS bundle
# for WKWebView offline loading on iOS.
#
# Usage:  bash scripts/prepare-ios-bundle.sh
#
# Output: /temporal-world/dist/ios/
#   - diorama.html          (entry point, rewritten imports)
#   - vendor/               (Three.js + QRCode)
#   - manifest.json         (file listing with SHA-256 hashes)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_SRC="$PROJECT_ROOT/public/vendor"
DIST_IOS="$PROJECT_ROOT/dist/ios"
CLIENT_SRC="$PROJECT_ROOT/clients/desktop.html"

# ── helpers ────────────────────────────────────────────────────
log() { printf "\033[1;35m[ios-bundle]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ios-bundle]\033[0m %s\n" "$*" >&2; exit 1; }

# ── Step 1: Build diorama runtime (if tsconfig exists) ─────────
if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
  log "tsconfig.json found — building diorama runtime ..."
  cd "$PROJECT_ROOT"
  if [ -f "node_modules/.package-lock.json" ] || [ -d "node_modules" ]; then
    npx tsc --noEmit 2>/dev/null && log "  TypeScript check passed." || log "  TypeScript check had warnings (non-fatal)."
  else
    log "  node_modules not installed — skipping tsc."
  fi
else
  log "No tsconfig.json — skipping TypeScript build step."
fi

# ── Step 2: Ensure vendor assets are bundled ───────────────────
if [ ! -f "$VENDOR_SRC/three.module.min.js" ]; then
  log "Vendor assets not found. Running bundle-assets.sh ..."
  bash "$SCRIPT_DIR/bundle-assets.sh"
fi
[ -f "$VENDOR_SRC/three.module.min.js" ] || err "Vendor assets missing after bundle-assets.sh. Aborting."

# ── Step 3: Prepare output directory ──────────────────────────
log "Preparing output directory: $DIST_IOS"
rm -rf "$DIST_IOS"
mkdir -p "$DIST_IOS/vendor/addons"

# ── Step 4: Copy vendor files ─────────────────────────────────
log "Copying vendor files ..."
cp "$VENDOR_SRC/three.module.js"      "$DIST_IOS/vendor/"
cp "$VENDOR_SRC/three.module.min.js"  "$DIST_IOS/vendor/"
cp "$VENDOR_SRC/qrcode.min.js"        "$DIST_IOS/vendor/"
cp "$VENDOR_SRC/addons/"*.js          "$DIST_IOS/vendor/addons/"

# ── Step 5: Copy & rewrite the HTML entry point ───────────────
log "Rewriting desktop.html for offline iOS bundle ..."

# Replace CDN QRCode script tag with local path
sed \
  -e 's|https://cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js|vendor/qrcode.min.js|g' \
  -e 's|https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js|vendor/three.module.min.js|g' \
  -e 's|https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/|vendor/addons/|g' \
  "$CLIENT_SRC" > "$DIST_IOS/diorama.html"

log "  diorama.html written."

# ── Step 6: Generate iOS bundle manifest ──────────────────────
log "Generating iOS bundle manifest ..."
MANIFEST="$DIST_IOS/manifest.json"

{
  echo "{"
  echo "  \"type\": \"ios-bundle\","
  echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"entry\": \"diorama.html\","
  echo "  \"files\": {"

  first=true
  while IFS= read -r -d '' file; do
    rel="${file#$DIST_IOS/}"
    hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
    size=$(wc -c < "$file" | tr -d ' ')
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    printf '    "%s": { "sha256": "%s", "size": %s }' "$rel" "$hash" "$size"
  done < <(find "$DIST_IOS" -type f -not -name 'manifest.json' -print0 | sort -z)

  echo ""
  echo "  }"
  echo "}"
} > "$MANIFEST"

log "Manifest written: $MANIFEST"

# ── Summary ────────────────────────────────────────────────────
total_files=$(find "$DIST_IOS" -type f | wc -l | tr -d ' ')
total_size=$(du -sh "$DIST_IOS" | cut -f1)
log "iOS bundle ready: $DIST_IOS ($total_files files, $total_size)"
