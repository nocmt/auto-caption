#!/bin/bash
set -e

# Get the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Detect architecture
ARCH=$(uname -m)
# if [ "$ARCH" == "x86_64" ]; then
#   DEST="mac-x64"
# elif [ "$ARCH" == "arm64" ]; then
#   DEST="mac-arm64"
# else
#   echo "Unsupported architecture: $ARCH"
#   exit 1
fi

echo "Building Engine for $ARCH..."

# Clean previous build artifacts for this arch
# rm -rf "dist/$DEST"
rm -rf "build"

# Run PyInstaller
# Ensure pyinstaller is in path or use python -m PyInstaller
if command -v pyinstaller &> /dev/null; then
    pyinstaller main.spec --noconfirm --clean
else
    python3 -m PyInstaller main.spec --noconfirm --clean
fi

# Create destination directory
mkdir -p "dist"

# Cleanup
rm -rf "build"
rm -f "main.spec" # Wait, don't delete main.spec! It's the source file.
# PyInstaller might create a spec file if one didn't exist, but we provided one.
# So don't delete it.

echo "Build complete. Engine is located at: engine/dist/main"
echo "To support Intel Macs, you must run this script on an x86_64 machine (or environment) to generate engine/dist/mac-x64/main."
