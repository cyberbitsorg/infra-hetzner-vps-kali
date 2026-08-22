#!/usr/bin/env bash
# Pure, testable helpers for locating and verifying the Kali GenericCloud image.
set -euo pipefail

KALI_BASE_URL="${KALI_BASE_URL:-https://kali.download/cloud-images/current/}"

# Print the absolute URL of the amd64 GenericCloud disk artifact.
# Kali ships GenericCloud only as a .tar.xz containing disk.raw; match that
# exactly (not the .torrent sibling, not arm64).
kali_image_url() {
  local html="$1" file
  file="$(printf '%s\n' "$html" \
    | grep -oE 'kali-linux-[0-9.]+-cloud-genericcloud-amd64\.tar\.xz(\.torrent)?' \
    | grep -v '\.torrent$' \
    | head -n1 || true)"
  [ -n "$file" ] || { echo "no amd64 genericcloud artifact found" >&2; return 1; }
  printf '%s%s\n' "$KALI_BASE_URL" "$file"
}

# Print the expected sha256 for BASENAME from a SHA256SUMS body, or fail.
kali_want_sha() {
  local base="$1" sums="$2" want
  want="$(printf '%s\n' "$sums" | awk -v b="$base" '$2==b || $2=="*"b {print $1; exit}')"
  [ -n "$want" ] || { echo "no checksum entry for $base" >&2; return 1; }
  printf '%s\n' "$want"
}

# The Packer build verifies checksums inline on the rescue host while
# streaming the download, so it does not call this helper on its hot path;
# this exists for the test suite and as a reusable utility for callers that
# have a file.
# Verify FILE against the SHA256SUMS body (portable: shasum or sha256sum).
kali_verify_checksum() {
  local file="$1" sums="$2" base want got
  base="$(basename "$file")"
  want="$(kali_want_sha "$base" "$sums")" || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$file" | awk '{print $1}')"
  else
    got="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  [ "$want" = "$got" ] || { echo "checksum mismatch for $base" >&2; return 1; }
}
