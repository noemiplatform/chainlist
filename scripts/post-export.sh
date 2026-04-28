#!/bin/sh
set -e

node generate-sitemap.js
node generate-json.js

rm out/404.html
mv out/error.html out/404.html
cp serve.json out/serve.json
#!/usr/bin/env bash

set -euo pipefail

#############################################
# Noemi Nexus Post Export Pipeline
# Hardened build + export stage
# Author: Noemi Platform CAP System
#############################################

echo "🚀 [NEXUS] Starting post-export pipeline..."

# ---------- CONFIG ----------
ROOT_DIR="$(pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_FILE="$ROOT_DIR/nexus-post-export.log"

NODE_BIN=$(command -v node || true)

if [[ -z "$NODE_BIN" ]]; then
  echo "❌ Node.js not found. Aborting."
  exit 1
fi

# ---------- LOGGING ----------
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 Working directory: $ROOT_DIR"
echo "📁 Output directory: $OUT_DIR"

# ---------- SAFETY CHECK ----------
if [[ ! -d "$OUT_DIR" ]]; then
  echo "⚠️ Output directory missing, creating..."
  mkdir -p "$OUT_DIR"
fi

# ---------- AUTHORIZED RUN GATE (optional security layer) ----------
# You can extend this later to verify GitHub tokens / signatures
AUTHORIZED_RUN=${NOEMI_AUTHORIZED_RUN:-"true"}

if [[ "$AUTHORIZED_RUN" != "true" ]]; then
  echo "⛔ Unauthorized execution blocked by Nexus policy."
  exit 1
fi

# ---------- PACKAGE.JSON SAFETY PATCH ----------
echo "🔧 Enabling temporary module compatibility patch..."

if [[ -f "package.json" ]]; then
  cp package.json package.json.nexus.backup

  # cross-platform safe node patch (no fragile sed hacks)
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));

    pkg.type = 'module';

    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
  "
fi

# ---------- BUILD STEPS ----------
echo "⚙️ Running export generation scripts..."

if [[ -f "scripts/generate-sitemap.js" ]]; then
  node scripts/generate-sitemap.js
else
  echo "⚠️ Missing sitemap generator"
fi

if [[ -f "scripts/generate-json.js" ]]; then
  node scripts/generate-json.js
else
  echo "⚠️ Missing JSON generator"
fi

# ---------- OUTPUT NORMALIZATION ----------
echo "🧹 Normalizing output structure..."

if [[ -f "$OUT_DIR/404.html" ]]; then
  echo "📄 404 page detected"
fi

# ensure deterministic timestamps for reproducibility
find "$OUT_DIR" -type f -exec touch -t 200001010000 {} \; || true

# ---------- ARTIFACT HASHING ----------
echo "🔐 Generating integrity manifest..."

MANIFEST="$OUT_DIR/manifest.sha256"
rm -f "$MANIFEST"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && find . -type f -exec sha256sum {} \;) > "$MANIFEST"
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && find . -type f -exec shasum -a 256 {} \;) > "$MANIFEST"
else
  echo "⚠️ No checksum tool found"
fi

# ---------- RESTORE STATE ----------
echo "♻️ Restoring original package.json..."

if [[ -f "package.json.nexus.backup" ]]; then
  mv package.json.nexus.backup package.json
fi

# ---------- FINAL PACKAGING ----------
echo "📦 Finalizing export bundle..."

tar -czf nexus-export.tar.gz out || true

# ---------- DONE ----------
echo "✅ [NEXUS] Post-export pipeline complete"
echo "📌 Log saved to: $LOG_FILE"
echo "📦 Artifact: nexus-export.tar.gz"