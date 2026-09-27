#!/bin/zsh
# Bump the build number, archive (iPhone app + watch app), and upload to App Store Connect.
# Signs and uploads with the App Store Connect API key, so no Xcode sign-in is needed.
# The key file stays on this Mac: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
#   scripts/testflight.sh          # next build number
#   scripts/testflight.sh 12       # a specific build number
#   SHUKR_APPSTORE=1 scripts/testflight.sh   # the App Store build: leaves out the "What's new"
#                                            # screenshots (shukr/WhatsNewShots/wn-*.jpg)
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=6K2RUXRJ92
ISSUER_ID=60a885ac-0315-4323-974d-57783a7392a2
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8"
[[ -f $KEY_PATH ]] || { echo "Missing API key at $KEY_PATH"; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

PBX=shukr.xcodeproj/project.pbxproj
CURRENT=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' $PBX | grep -o '[0-9]*$')
NEXT=${1:-$((CURRENT + 1))}
VERSION=$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' $PBX | grep -o '[0-9.]*$')
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEXT;/g" $PBX
echo "→ $VERSION ($NEXT)"

ARCHIVE=build/shukr-$VERSION-$NEXT.xcarchive
rm -rf "$ARCHIVE" "build/export-$NEXT"
# Which commit this is, shown under the hamburger menu / Settings (BuildInfo.swift). "+" = the
# build bump (and anything else) wasn't committed yet.
STAMP="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . ':!*.xcuserstate' ':!*xcschememanagement.plist' || echo +)"
# TestFlight and the App Store get the same binary, so the screenshots are left out only on request.
EXTRA=()
[[ "${SHUKR_APPSTORE:-}" == 1 ]] && EXTRA=(EXCLUDED_SOURCE_FILE_NAMES='wn-*.jpg') && echo "→ App Store build: no What's new screenshots"
xcodebuild -project shukr.xcodeproj -scheme shukr -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" "${AUTH[@]}" SHUKR_BUILD_STAMP="$STAMP" "${EXTRA[@]}" archive | tail -3

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>7R387XZ2Y7</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

# Homebrew's rsync breaks the export ("Copy failed"): use the system one.
env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist -exportPath "build/export-$NEXT" "${AUTH[@]}" \
  | grep -E "Upload succeeded|EXPORT|error" || true
echo "✓ $VERSION ($NEXT) uploaded — commit the build number bump."
