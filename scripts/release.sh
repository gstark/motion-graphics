#!/bin/zsh
# Builds, signs, and packages MotionGraphics as a DMG with the standard
# "drag to Applications" layout.
#
#   scripts/release.sh
#
# Signing identity: prefers "Developer ID Application" (correct for apps
# distributed outside the App Store), falls back to "Apple Development"
# (fine for your own Macs). The hardened runtime is enabled, so the app
# is ready for notarization if that is ever wanted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="MotionGraphics"
VOLUME_NAME="Motion Graphics"
ENTITLEMENTS="$ROOT/app/MotionGraphics.entitlements"

# --- pick a signing identity ---------------------------------------------
# Sign by certificate hash, not name: duplicate certificates with the
# same name make codesign refuse a name as "ambiguous".
IDENTITIES=$(security find-identity -v -p codesigning)
LINE=$(echo "$IDENTITIES" | grep '"Developer ID Application:' | head -1 || true)
if [ -z "$LINE" ]; then
  LINE=$(echo "$IDENTITIES" | grep '"Apple Development:' | head -1 || true)
  echo "note: no Developer ID Application certificate found; signing with an Apple Development one."
  echo "      Create one in Xcode > Settings > Accounts > Manage Certificates for outside-App-Store distribution."
fi
[ -n "$LINE" ] || { echo "error: no signing identity found"; exit 1 }
IDENTITY=$(echo "$LINE" | awk '{print $2}')
echo "==> signing as: $(echo "$LINE" | sed 's/^ *[0-9]*) [A-F0-9]* //')"

# --- runtimes and build ---------------------------------------------------
if [ ! -f "$ROOT/app/Resources/bin/node" ]; then
  "$ROOT/scripts/bundle-runtimes.sh"
fi

echo "==> building Release"
cd "$ROOT"
tuist generate --no-open >/dev/null
xcodebuild -workspace MotionGraphics.xcworkspace -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO \
  build | grep -E "error:|BUILD"

APP="$ROOT/build/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: build product not found"; exit 1 }

# --- sign nested Mach-O binaries, then the app ---------------------------
# Everything in Resources (node, ffmpeg, yt-dlp, the Claude binary, the
# headless Chrome, native .node modules) must be signed before the outer
# bundle; codesign does not descend into Resources on its own.
echo "==> signing nested binaries"
python3 - "$APP/Contents/Resources" <<'PY' > /tmp/mg-machos.txt
import os, sys
MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for base, dirs, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(base, name)
        if os.path.islink(path):
            continue
        try:
            with open(path, 'rb') as f:
                if f.read(4) in MAGICS:
                    print(path)
        except OSError:
            pass
PY
while IFS= read -r binary; do
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$binary" 2>/dev/null \
    || echo "warn: could not sign $binary"
done < /tmp/mg-machos.txt
echo "    signed $(wc -l < /tmp/mg-machos.txt | tr -d ' ') binaries"

echo "==> signing the app bundle"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "    verified"

# --- notarize the app -----------------------------------------------------
# Without notarization, other Macs show "cannot verify ... malware" and the
# user must approve it in System Settings. Notarizing + stapling removes
# that prompt. This needs a one-time saved credential (see NOTARY_PROFILE).
# Skips cleanly when no credential is set, leaving the app signed but not
# notarized (fine for your own Mac).
NOTARY_PROFILE="${NOTARY_PROFILE:-MG_NOTARY}"
NOTARIZE=0
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  NOTARIZE=1
else
  echo "note: no notary credential '$NOTARY_PROFILE' found; skipping notarization."
  echo "      The app is signed but other Macs will warn on first open."
  echo "      One-time setup (see scripts/notarize-setup.md):"
  echo "        xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "          --apple-id <your Apple ID> --team-id JBRC9C74U7 --password <app-specific-password>"
fi

app_notarized=0
if [ "$NOTARIZE" = "1" ]; then
  echo "==> notarizing the app (this can take a few minutes)"
  ZIP=$(mktemp -d)/app.zip
  ditto -c -k --keepParent "$APP" "$ZIP"
  # Best-effort: a locked login keychain can make notarytool fail to read the
  # credential mid-build. Retry once, and never abort the build over it — the
  # app stays signed either way. Run release.sh from an interactive shell (or
  # switch to an App Store Connect API key) for reliable headless notarizing.
  for attempt in 1 2; do
    if xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
       && xcrun stapler staple "$APP"; then
      app_notarized=1
      break
    fi
    echo "warn: app notarization attempt $attempt failed; retrying..."
    sleep 5
  done
  /bin/rm -f "$ZIP"
  [ "$app_notarized" = "1" ] || echo "warn: app not notarized (keychain locked?). Artifacts are signed but will warn on other Macs."
fi

# --- ZIP (the easy handoff) ----------------------------------------------
# A zip of the notarized, stapled app is the lowest-friction distributable:
# double-click expands it, drag the app to Applications, nothing to eject.
# The stapled ticket travels inside the app, so no separate notarization.
echo "==> building ZIP"
ZIP_OUT="$DIST/$APP_NAME.zip"
mkdir -p "$DIST"
/bin/rm -f "$ZIP_OUT"
ditto -c -k --keepParent "$APP" "$ZIP_OUT"

# --- DMG ------------------------------------------------------------------
echo "==> building DMG"
mkdir -p "$DIST"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME.dmg"
/bin/rm -f "$DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
/bin/rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" "$DMG"

# Notarize and staple the DMG too, so the disk image itself opens without a
# warning even before the app is copied out. Best-effort, like the app step.
if [ "$NOTARIZE" = "1" ] && [ "$app_notarized" = "1" ]; then
  echo "==> notarizing the DMG"
  dmg_notarized=0
  for attempt in 1 2; do
    if xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
       && xcrun stapler staple "$DMG"; then
      dmg_notarized=1
      break
    fi
    echo "warn: DMG notarization attempt $attempt failed; retrying..."
    sleep 5
  done
  if [ "$dmg_notarized" = "1" ]; then
    echo "==> verifying Gatekeeper acceptance"
    spctl -a -t open --context context:primary-signature -vv "$DMG" || true
  else
    echo "warn: could not notarize the DMG. The ZIP is fully notarized and is"
    echo "      the recommended handoff. If the DMG matters, re-run the script;"
    echo "      the keychain may have locked during the app-notarization wait."
  fi
fi

echo "==> done"
ls -lh "$ZIP_OUT" "$DMG"
