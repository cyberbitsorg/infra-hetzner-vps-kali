#!/usr/bin/env bats
load_lib() { source "${BATS_TEST_DIRNAME}/../scripts/lib/kali-image.sh"; }

@test "kali_image_url returns the amd64 tar.xz, not the .torrent sibling or arm64" {
  load_lib
  html='<a href="kali-linux-2026.2-cloud-genericcloud-arm64.tar.xz">arm64</a>
        <a href="kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz.torrent">torrent</a>
        <a href="kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz">amd64</a>'
  run kali_image_url "$html"
  [ "$status" -eq 0 ]
  [ "$output" = "https://kali.download/cloud-images/current/kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz" ]
  [[ "$output" != *.torrent ]]
}

@test "kali_image_url fails when no amd64 tar.xz is present" {
  load_lib
  html='<a href="kali-linux-2026.2-cloud-genericcloud-arm64.tar.xz">arm64</a>
        <a href="kali-linux-2026.2-cloud-genericcloud-arm64.tar.xz.torrent">torrent</a>'
  run kali_image_url "$html"
  [ "$status" -ne 0 ]
}

@test "kali_want_sha returns the sha256 for a present basename" {
  load_lib
  sums='deadbeef  kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz
cafef00d  kali-linux-2026.2-cloud-genericcloud-arm64.tar.xz'
  run kali_want_sha "kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz" "$sums"
  [ "$status" -eq 0 ]
  [ "$output" = "deadbeef" ]
}

@test "kali_want_sha fails for an absent basename" {
  load_lib
  sums='cafef00d  kali-linux-2026.2-cloud-genericcloud-arm64.tar.xz'
  run kali_want_sha "kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz" "$sums"
  [ "$status" -ne 0 ]
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
