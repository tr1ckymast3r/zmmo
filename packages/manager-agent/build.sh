#!/bin/bash
# Cross-compile manager-agent for all target platforms
set -e

PLATFORMS=(
  "linux:amd64:manager-agent"
  "windows:amd64:manager-agent.exe"
  "darwin:amd64:manager-agent-darwin-amd64"
  "darwin:arm64:manager-agent-darwin-arm64"
)

cd "$(dirname "$0")"

echo "🔨 Building manager-agent..."
for p in "${PLATFORMS[@]}"; do
  IFS=':' read -r GOOS GOARCH OUTPUT <<< "$p"
  echo -n "  $GOOS/$GOARCH → $OUTPUT ... "
  GOOS=$GOOS GOARCH=$GOARCH go build -ldflags="-s -w" -o "$OUTPUT" . 2>&1
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  echo "✅ ($SIZE)"
done

echo ""
echo "📦 Binaries:"
ls -lh manager-agent manager-agent.exe manager-agent-darwin-*
