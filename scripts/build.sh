#!/usr/bin/env bash
set -euo pipefail

# MenuWrangler Build & Deploy Script
# Prevents Gatekeeper issues, cleans Dropbox artifacts, and performs deep code signing.

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_DIR"

# 1. Clean conflict files and temporary build dirs in workspace
echo "🧹 Cleaning conflicted copies and local build artifacts..."
find . -name "*conflicted copy*" -delete 2>/dev/null || true
rm -rf build DerivedData

# 2. Compile using standard Xcode derived data (outside Dropbox sync)
echo "🔨 Compiling MenuWrangler..."
xcodebuild \
  -project Ice.xcodeproj \
  -scheme Ice \
  -configuration Debug \
  DEVELOPMENT_TEAM="5K6TS92SYQ" \
  CODE_SIGN_IDENTITY="Apple Development" \
  build

DERIVED_APP_PATH="$(xcodebuild -project Ice.xcodeproj -scheme Ice -showBuildSettings | grep -m 1 ' TARGET_BUILD_DIR =' | awk -F '=' '{print $2}' | tr -d ' ')/MenuWrangler.app"

if [ ! -d "$DERIVED_APP_PATH" ]; then
  # Fallback to standard derived data location
  DERIVED_APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/Ice-gjandllfzqibddcbsodptgtlrvkk/Build/Products/Debug/MenuWrangler.app"
fi

if [ ! -d "$DERIVED_APP_PATH" ]; then
  echo "❌ Error: Could not find built MenuWrangler.app"
  exit 1
fi

echo "📦 Installing to /Applications/MenuWrangler.app..."
killall MenuWrangler Ice 2>/dev/null || true
rm -rf /Applications/MenuWrangler.app /Applications/Ice.app
cp -R "$DERIVED_APP_PATH" /Applications/MenuWrangler.app

# 3. Deep sign and strip quarantine flags to prevent Gatekeeper damage alerts
echo "🔏 Signing with Apple Development Certificate & removing quarantine..."
codesign --force --deep --sign "Apple Development: jacob.winkler@mac.com (34WGK88W63)" /Applications/MenuWrangler.app
xattr -cr /Applications/MenuWrangler.app

echo "🚀 Launching MenuWrangler..."
open /Applications/MenuWrangler.app

echo "✅ Build & Deployment Complete!"
