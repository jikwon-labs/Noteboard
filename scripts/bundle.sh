#!/bin/bash
# release 빌드 후 build/Noteboard.app 번들을 만든다(Sparkle.framework 포함).
# Developer ID 인증서가 키체인에 있으면 그걸로 서명하고, NOTARIZE=1 이면 공증까지 해서 build/Noteboard.zip 을 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."

# 버전은 Sources/NoteboardCore/Version.swift 한 곳에만 둔다. 빌드 번호는 커밋 수(늘기만 한다, Sparkle 비교에 쓴다).
VERSION="$(sed -nE 's/.*version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' Sources/NoteboardCore/Version.swift)"
if [ -z "$VERSION" ]; then echo "Version.swift 에서 버전을 읽지 못했다" >&2; exit 1; fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# 업데이트 정보(appcast)를 받는 주소: 레포 main 의 appcast.xml(scripts/release.sh 가 갱신).
# 레포가 비공개라 앱은 gh 토큰을 붙여 요청한다(UpdaterController).
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/jikwon-labs/Noteboard/main/appcast.xml}"
# Sparkle 서명 공개 키(scripts/sparkle-keys.sh 가 만든다). 없으면 업데이트 기능이 꺼진 채로 빌드된다.
PUBLIC_KEY="$(tr -d '[:space:]' < Resources/SparklePublicKey.txt 2>/dev/null || true)"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/Noteboard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Noteboard" "$APP/Contents/MacOS/Noteboard"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# 번들 안의 Frameworks 에서 Sparkle 을 찾게 한다.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Noteboard" 2>/dev/null || true
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -n "$PUBLIC_KEY" ]; then
  KEY_ENTRY="<key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>"
else
  KEY_ENTRY=""
  echo "주의: Resources/SparklePublicKey.txt 가 없어 업데이트 기능 없이 빌드한다 (scripts/sparkle-keys.sh)" >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>noteboard</string>
  <key>CFBundleDisplayName</key><string>noteboard</string>
  <key>CFBundleIdentifier</key><string>local.noteboard.app</string>
  <key>CFBundleExecutable</key><string>Noteboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>jikwon-labs</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  $KEY_ENTRY
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# 서명: Developer ID 인증서가 있으면 그걸로(Sparkle 안쪽 부품부터), 없으면 임시(ad-hoc) 서명.
ID="${SIGN_IDENTITY:-Developer ID Application: jikwon seo (K6599UJ4KM)}"
F="$APP/Contents/Frameworks/Sparkle.framework"
if security find-identity -v -p codesigning | grep -qF "$ID"; then
  sign() { codesign --force --options runtime --timestamp --sign "$ID" "$@"; }
  sign "$F/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$F/Versions/B/XPCServices/Downloader.xpc"
  sign "$F/Versions/B/Autoupdate"
  sign "$F/Versions/B/Updater.app"
  sign "$F"
  sign "$APP"
  codesign --verify --strict --deep "$APP"
  SIGNED_WITH_ID=1
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  SIGNED_WITH_ID=0
fi
echo "built $APP ($VERSION, build $BUILD)"

# 공증: NOTARIZE=1 일 때만 (몇 분 걸림). 계정 정보는 미리
# `xcrun notarytool store-credentials <이름> ...` 로 저장해 둔다(symboard 와 같은 계정을 쓴다).
if [ "${NOTARIZE:-0}" = 1 ]; then
  if [ "$SIGNED_WITH_ID" != 1 ]; then echo "Developer ID 서명이 없어 공증할 수 없다" >&2; exit 1; fi
  ZIP=build/Noteboard.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-symboard-notary}" --wait
  xcrun stapler staple "$APP"
  # 배포용 zip 은 공증 결과를 붙인 뒤 다시 만든다.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -vv "$APP"
  echo "notarized $ZIP"
fi
