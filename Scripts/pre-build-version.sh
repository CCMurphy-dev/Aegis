#!/bin/bash
# Pre-build script to sync VERSION to Info.plist
# Run this before xcodebuild

cd "$(dirname "$0")/.."
VERSION=$(cat VERSION | tr -d '[:space:]')

if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "Aegis/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "Aegis/Info.plist"
    echo "Updated Info.plist to version $VERSION"
fi
