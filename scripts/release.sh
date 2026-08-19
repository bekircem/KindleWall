#!/usr/bin/env bash
#
# KindleWall release pipeline.
#
#   scripts/release.sh 1.0.0             build, sign, notarize, staple — all local
#   scripts/release.sh 1.0.0 --publish   ...then push the tag, the release and the cask
#
# Nothing leaves this machine without --publish. Signing credentials stay in the login
# keychain and are never copied anywhere.
#
# Prerequisites
#   brew install xcodegen create-dmg
#   gh auth login
#   ~/bin/sign_update            from the Sparkle release tarball
#   xcrun notarytool store-credentials KindleWall --apple-id <id> --team-id CB9V39VP62

set -euo pipefail

VERSION="${1:-}"
PUBLISH="${2:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version> [--publish]" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be MAJOR.MINOR.PATCH" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="KindleWall"
SCHEME="KindleWall"
TEAM="CB9V39VP62"
IDENTITY="Developer ID Application: Bekir Cem ÜNALAN ($TEAM)"
NOTARY_PROFILE="KindleWall"
REPO="bekircem/KindleWall"
TAP_DIR="${KINDLEWALL_TAP_DIR:-$ROOT/../homebrew-tap}"
DEST="platform=macOS,arch=arm64"

BUILD="$ROOT/build"
ARCHIVE="$BUILD/$APP.xcarchive"
EXPORT="$BUILD/export"
DMG="$BUILD/$APP-$VERSION.dmg"
PLIST="$ROOT/KindleWall/Resources/Info.plist"
APPCAST="$ROOT/docs/appcast.xml"
SIGN_UPDATE="$HOME/bin/sign_update"

step() { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. preflight ─────────────────────────────────────────────────────────────
step "1/14  preflight"
[ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit or stash first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "not on main"
for tool in xcodegen create-dmg gh xmllint; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done
[ -x "$SIGN_UPDATE" ] || die "sign_update missing at $SIGN_UPDATE (copy it from the Sparkle release tarball)"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' is not set up — see the header of this script"

xcodegen generate >/dev/null
[ -z "$(git status --porcelain KindleWall.xcodeproj)" ] \
  || die "xcodegen changed the project — commit the regenerated project first"
ok "clean tree, on main, tooling present"

# Two-step on purpose. The single-step `xcodebuild test` does not stage the xctest bundle;
# it fails with "Failed to create a bundle instance representing …", which reads like a test
# failure but means the tests never ran at all.
step "2/14  tests"
xcodebuild -project "$APP.xcodeproj" -scheme "$SCHEME" clean >/dev/null
xcodebuild build-for-testing -project "$APP.xcodeproj" -scheme "$SCHEME" -destination "$DEST" >/dev/null
TEST_LINE=$(xcodebuild test-without-building -project "$APP.xcodeproj" -scheme "$SCHEME" \
  -destination "$DEST" 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1 || true)
[ -n "$TEST_LINE" ] || die "no 'Executed N tests' line — the tests never ran"
echo "  $TEST_LINE"
echo "$TEST_LINE" | grep -q "with 0 failures" || die "tests failed"
ok "tests green"

# ── 3. version ───────────────────────────────────────────────────────────────
step "3/14  stamping version $VERSION"
BUILD_NO=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
BUILD_NO=$((BUILD_NO + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$PLIST"
ok "short=$VERSION  build=$BUILD_NO"

# ── 4. archive ───────────────────────────────────────────────────────────────
step "4/14  archive (Release)"
rm -rf "$BUILD"; mkdir -p "$BUILD"
xcodebuild archive -project "$APP.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -archivePath "$ARCHIVE" -allowProvisioningUpdates >/dev/null
ok "archived"

# ── 5. export ────────────────────────────────────────────────────────────────
# The archive is signed for development; `method: developer-id` is what re-signs it with the
# Developer ID certificate and fetches the matching profile.
step "5/14  export (developer-id)"
cat > "$BUILD/ExportOptions.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST_EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates >/dev/null
APP_PATH="$EXPORT/$APP.app"
[ -d "$APP_PATH" ] || die "export produced no app"
ok "exported"

# ── 6. verify the signature, Sparkle's nested binaries included ──────────────
# Xcode does not always harden what lives inside an embedded framework, and when it misses
# one the only evidence is a line in a notarization log nobody reads. Checked here instead.
step "6/14  verifying signatures"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -2
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -q "flags=0x10000(runtime)" \
  || die "the app is not hardened"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -q "Authority=Developer ID Application" \
  || die "the app is not signed with a Developer ID certificate"
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "get-task-allow"; then
  die "get-task-allow is present — notarization will reject this"
fi
ok "app: Developer ID, hardened, no get-task-allow"

FW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$FW/Autoupdate" "$FW/Updater.app" "$FW/XPCServices"/*.xpc; do
  [ -e "$nested" ] || continue
  NAME=$(basename "$nested")
  INFO=$(codesign -dv --verbose=4 "$nested" 2>&1)
  echo "$INFO" | grep -q "runtime" || die "$NAME is not hardened — notarization will reject it"
  echo "$INFO" | grep -q "Authority=Developer ID Application" \
    || die "$NAME is still ad-hoc signed — re-sign it with the Developer ID certificate"
  ok "$NAME: Developer ID, hardened"
done

# ── 7. dmg ───────────────────────────────────────────────────────────────────
step "7/14  building dmg"
create-dmg --volname "$APP $VERSION" --window-size 540 380 \
  --icon-size 110 --icon "$APP.app" 140 180 --app-drop-link 400 180 \
  --hide-extension "$APP.app" --no-internet-enable \
  "$DMG" "$EXPORT" >/dev/null 2>&1 || die "create-dmg failed"
codesign --sign "$IDENTITY" --timestamp "$DMG"
ok "$(basename "$DMG") — $(du -h "$DMG" | cut -f1)"

# ── 8. notarize ──────────────────────────────────────────────────────────────
step "8/14  notarizing (waiting on Apple)"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
  SUB=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["history"][0]["id"])' 2>/dev/null || true)
  if [ -n "$SUB" ]; then
    echo "── notarization log ──────────────────────────────"
    xcrun notarytool log "$SUB" --keychain-profile "$NOTARY_PROFILE" || true
  fi
  die "notarization failed (log above)"
fi
ok "notarized"

# ── 9-10. staple + gatekeeper ────────────────────────────────────────────────
step "9/14  stapling"
xcrun stapler staple "$DMG" >/dev/null
xcrun stapler validate "$DMG"
ok "stapled"

step "10/14  gatekeeper"
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | tail -3
ok "accepted"

# ── 11. sparkle signature ────────────────────────────────────────────────────
step "11/14  sparkle signature"
SIG_LINE=$("$SIGN_UPDATE" "$DMG")
ED_SIG=$(echo "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$ED_SIG" ] || die "sign_update produced no signature"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
ok "signed · sha256 $SHA"

# ── 12. appcast ──────────────────────────────────────────────────────────────
step "12/14  appcast"
PUBDATE=$(LC_ALL=C date -R)
export KW_ITEM="    <item>
      <title>$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_NO</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <enclosure url=\"https://github.com/$REPO/releases/download/v$VERSION/$APP-$VERSION.dmg\"
                 sparkle:edSignature=\"$ED_SIG\"
                 length=\"$LENGTH\"
                 type=\"application/octet-stream\" />
    </item>"
KW_APPCAST="$APPCAST" python3 - <<'PY'
import os
path = os.environ["KW_APPCAST"]
item = os.environ["KW_ITEM"]
xml = open(path, encoding="utf-8").read()
marker = "</language>"
assert marker in xml, "appcast is missing its <language> line"
# Newest first, immediately after the channel preamble.
open(path, "w", encoding="utf-8").write(xml.replace(marker, marker + "\n" + item, 1))
PY
xmllint --noout "$APPCAST" || die "the appcast is no longer well-formed"
ok "appcast updated"

echo
echo "Local artifacts ready:"
echo "  $DMG"
echo "  sha256 $SHA"
if [ "$PUBLISH" != "--publish" ]; then
  echo
  echo "Stopping here — nothing has left this machine."
  echo "Re-run with --publish to tag, release and update the cask."
  exit 0
fi

# ── 13-14. publish ───────────────────────────────────────────────────────────
step "13/14  commit, tag, push"
git add "$PLIST" "$APPCAST"
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push origin main
git push origin "v$VERSION"
ok "pushed v$VERSION"

step "14/14  github release"
gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "v$VERSION" --generate-notes
ok "release created"

step "14/14  homebrew tap"
[ -d "$TAP_DIR" ] || die "tap not found at $TAP_DIR (set KINDLEWALL_TAP_DIR)"
CASK="$TAP_DIR/Casks/kindlewall.rb"
[ -f "$CASK" ] || die "cask not found at $CASK"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP_DIR" add Casks/kindlewall.rb
git -C "$TAP_DIR" commit -m "kindlewall $VERSION"
git -C "$TAP_DIR" push
ok "cask updated"

echo
printf '\033[1;32m✓ v%s published.\033[0m\n' "$VERSION"
