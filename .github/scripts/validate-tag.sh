#!/usr/bin/env bash
set -euo pipefail

validate_tag() {
  local tag="$1"

  if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(rc|alpha|beta)[0-9]+)?$ ]]; then
    echo "Invalid tag format: $tag" >&2
    echo "Expected format: X.Y.Z or X.Y.Z-suffix (e.g., 1.2.3, 1.2.3-rc1, 1.2.3-alpha1)" >&2
    return 1
  fi

  echo "Valid tag: $tag"
  return 0
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <tag>" >&2
    exit 1
  fi
  validate_tag "$1"
fi
