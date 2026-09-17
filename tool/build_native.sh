#!/usr/bin/env bash
# Fetches and builds the `bluetooth_core` Rust crate that `bluetooth_dart`
# loads over FFI. The crate is pinned to the commit that matches the published
# bluetooth_dart 0.0.1 package so the C ABI stays in sync.
#
# Requires a Rust toolchain (https://rustup.rs or `brew install rust`).
#
# The result lands in native/bluetooth_core/target/release/, which
# bluetooth_dart finds automatically when the CLI runs from anywhere inside
# this repository. Elsewhere, point BLUETOOTH_CORE_LIB at the built library.
set -euo pipefail

COMMIT="70c0ef23cf49502331893492ef42937397153422"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/native/bluetooth_core"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found. Install Rust first: https://rustup.rs" >&2
  exit 1
fi

if [ ! -f "$DEST/Cargo.toml" ]; then
  echo "Fetching bluetooth_core @ ${COMMIT:0:12}..."
  TMP="$(mktemp -d)"
  curl -sSL "https://github.com/ManyMath/bluetooth/archive/$COMMIT.tar.gz" | tar -xz -C "$TMP"
  mkdir -p "$DEST"
  cp -R "$TMP/bluetooth-$COMMIT/native/bluetooth_core/." "$DEST/"
  rm -rf "$TMP"
fi

echo "Building bluetooth_core (release)..."
cargo build --release --manifest-path "$DEST/Cargo.toml"

case "$(uname -s)" in
  Darwin) LIB="libbluetooth_core.dylib" ;;
  Linux)  LIB="libbluetooth_core.so" ;;
  *)      LIB="bluetooth_core.dll" ;;
esac
echo "Built: $DEST/target/release/$LIB"
