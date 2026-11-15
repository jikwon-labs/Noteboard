#!/bin/bash
# 실제 창으로 저장 흐름(저장·제목 변경·포맷 전환·외부 수정·빈 노트 삭제·휴지통)을 돌려 본다.
# 시험 노트는 빈 임시 폴더에서만 만든다(휴지통 시험 파일은 휴지통에 남는다).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
DIR="$(mktemp -d)/notes"
NOTEBOARD_SELFTEST=1 "$BIN/Noteboard" -storageFolder "$DIR"
