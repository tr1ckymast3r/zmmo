#!/bin/bash
# Cross-compile manager-agent for all target platforms
set -e

cd "$(dirname "$0")"

echo "🔨 Building manager-agent v1.1.0 (systray on Windows/macOS)..."
echo ""

# Windows — systray, no console window
echo -n "  windows/amd64 → zmmo-agent-windows-amd64.exe ... "
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w -H windowsgui" -o ../../assets/zmmo-agent-windows-amd64.exe . 2>&1
SIZE=$(du -h ../../assets/zmmo-agent-windows-amd64.exe | cut -f1)
echo "✅ ($SIZE)"

# Linux — headless (no systray on headless servers)
echo -n "  linux/amd64 → zmmo-agent-linux-amd64 ... "
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../../assets/zmmo-agent-linux-amd64 . 2>&1
SIZE=$(du -h ../../assets/zmmo-agent-linux-amd64 | cut -f1)
echo "✅ ($SIZE)"

echo ""
echo "⚠️  macOS builds require macOS SDK (CGo). Build on a Mac:"
echo "   GOOS=darwin GOARCH=amd64 go build -ldflags=\"-s -w\" -o zmmo-agent-darwin-amd64 ."
echo "   GOOS=darwin GOARCH=arm64 go build -ldflags=\"-s -w\" -o zmmo-agent-darwin-arm64 ."
echo ""
echo "📦 Binaries:"
ls -lh ../../assets/zmmo-agent-* 2>/dev/null
