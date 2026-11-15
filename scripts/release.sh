#!/bin/bash
# 새 버전을 배포한다: 버전 올리기 → 시험 → 서명·공증 빌드 → zip 서명 → 커밋·태그·push → GitHub 릴리스 → appcast.xml 갱신.
# 사용: scripts/release.sh <새 버전>          예) scripts/release.sh 1.0.0
#       DRY_RUN=1 scripts/release.sh 1.0.0    빌드·공증·서명까지만 하고 커밋·push·릴리스는 하지 않는다(버전 파일은 되돌린다).
#       DRY_RUN=1 SKIP_NOTARIZE=1 ...         공증도 건너뛴다(빠른 확인용).
#       YES=1 scripts/release.sh 1.0.0        마지막 확인 질문을 건너뛴다.
# 필요한 것: main 에서 깨끗한 작업 트리, Developer ID 인증서, 공증 계정(NOTARY_PROFILE, 기본 symboard-notary),
#           Sparkle 키(scripts/sparkle-keys.sh), 로그인된 gh.
#
# 레포가 비공개라 업데이트도 이 레포 안에서 돈다:
# - zip 은 이 레포의 GitHub 릴리스에 올린다.
# - appcast.xml 은 main 에 커밋한다. 앱은 raw.githubusercontent.com 의 이 파일을 gh 토큰을 붙여 읽고,
#   enclosure 주소(릴리스 첨부 파일의 API 주소)도 토큰을 붙여 받는다.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
NEW="${NEW#v}"
VERSION_FILE=Sources/NoteboardCore/Version.swift
CUR="$(sed -nE 's/.*version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$VERSION_FILE")"
REPO="${REPO:-jikwon-labs/Noteboard}"
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

echo "== zip 서명"
SIGNATURE="$("$SPARKLE_BIN/sign_update" build/Noteboard.zip)"
[[ "$SIGNATURE" == *edSignature* ]] || die "sign_update 결과가 이상하다: $SIGNATURE"

CHANGES="$(if [ -n "$PREV_TAG" ]; then git log --no-merges --pretty='%s' "$PREV_TAG..HEAD"; else git log --no-merges --pretty='%s'; fi)"
CHANGES="$(echo "$CHANGES" | grep -v '^chore: v[0-9.]* appcast$' || true)"
NOTES="$(mktemp)"
{
  echo "## 바뀐 것"
  echo "$CHANGES" | sed 's/^/- /'
  echo
  echo "## 설치"
  echo "1. \`Noteboard.zip\` 을 받아 압축을 푼다."
  echo "2. \`Noteboard.app\` 을 응용 프로그램 폴더로 옮겨 연다. 이미 쓰고 있다면 앱 안의 업데이트로 받으면 된다."
  echo
  echo "Developer ID 로 서명하고 Apple 공증을 받았다. macOS 15 이상, Apple Silicon."
} > "$NOTES"

write_appcast() { # $1 = enclosure 주소
  local changes_html
  changes_html="$(echo "$CHANGES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's#^\(.*\)$#<li>\1</li>#' | tr -d '\n')"
  cat > appcast.xml <<XML
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
      <description><![CDATA[<ul>$changes_html</ul>]]></description>
      <enclosure url="$1" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
  xmllint --noout appcast.xml
}

if [ "$DRY" = 1 ]; then
  write_appcast "https://api.github.com/repos/$REPO/releases/assets/0"
  mv appcast.xml build/appcast.xml
  cat build/appcast.xml
  trap - ERR
  restore
  rm -f "$NOTES"
  echo "== DRY_RUN: build/Noteboard.zip, build/appcast.xml 까지 만들었다. 커밋·push·릴리스는 하지 않았다."
  exit 0
fi

echo "== 릴리스 노트"
cat "$NOTES"
echo
if [ "${YES:-0}" != 1 ]; then
  read -r -p "v$NEW 를 커밋·태그·push 하고 릴리스를 만들까요? [y/N] " ok
  if [ "$ok" != y ] && [ "$ok" != Y ]; then
    trap - ERR
    restore
    rm -f "$NOTES"
    die "취소했다(버전 파일을 되돌렸다)"
  fi
fi

trap - ERR
git add "$VERSION_FILE"
git commit -m "chore: v$NEW 배포"
git tag -a "v$NEW" -m "noteboard $NEW"
git push origin main "v$NEW"
gh release create "v$NEW" build/Noteboard.zip --repo "$REPO" --title "noteboard $NEW" --notes-file "$NOTES"
rm -f "$NOTES"

# 릴리스 첨부 파일의 API 주소(토큰 + Accept: application/octet-stream 으로 받는다).
ASSET_URL="$(gh api "repos/$REPO/releases/tags/v$NEW" --jq '.assets[] | select(.name == "Noteboard.zip") | .url')"
[ -n "$ASSET_URL" ] || die "릴리스 첨부 파일 주소를 못 찾았다. appcast.xml 을 직접 갱신해야 한다"

echo "== appcast.xml 갱신"
write_appcast "$ASSET_URL"
git add appcast.xml
git commit -m "chore: v$NEW appcast"
git push origin main
echo "== 끝: $(gh release view "v$NEW" --repo "$REPO" --json url -q .url)"
