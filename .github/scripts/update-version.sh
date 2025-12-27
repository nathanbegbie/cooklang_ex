#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.0.2"
  exit 1
fi

VERSION="$1"

# Update the VERSION file
echo "$VERSION" > VERSION

echo "Updated VERSION file to $VERSION"
