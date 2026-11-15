#!/bin/bash
# Sparkle 업데이트 서명 키를 준비한다. 한 번만 하면 된다.
# - 비밀 키: 로그인 키체인에 저장된다(이미 있으면 그대로 쓴다). 잃어버리면 기존 사용자에게 업데이트를 보낼 수 없다.
# - 공개 키: Resources/SparklePublicKey.txt 에 적는다(커밋한다). bundle.sh 가 Info.plist 에 넣는다.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="$(scripts/sparkle-tools.sh)"
"$BIN/generate_keys" >/dev/null
KEY="$("$BIN/generate_keys" -p)"
[ -n "$KEY" ] || { echo "공개 키를 읽지 못했다" >&2; exit 1; }
echo "$KEY" > Resources/SparklePublicKey.txt
echo "공개 키를 Resources/SparklePublicKey.txt 에 적었다: $KEY"
echo "비밀 키 백업(안전한 곳에 보관): \"$BIN/generate_keys\" -x <파일 경로>"
