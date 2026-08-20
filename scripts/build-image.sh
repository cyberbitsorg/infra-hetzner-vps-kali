#!/usr/bin/env bash
# Phase 0 (one-time): image a throwaway Hetzner server with the Kali
# GenericCloud disk via the rescue system, snapshot it, and print the
# snapshot ID for terraform.tfvars. Requires: hcloud CLI, an SSH key
# already in Hetzner, HCLOUD_TOKEN in env.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091 # dynamic path; resolves fine at runtime
source "$HERE/lib/kali-image.sh"

SERVER_NAME="${SERVER_NAME:-kali-imagebuilder}"
SERVER_TYPE="${SERVER_TYPE:-cx33}"
LOCATION="${LOCATION:-fsn1}"
SSH_KEY_NAME="${SSH_KEY_NAME:-main-deploy-key}"
BASE_IMAGE="${BASE_IMAGE:-debian-12}" # throwaway OS; we overwrite the disk
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need hcloud; need ssh; need curl

log() { printf '==> %s\n' "$*" >&2; }

# Resolve the image URL up front so a --dry-run proves the lib wiring.
log "Resolving current Kali GenericCloud image..."
INDEX_HTML="$(curl -fsSL "$KALI_BASE_URL")"
IMG_URL="$(kali_image_url "$INDEX_HTML")"
log "Image: $IMG_URL"

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry-run: would create $SERVER_NAME ($SERVER_TYPE/$LOCATION), image the disk, snapshot, and delete."
  exit 0
fi

: "${HCLOUD_TOKEN:?export HCLOUD_TOKEN first}"

cleanup() { hcloud server delete "$SERVER_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

log "Creating throwaway server..."
hcloud server create --name "$SERVER_NAME" --type "$SERVER_TYPE" \
  --location "$LOCATION" --image "$BASE_IMAGE" --ssh-key "$SSH_KEY_NAME" >/dev/null
IP="$(hcloud server ip "$SERVER_NAME")"

log "Enabling rescue and rebooting into it..."
hcloud server enable-rescue "$SERVER_NAME" --ssh-key "$SSH_KEY_NAME" >/dev/null
hcloud server reboot "$SERVER_NAME" >/dev/null
# Wait for the rescue SSH to answer.
for _ in $(seq 1 30); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$IP" true 2>/dev/null && break
  sleep 5
done

log "Writing Kali image to /dev/sda inside rescue..."
SUMS="$(curl -fsSL "${KALI_BASE_URL}SHA256SUMS")"
WANT_SHA="$(printf '%s\n' "$SUMS" | awk -v b="$(basename "$IMG_URL")" '$2==b || $2=="*"b {print $1; exit}')"
[ -n "$WANT_SHA" ] || { echo "no checksum entry for image" >&2; exit 1; }
# Run the download+verify+dd on the rescue box itself (its bandwidth, its disk).
# Stream the tarball once: tee its sha256 to a side file while extracting
# disk.raw straight through to /dev/sda, then verify before we trust it.
ssh -o StrictHostKeyChecking=no "root@$IP" bash -s -- "$IMG_URL" "$WANT_SHA" <<'REMOTE'
set -euo pipefail
url="$1"; want="$2"; file="$(basename "$url")"
cd /root
# Stream: compute sha256 of the compressed tarball while extracting disk.raw straight to the disk.
curl -fL "$url" \
  | tee >(sha256sum | awk '{print $1}' > /root/dl.sha) \
  | tar -xJO disk.raw \
  | dd of=/dev/sda bs=4M status=progress
sync
got="$(cat /root/dl.sha)"
if [ "$want" != "$got" ]; then
  echo "CHECKSUM MISMATCH for $file: want=$want got=$got" >&2
  exit 1
fi
echo "checksum OK: $file"
REMOTE

log "Disabling rescue and rebooting into Kali..."
hcloud server disable-rescue "$SERVER_NAME" >/dev/null
hcloud server reboot "$SERVER_NAME" >/dev/null
for _ in $(seq 1 30); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "kali@$IP" true 2>/dev/null && break
  sleep 5
done

log "Creating snapshot..."
SNAP_ID="$(hcloud server create-image --type snapshot \
  --description "kali-genericcloud-$(date +%Y%m%d)" \
  --label os=kali,role=attacker "$SERVER_NAME" -o noheader -o columns=image 2>/dev/null \
  || hcloud image list -o noheader -o columns=id -l os=kali | head -n1)"

log "Snapshot ready. Put this in terraform.tfvars server_image:"
printf '%s\n' "$SNAP_ID"
