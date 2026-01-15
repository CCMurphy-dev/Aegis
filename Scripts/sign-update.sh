#!/bin/bash
# Sign an Aegis release for Sparkle updates
# Usage: ./scripts/sign-update.sh /path/to/Aegis.app.zip

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PRIVATE_KEY="$PROJECT_DIR/.sparkle-keys/sparkle_private.pem"

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-app-zip>"
    echo "Example: $0 /tmp/Aegis.app.zip"
    exit 1
fi

ZIP_FILE="$1"

if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: File not found: $ZIP_FILE"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key not found at $PRIVATE_KEY"
    echo "Generate keys first with: openssl genpkey -algorithm ed25519 -out $PRIVATE_KEY"
    exit 1
fi

# Get file size
FILE_SIZE=$(stat -f%z "$ZIP_FILE" 2>/dev/null || stat -c%s "$ZIP_FILE")

# Generate EdDSA signature
# Sparkle expects base64-encoded signature of the file's SHA-512 hash
echo "Generating EdDSA signature..."

# Create signature using openssl
SIGNATURE=$(openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -rawin -in <(openssl dgst -sha512 -binary "$ZIP_FILE") | base64)

echo ""
echo "=== Sparkle Update Information ==="
echo "File: $ZIP_FILE"
echo "Size: $FILE_SIZE bytes"
echo ""
echo "EdDSA Signature:"
echo "$SIGNATURE"
echo ""
echo "=== Appcast Entry ==="
echo "Replace SIGNATURE_PLACEHOLDER in appcast.xml with the signature above"
echo ""
echo "sparkle:edSignature=\"$SIGNATURE\""
echo "length=\"$FILE_SIZE\""
