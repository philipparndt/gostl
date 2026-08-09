#!/bin/bash
# Script to set version information in the Swift app
# Usage: ./GoSTL-Swift/scripts/set-version.sh [version] [commit] [date]
# If no arguments provided, uses "dev" defaults

VERSION="${1:-dev}"
COMMIT="${2:-unknown}"
BUILD_DATE="${3:-unknown}"

# Resolved from the script's own location rather than the working directory:
# builds now run from the repository root, where the manifest is, while the
# sources this writes into are still one directory down. A relative path would
# quietly write the file somewhere else and ship an unversioned build.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../GoSTL/App/VersionInfo.swift"

cat > "$VERSION_FILE" << EOF
// This file is auto-generated during build. Do not edit manually.
import Foundation

/// Build-time version information
enum VersionInfo {
    static let version = "$VERSION"
    static let gitCommit = "$COMMIT"
    static let buildDate = "$BUILD_DATE"
}
EOF

echo "Version info written to $VERSION_FILE"
echo "  Version: $VERSION"
echo "  Commit: $COMMIT"
echo "  Date: $BUILD_DATE"
