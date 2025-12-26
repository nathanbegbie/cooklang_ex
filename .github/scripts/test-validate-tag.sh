#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/validate-tag.sh"

failures=0

expect_valid() {
  if validate_tag "$1" > /dev/null 2>&1; then
    echo "✓ $1 (valid as expected)"
  else
    echo "✗ $1 (expected valid, got invalid)"
    ((failures++))
  fi
}

expect_invalid() {
  if validate_tag "$1" > /dev/null 2>&1; then
    echo "✗ $1 (expected invalid, got valid)"
    ((failures++))
  else
    echo "✓ $1 (invalid as expected)"
  fi
}

echo "Testing valid tags..."
expect_valid "1.2.3"
expect_valid "0.0.1"
expect_valid "12.345.6"
expect_valid "1.2.3-rc1"
expect_valid "1.2.3-alpha1"
expect_valid "1.2.3-beta12"

echo ""
echo "Testing invalid tags..."
expect_invalid "v1.2.3"
expect_invalid "1.2"
expect_invalid "1.2.3.4"
expect_invalid "1.2.3-"
expect_invalid "1.2.3-rc"
expect_invalid "1.2.3-gamma1"
expect_invalid "a.b.c"
expect_invalid ""

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All tests passed!"
  exit 0
else
  echo "$failures test(s) failed"
  exit 1
fi
