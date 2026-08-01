#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/.cargo/env"

LIB=libPatchwork_server.a
STAGING=target/xcframework-staging
KIT=../PatchworkServerKit

cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target aarch64-apple-darwin

# Bindgen reads metadata out of a host dylib
cargo build --release --features cli
cargo run --release --features cli --bin uniffi-bindgen -- generate \
  --library target/release/libPatchwork_server.dylib \
  --language swift --out-dir target/bindings

rm -rf "$STAGING"
mkdir -p "$STAGING/headers"
cp target/bindings/Patchwork_serverFFI.h "$STAGING/headers/"
cp target/bindings/Patchwork_serverFFI.modulemap "$STAGING/headers/module.modulemap"

rm -rf "$KIT/Artifacts/PatchworkServerFFI.xcframework"
mkdir -p "$KIT/Artifacts"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/$LIB -headers "$STAGING/headers" \
  -library target/aarch64-apple-ios-sim/release/$LIB -headers "$STAGING/headers" \
  -library target/aarch64-apple-darwin/release/$LIB -headers "$STAGING/headers" \
  -output "$KIT/Artifacts/PatchworkServerFFI.xcframework"

mkdir -p "$KIT/Sources/PatchworkServerKit/Generated"
cp target/bindings/Patchwork_server.swift "$KIT/Sources/PatchworkServerKit/Generated/"
echo "done: $KIT/Artifacts/PatchworkServerFFI.xcframework"
