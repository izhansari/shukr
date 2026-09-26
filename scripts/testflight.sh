#!/bin/zsh
# Bump the build number, archive (iPhone app + watch app), and upload to App Store Connect.
# Signs and uploads with the App Store Connect API key, so no Xcode sign-in is needed.
# The key file stays on this Mac: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
#   scripts/testflight.sh          # next build number
#   scripts/testflight.sh 12       # a specific build number
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
xcodebuild -project shukr.xcodeproj -scheme shukr -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" "${AUTH[@]}" archive | tail -3

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
