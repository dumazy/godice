#!/usr/bin/env bash
# Verifies the public packages against the *minimum* SDK they declare.
#
# The workspace itself needs a recent SDK (Melos, lockfile), so the packages
# are copied out of it, `resolution: workspace` is dropped, and they are
# resolved standalone with whatever `dart`/`flutter` is on PATH. Run it with
# the floor version installed, e.g.:
#
#   fvm spawn 3.32.0 bash tool/check_min_sdk.sh      # locally with FVM
#
# CI does the same in the "Minimum SDK" job.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Using $(dart --version 2>&1)"
echo "Using Flutter $(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"

prepare() {
  local pkg="$1"
  cp -R "$ROOT/packages/$pkg" "$TMP/$pkg"
  rm -rf "$TMP/$pkg/.dart_tool" "$TMP/$pkg/pubspec.lock"
  grep -v '^resolution: workspace$' "$TMP/$pkg/pubspec.yaml" > "$TMP/$pkg/pubspec.tmp"
  mv "$TMP/$pkg/pubspec.tmp" "$TMP/$pkg/pubspec.yaml"
}

prepare godice
prepare godice_universal_ble
# The Flutter example is its own workspace package; not part of this check.
rm -rf "$TMP/godice_universal_ble/example"
printf '\ndependency_overrides:\n  godice:\n    path: ../godice\n' >> "$TMP/godice_universal_ble/pubspec.yaml"

echo; echo "== godice"
( cd "$TMP/godice" && dart pub get && dart analyze --fatal-infos && dart test )

echo; echo "== godice_universal_ble"
( cd "$TMP/godice_universal_ble" && flutter pub get && flutter analyze --fatal-infos && flutter test )

echo; echo "Minimum SDK check passed."
