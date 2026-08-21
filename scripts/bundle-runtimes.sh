#!/bin/zsh
# Populates app/Resources with everything the .app needs to run with no
# third-party installs:
#   bin/node            portable Node.js (official tarball)
#   bin/ffmpeg,ffprobe  static builds (evermeet.cx)
#   bin/yt-dlp          standalone binary (self-updating with -U)
#   bin/mg-transcribe   the SpeechAnalyzer CLI, built here
#   worker/             the node worker incl. node_modules and the
#                       downloaded headless browser
# Safe to re-run; skips downloads that already exist.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/app/Resources"
BIN="$RES/bin"
CACHE="$ROOT/.runtime-cache"
NODE_VERSION="22.19.0"

mkdir -p "$BIN" "$CACHE"

echo "==> node $NODE_VERSION"
NODE_TAR="$CACHE/node-v$NODE_VERSION-darwin-arm64.tar.gz"
if [ ! -f "$NODE_TAR" ]; then
  curl -fL "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.gz" -o "$NODE_TAR"
fi
tar -xzf "$NODE_TAR" -C "$CACHE"
/bin/cp "$CACHE/node-v$NODE_VERSION-darwin-arm64/bin/node" "$BIN/node"

echo "==> ffmpeg + ffprobe (static)"
for tool in ffmpeg ffprobe; do
  if [ ! -f "$CACHE/$tool.zip" ]; then
    curl -fL "https://evermeet.cx/ffmpeg/getrelease/$tool/zip" -o "$CACHE/$tool.zip"
  fi
  unzip -oq "$CACHE/$tool.zip" -d "$BIN"
done

echo "==> yt-dlp"
if [ ! -f "$CACHE/yt-dlp_macos" ]; then
  curl -fL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" -o "$CACHE/yt-dlp_macos"
fi
/bin/cp "$CACHE/yt-dlp_macos" "$BIN/yt-dlp"
chmod +x "$BIN/yt-dlp"

echo "==> mg-transcribe"
swiftc -O -parse-as-library -o "$BIN/mg-transcribe" "$ROOT/transcriber/Transcribe.swift"

echo "==> worker (incl. node_modules and headless browser)"
/bin/rm -rf "$RES/worker"
rsync -a --exclude ".DS_Store" "$ROOT/worker/" "$RES/worker/"

echo "==> done"
du -sh "$RES/bin" "$RES/worker"
