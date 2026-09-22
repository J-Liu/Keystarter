#!/bin/bash
# setup-sparkle.sh
# Generates Sparkle EdDSA key pair for automatic updates.
# Run this once after installing Sparkle.

set -e

# Check if generate_keys exists
if command -v generate_keys &> /dev/null; then
    GENERATE_KEYS="generate_keys"
else
    # Try common locations
    if [ -f "/Applications/Sparkle/bin/generate_keys" ]; then
        GENERATE_KEYS="/Applications/Sparkle/bin/generate_keys"
    else
        echo "Error: generate_keys not found."
        echo "Download Sparkle from: https://github.com/sparkle-project/Sparkle/releases"
        echo "Then extract and copy bin/generate_keys to /usr/local/bin or /Applications/Sparkle/bin/"
        exit 1
    fi
fi

echo "==> Generating Sparkle EdDSA key pair..."
echo ""

# Run generate_keys - this will save private key to keychain and print public key
"$GENERATE_KEYS"

echo ""
echo "==> Done!"
echo ""
echo "Next steps:"
echo "1. Copy the Public EdDSA key shown above"
echo "2. Update Resources/Info.plist:"
echo "   - Set SUPublicEDKey to your public key"
echo "   - Set SUFeedURL to your appcast.xml URL"
echo ""
echo "3. Create your first release:"
echo "   ./scripts/build-app.sh"
echo "   cd build && zip -r Keystarter-X.X.X.zip Keystarter.app"
echo "   sign_update Keystarter-X.X.X.zip"
echo "   # Update docs/appcast.xml with signature and length"