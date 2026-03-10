#!/bin/bash
set -euo pipefail

APP_NAME="BetterFinder"
SCHEME="BetterFinder"
PROJECT="BetterFinder.xcodeproj"
INSTALL_DIR="/Applications"
BUILD_DIR=$(mktemp -d)

echo "Building $APP_NAME (Release)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build product not found at $APP_PATH"
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "Installing to $INSTALL_DIR/$APP_NAME.app..."
rsync -a --delete "$APP_PATH/" "$INSTALL_DIR/$APP_NAME.app/"

rm -rf "$BUILD_DIR"

echo "Done. $APP_NAME installed to $INSTALL_DIR/$APP_NAME.app"
