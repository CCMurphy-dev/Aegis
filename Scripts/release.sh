#!/bin/bash
# Aegis Release Script
# Usage: ./scripts/release.sh [version]
# If no version provided, reads from VERSION file

set -e

cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Aegis Release Script ===${NC}"

# Get version
if [ -n "$1" ]; then
    VERSION="$1"
    echo "$VERSION" > VERSION
    echo -e "Version set to: ${YELLOW}$VERSION${NC}"
else
    VERSION=$(cat VERSION | tr -d '[:space:]')
    echo -e "Using VERSION file: ${YELLOW}$VERSION${NC}"
fi

if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: No version specified${NC}"
    exit 1
fi

# Step 1: Sync version to Info.plist
echo -e "\n${GREEN}[1/6] Syncing version to Info.plist...${NC}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "Aegis/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "Aegis/Info.plist"
echo "Info.plist updated to $VERSION"

# Step 2: Build Release
echo -e "\n${GREEN}[2/6] Building Release configuration...${NC}"
xcodebuild -scheme Aegis -configuration Release -derivedDataPath build clean build 2>&1 | tail -5

# Verify version in built app
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Build/Products/Release/Aegis.app/Contents/Info.plist)
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo -e "${RED}Error: Built version ($BUILT_VERSION) doesn't match expected ($VERSION)${NC}"
    exit 1
fi
echo -e "Build successful, version verified: ${GREEN}$BUILT_VERSION${NC}"

# Step 3: Create zip
echo -e "\n${GREEN}[3/6] Creating release zip...${NC}"
rm -f /tmp/Aegis.app.zip
ditto -c -k --keepParent build/Build/Products/Release/Aegis.app /tmp/Aegis.app.zip
FILE_SIZE=$(stat -f%z /tmp/Aegis.app.zip)
echo "Created /tmp/Aegis.app.zip ($FILE_SIZE bytes)"

# Step 4: Sign with Sparkle
echo -e "\n${GREEN}[4/6] Signing with Sparkle...${NC}"
SPARKLE_SIGN="./build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -f "$SPARKLE_SIGN" ]; then
    echo -e "${RED}Error: Sparkle sign_update not found at $SPARKLE_SIGN${NC}"
    echo "Run a build in Xcode first to fetch Sparkle package"
    exit 1
fi

SIGN_OUTPUT=$($SPARKLE_SIGN /tmp/Aegis.app.zip)
echo "$SIGN_OUTPUT"

# Extract signature
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
if [ -z "$SIGNATURE" ]; then
    echo -e "${RED}Error: Could not extract signature${NC}"
    exit 1
fi

# Step 5: Update appcast.xml
echo -e "\n${GREEN}[5/6] Updating appcast.xml...${NC}"
APPCAST="Distribution/appcast.xml"
DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

# Check if this version already exists
if grep -q "sparkle:version>$VERSION<" "$APPCAST"; then
    echo -e "${YELLOW}Warning: Version $VERSION already exists in appcast.xml${NC}"
    echo "Updating existing entry..."
    # Update existing entry (signature and length)
    sed -i '' "/<sparkle:version>$VERSION<\/sparkle:version>/,/<\/item>/ {
        s/length=\"[^\"]*\"/length=\"$FILE_SIZE\"/
        s/sparkle:edSignature=\"[^\"]*\"/sparkle:edSignature=\"$SIGNATURE\"/
    }" "$APPCAST"
else
    echo "Adding new version entry..."
    # Create new item XML
    NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>$DATE</pubDate>
            <description><![CDATA[
                <h2>What's New in $VERSION</h2>
                <p>See CHANGELOG.md for details.</p>
            ]]></description>
            <enclosure
                url=\"https://github.com/CCMurphy-Dev/Aegis/releases/download/v$VERSION/Aegis.app.zip\"
                length=\"$FILE_SIZE\"
                type=\"application/octet-stream\"
                sparkle:edSignature=\"$SIGNATURE\" />
        </item>

        <!-- Previous Releases -->"

    # Insert after "<!-- Latest Release -->" line
    sed -i '' "s|<!-- Latest Release -->|<!-- Latest Release -->\n$NEW_ITEM|" "$APPCAST"

    # Remove duplicate "Previous Releases" comment if exists
    sed -i '' '/<!-- Previous Releases -->/{ N; /\n.*<!-- Previous Releases -->/d; }' "$APPCAST"
fi

echo "Appcast updated"

# Step 6: Summary
echo -e "\n${GREEN}=== Release Summary ===${NC}"
echo -e "Version:   ${YELLOW}$VERSION${NC}"
echo -e "File size: ${YELLOW}$FILE_SIZE${NC} bytes"
echo -e "Signature: ${YELLOW}${SIGNATURE:0:20}...${NC}"
echo -e "Zip:       ${YELLOW}/tmp/Aegis.app.zip${NC}"

echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo "1. Review and update CHANGELOG.md if needed"
echo "2. Review appcast.xml description"
echo "3. Commit and push:"
echo -e "   ${YELLOW}git add -A && git commit -m \"Release v$VERSION\" && git push origin main${NC}"
echo "4. Create GitHub release:"
echo -e "   ${YELLOW}gh release create v$VERSION /tmp/Aegis.app.zip --title \"v$VERSION\" --notes-file CHANGELOG.md${NC}"
echo ""
echo -e "Or run with ${YELLOW}--publish${NC} flag to do steps 3-4 automatically"
