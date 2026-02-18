#!/bin/bash
set -euo pipefail

PRODUCT_NAME="HiMilo"
BUILD_DIR=".build/release"
INSTALL_DIR="/usr/local/bin"
CLI_NAME="milo"

if [ ! -f "${BUILD_DIR}/${PRODUCT_NAME}" ]; then
    echo "Binary not found. Building first..."
    swift build -c release
fi

echo "Installing ${CLI_NAME} to ${INSTALL_DIR}..."

BINARY_PATH="$(cd "${BUILD_DIR}" && pwd)/${PRODUCT_NAME}"

if [ -L "${INSTALL_DIR}/${CLI_NAME}" ] || [ -f "${INSTALL_DIR}/${CLI_NAME}" ]; then
    echo "Removing existing ${INSTALL_DIR}/${CLI_NAME}..."
    rm -f "${INSTALL_DIR}/${CLI_NAME}"
fi

ln -s "${BINARY_PATH}" "${INSTALL_DIR}/${CLI_NAME}"
echo "Installed: ${INSTALL_DIR}/${CLI_NAME} -> ${BINARY_PATH}"
echo ""
echo "Usage:"
echo "  milo \"Hello, world!\""
echo "  echo \"Read this\" | milo"
echo "  milo --clipboard"
echo "  milo --listen"
echo "  milo  # (menu bar mode)"
