#!/usr/bin/env bats
load_lib() { source "${BATS_TEST_DIRNAME}/../scripts/lib/kali-image.sh"; }

@test "kali_image_url prefers the amd64 raw.xz artifact" {
  load_lib
  html='<a href="kali-linux-2026.2-cloud-genericcloud-amd64.qcow2">q</a>
        <a href="kali-linux-2026.2-cloud-genericcloud-amd64.raw.xz">r</a>
        <a href="kali-linux-2026.2-cloud-genericcloud-arm64.raw.xz">bad</a>'
  run kali_image_url "$html"
  [ "$status" -eq 0 ]
  [ "$output" = "https://kali.download/cloud-images/current/kali-linux-2026.2-cloud-genericcloud-amd64.raw.xz" ]
}

@test "kali_image_url falls back to qcow2 when no raw.xz" {
  load_lib
  html='<a href="kali-linux-2026.2-cloud-genericcloud-amd64.qcow2">q</a>'
  run kali_image_url "$html"
  [ "$status" -eq 0 ]
  [[ "$output" == *"amd64.qcow2" ]]
}

@test "kali_verify_checksum passes on a matching sha256" {
  load_lib
  tmp="$BATS_TEST_TMPDIR/img"; printf 'hello' > "$tmp"
  sum="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  sums="$sum  img"
  run kali_verify_checksum "$tmp" "$sums"
  [ "$status" -eq 0 ]
}

@test "kali_verify_checksum fails on a mismatch" {
  load_lib
  tmp="$BATS_TEST_TMPDIR/img"; printf 'hello' > "$tmp"
  sums="deadbeef  img"
  run kali_verify_checksum "$tmp" "$sums"
  [ "$status" -ne 0 ]
}
