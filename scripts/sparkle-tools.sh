#!/bin/bash
# Sparkle 명령 도구(generate_keys, sign_update)를 .tools/sparkle 에 받아 두고 bin 폴더 경로를 출력한다.
# 버전은 Package.swift 의 Sparkle 과 맞춘다.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="$(sed -nE 's/.*Sparkle", exact: "([0-9.]+)".*/\1/p' Package.swift)"
[ -n "$SPARKLE_VERSION" ] || { echo "Package.swift 에서 Sparkle 버전을 못 읽었다" >&2; exit 1; }
DEST=".tools/sparkle-$SPARKLE_VERSION"

if [ ! -x "$DEST/bin/sign_update" ]; then
  mkdir -p "$DEST"
  ARCHIVE="$DEST/Sparkle-$SPARKLE_VERSION.tar.xz"
  curl -fsSL -o "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  tar -xf "$ARCHIVE" -C "$DEST"
  rm -f "$ARCHIVE"
fi
echo "$PWD/$DEST/bin"
