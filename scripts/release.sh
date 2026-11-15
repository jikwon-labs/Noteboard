#!/bin/bash
# 새 버전을 배포한다: 버전 올리기 → 시험 → 서명·공증 빌드 → appcast 서명 → 커밋·태그·push → 공개 릴리스 레포에 올리기.
# 사용: scripts/release.sh <새 버전>          예) scripts/release.sh 1.0.0
#       DRY_RUN=1 scripts/release.sh 1.0.0    빌드·공증·appcast 까지만 하고 커밋·push·릴리스는 하지 않는다(버전 파일은 되돌린다).
#       DRY_RUN=1 SKIP_NOTARIZE=1 ...         공증도 건너뛴다(빠른 확인용).
# 필요한 것: main 에서 깨끗한 작업 트리, Developer ID 인증서, 공증 계정(NOTARY_PROFILE, 기본 symboard-notary),
#           Sparkle 키(scripts/sparkle-keys.sh), 로그인된 gh, 공개 릴리스 레포(RELEASE_REPO).
#
# 코드 레포(jikwon-labs/Noteboard)는 비공개라 앱이 로그인 없이 업데이트를 받을 수 없다.
# 그래서 zip 과 appcast.xml 은 공개 릴리스 레포에 올리고, 앱은
# https://github.com/<RELEASE_REPO>/releases/latest/download/appcast.xml 을 본다(bundle.sh 의 SUFeedURL).
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
NEW="${NEW#v}"
VERSION_FILE=Sources/NoteboardCore/Version.swift
CUR="$(sed -nE 's/.*version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$VERSION_FILE")"
RELEASE_REPO="${RELEASE_REPO:-jikwon-labs/Noteboard-releases}"
DRY="${DRY_RUN:-0}"

die() { echo "release: $*" >&2; exit 1; }

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전을 x.y.z 로 주세요 (지금 $CUR)"
[ "$NEW" != "$CUR" ] && [ "$(printf '%s\n%s\n' "$CUR" "$NEW" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$NEW" ] \
  || die "$NEW 는 지금 버전 $CUR 보다 높아야 한다"
[ -s Resources/SparklePublicKey.txt ] || die "Sparkle 공개 키가 없다. scripts/sparkle-keys.sh 를 먼저 돌린다"

if [ "$DRY" != 1 ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "main 브랜치에서 실행한다"
  git diff --quiet && git diff --cached --quiet || die "커밋하지 않은 변경이 있다"
  git fetch --quiet origin main --tags
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "origin/main 과 다르다(pull 또는 push 먼저)"
  git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null && die "태그 v$NEW 가 이미 있다"
  command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || die "gh 로그인이 필요하다 (gh auth login)"
  gh repo view "$RELEASE_REPO" >/dev/null 2>&1 || die "공개 릴리스 레포 $RELEASE_REPO 가 없다 (gh repo create $RELEASE_REPO --public)"
fi

PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
SPARKLE_BIN="$(scripts/sparkle-tools.sh)"

echo "== $CUR → $NEW"
sed -i '' -E "s/(version = \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$NEW\2/" "$VERSION_FILE"
restore() { git checkout -- "$VERSION_FILE"; }
trap 'echo "release: 실패해서 버전 파일을 되돌린다" >&2; restore' ERR

echo "== 시험"
swift test

if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then
  [ "$DRY" = 1 ] || die "SKIP_NOTARIZE 는 DRY_RUN 에서만 쓸 수 있다"
  echo "== 서명 빌드 (공증 건너뜀)"
  scripts/bundle.sh
  rm -f build/Noteboard.zip
  ditto -c -k --keepParent build/Noteboard.app build/Noteboard.zip
else
  echo "== 서명·공증 빌드 (몇 분 걸림)"
  NOTARIZE=1 scripts/bundle.sh
fi
[ -f build/Noteboard.zip ] || die "build/Noteboard.zip 이 없다"

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/Noteboard.app/Contents/Info.plist)"

# 릴리스 노트: 지난 태그 뒤 커밋 제목.
NOTES="$(mktemp)"
CHANGES="$(if [ -n "$PREV_TAG" ]; then git log --no-merges --pretty='%s' "$PREV_TAG..HEAD"; else git log --no-merges --pretty='%s'; fi)"
{
  echo "## 바뀐 것"
  echo "$CHANGES" | sed 's/^/- /'
  echo
  echo "## 설치"
  echo "1. \`Noteboard.zip\` 을 받아 압축을 푼다."
  echo "2. \`Noteboard.app\` 을 응용 프로그램 폴더로 옮겨 연다. 이미 쓰고 있다면 앱 안의 업데이트로 바로 받을 수 있다."
  echo
  echo "Developer ID 로 서명하고 Apple 공증을 받았다. macOS 15 이상, Apple Silicon."
} > "$NOTES"

echo "== appcast"
SIGNATURE="$("$SPARKLE_BIN/sign_update" build/Noteboard.zip)"
CHANGES_HTML="$(echo "$CHANGES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's#^\(.*\)$#<li>\1</li>#')"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>noteboard</title>
    <item>
      <title>noteboard $NEW</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$CHANGES_HTML</ul>]]></description>
      <enclosure url="https://github.com/$RELEASE_REPO/releases/download/v$NEW/Noteboard.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout build/appcast.xml
cat build/appcast.xml

if [ "$DRY" = 1 ]; then
  trap - ERR
  restore
  rm -f "$NOTES"
  echo "== DRY_RUN: build/Noteboard.zip, build/appcast.xml 까지 만들었다. 커밋·push·릴리스는 하지 않았다."
  exit 0
fi

echo "== 릴리스 노트"
cat "$NOTES"
echo
read -r -p "v$NEW 를 커밋·태그·push 하고 $RELEASE_REPO 에 릴리스를 만들까요? [y/N] " ok
if [ "$ok" != y ] && [ "$ok" != Y ]; then
  trap - ERR
  restore
  rm -f "$NOTES"
  die "취소했다(버전 파일을 되돌렸다)"
fi

trap - ERR
git add "$VERSION_FILE"
git commit -m "chore: v$NEW 배포"
git tag -a "v$NEW" -m "noteboard $NEW"
git push origin main "v$NEW"
gh release create "v$NEW" build/Noteboard.zip build/appcast.xml --repo "$RELEASE_REPO" \
  --title "noteboard $NEW" --notes-file "$NOTES"
rm -f "$NOTES"
echo "== 끝: $(gh release view "v$NEW" --repo "$RELEASE_REPO" --json url -q .url)"
