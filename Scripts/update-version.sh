#!/bin/bash

# Update Version Script
# Reads version from VERSION file and updates project.pbxproj
# Run this before building or as part of your workflow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_ROOT/VERSION"
PROJECT_FILE="$PROJECT_ROOT/Aegis.xcodeproj/project.pbxproj"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: VERSION file not found at $VERSION_FILE"
    exit 1
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

if [ -z "$VERSION" ]; then
    echo "Error: VERSION file is empty"
    exit 1
fi

echo "Updating MARKETING_VERSION to $VERSION"

# Update all MARKETING_VERSION entries in the project file
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"

# Verify the update
COUNT=$(grep -c "MARKETING_VERSION = $VERSION;" "$PROJECT_FILE")
echo "Updated $COUNT MARKETING_VERSION entries to $VERSION"
