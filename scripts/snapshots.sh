#!/bin/bash
# 창을 화면 밖에 그려 build/snapshots/*.png 로 저장한다(디자인 시안과 비교할 때).
# 시험 노트는 build/snapshot-notes 에 만들고, 실제 저장 폴더는 건드리지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
rm -rf build/snapshots build/snapshot-notes
NOTEBOARD_SNAPSHOT_DIR="$PWD/build/snapshots" "$BIN/Noteboard" -storageFolder "$PWD/build/snapshot-notes"
ls build/snapshots
