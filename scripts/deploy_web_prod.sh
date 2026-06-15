#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_ROOT="/var/www/duoyi"
FLUTTER_BIN="${FLUTTER_BIN:-/home/ubuntu/flutter/bin/flutter}"

echo "=================================================="
echo "Duoyi Web Production Deployment"
echo "=================================================="
echo ""
echo "Project root: $PROJECT_ROOT"
echo "Web root: $WEB_ROOT"
echo "Flutter: $FLUTTER_BIN"
echo ""

cd "$PROJECT_ROOT"

# 1. 检查版本号
echo "📋 Checking version..."
VERSION_NAME=$(grep "static const name = " lib/core/app_version.dart | sed -E "s/.*'([^']+)'.*/\1/")
VERSION_CODE=$(grep "static const build = " lib/core/app_version.dart | sed -E "s/.*= ([0-9]+);/\1/")
PUBSPEC_VERSION=$(grep "^version: " pubspec.yaml | sed -E "s/version: ([0-9.]+)\+.*/\1/")

if [ "$VERSION_NAME" != "$PUBSPEC_VERSION" ]; then
    echo "❌ Version mismatch:"
    echo "   app_version.dart: $VERSION_NAME"
    echo "   pubspec.yaml: $PUBSPEC_VERSION"
    exit 1
fi

echo "   Version: $VERSION_NAME (build $VERSION_CODE)"
echo ""

# 2. 构建 Web
echo "🔨 Building web (release)..."
$FLUTTER_BIN build web --release --dart-define=DUOYI_SERVER_URL=
echo ""

# 3. 备份旧版本
if [ -d "$WEB_ROOT" ] && [ "$(ls -A $WEB_ROOT 2>/dev/null)" ]; then
    BACKUP_DIR="$WEB_ROOT.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backing up old version to $BACKUP_DIR..."
    sudo cp -r "$WEB_ROOT" "$BACKUP_DIR"
    echo "   Old version backed up"
    echo ""
fi

# 4. 部署新版本
echo "🚀 Deploying to $WEB_ROOT..."
sudo rm -rf "$WEB_ROOT"/*
sudo cp -r "$PROJECT_ROOT/build/web/"* "$WEB_ROOT/"
echo "   Files copied"
echo ""

# 5. 验证部署
echo "✅ Verifying deployment..."
if [ -f "$WEB_ROOT/version.json" ]; then
    DEPLOYED_VERSION=$(cat "$WEB_ROOT/version.json" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo "   Deployed version: $DEPLOYED_VERSION"
    if [ "$DEPLOYED_VERSION" = "$VERSION_NAME" ]; then
        echo "   ✓ Version match"
    else
        echo "   ⚠ Version mismatch: expected $VERSION_NAME, got $DEPLOYED_VERSION"
    fi
else
    echo "   ⚠ version.json not found"
fi

if [ -f "$WEB_ROOT/index.html" ]; then
    echo "   ✓ index.html exists"
else
    echo "   ❌ index.html missing"
    exit 1
fi

if [ -f "$WEB_ROOT/main.dart.js" ]; then
    SIZE=$(du -h "$WEB_ROOT/main.dart.js" | cut -f1)
    echo "   ✓ main.dart.js exists ($SIZE)"
else
    echo "   ❌ main.dart.js missing"
    exit 1
fi

echo ""
echo "=================================================="
echo "✅ Web deployment completed successfully!"
echo "=================================================="
echo ""
echo "Deployed: v$VERSION_NAME (build $VERSION_CODE)"
echo "Location: $WEB_ROOT"
echo "Access: http://127.0.0.1/duoyi/"
echo ""
echo "Note: Users may need to hard refresh (Ctrl+Shift+R) to see the new version."
echo ""
