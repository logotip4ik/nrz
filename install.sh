#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
REPO="logotip4ik/nrz"

# --- Detect System ---
# Get OS and architecture
OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"
TARGET_OS=""
TARGET_ARCH=""
EXTENSION=""

# Determine OS and the correct file extension
case "$OS_RAW" in
  Linux)
    TARGET_OS="linux"
    EXTENSION="tar.gz"
    ;;
  Darwin)
    TARGET_OS="macos"
    EXTENSION="tar.gz"
    ;;
  *)
    echo "Error: Unsupported operating system '$OS_RAW'."
    exit 1
    ;;
esac

# Normalize architecture name
case "$ARCH_RAW" in
  x86_64)
    TARGET_ARCH="x86_64"
    ;;
  aarch64 | arm64)
    TARGET_ARCH="aarch64"
    ;;
  *)
    echo "Error: Unsupported architecture '$ARCH_RAW'."
    exit 1
    ;;
esac

# --- GitHub API ---
# Construct the expected asset filename based on detected system
ASSET_NAME="nrz-${TARGET_OS}-${TARGET_ARCH}.${EXTENSION}"

echo "System detected: ${TARGET_OS}-${TARGET_ARCH}"
echo "Looking for asset: ${ASSET_NAME}"

# Fetch the latest release data from the GitHub API
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

echo "Fetching latest release information from GitHub..."

# Use jq to parse the JSON response, which is more robust than grep/cut
# If jq is not installed, it falls back to a grep/cut method.
if command -v jq &> /dev/null; then
    DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url")
else
    echo "Warning: 'jq' is not installed. Using a less reliable fallback to find the URL."
    DOWNLOAD_URL=$(curl -s "$API_URL" | grep "browser_download_url.*${ASSET_NAME}" | cut -d '"' -f 4)
fi

# Check if a download URL was found
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
  echo "Error: Could not find a download URL for your system ($ASSET_NAME)."
  echo "Please check the releases page for available assets: https://github.com/${REPO}/releases"
  exit 1
fi

# --- Download and Extract ---
echo "Downloading from: $DOWNLOAD_URL"
curl -sL -o "$ASSET_NAME" "$DOWNLOAD_URL"

echo "Extracting ${ASSET_NAME}..."
# Use the correct extraction tool based on the file extension
if [ "$EXTENSION" == "zip" ]; then
  unzip -o "$ASSET_NAME"
else # .tar.gz
  tar -xzf "$ASSET_NAME"
fi

# --- Cleanup ---
echo "Cleaning up..."
rm "$ASSET_NAME"

echo "✅ Successfully downloaded and extracted the 'nrz' executable to the current directory."
