#!/bin/zsh
# Team-sign the simulator build and install it, so the simulator runs shukr's App Shortcuts (an unsigned simulator build
# can't: linkd "Unable to get teamId"). Uses the Mac's Apple Development identity; never touches the ASC key.
# usage: scripts/sim-sign.sh <simulator udid> [derived data dir, default build/sim]
setopt nullglob
U=${1:?simulator udid}
D=${2:-build/sim}
ID=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
T=$(mktemp -d)
cp -R "$D/Build/Products/Debug-iphonesimulator/shukr.app" "$T/"
B="$T/shukr.app"
X="$D/Build/Intermediates.noindex/shukr.build/Debug-iphonesimulator/shukr.build/shukr.app.xcent"
WX="$D/Build/Intermediates.noindex/shukr.build/Debug-iphonesimulator/shukrWidgetExtension.build/shukrWidgetExtension.appex.xcent"
for f in $B/*.dylib; do codesign -f -s $ID "$f" 2>/dev/null; done
for p in $B/PlugIns/*.appex; do codesign -f -s $ID --entitlements "$WX" "$p" 2>/dev/null; done
codesign -f -s $ID --entitlements "$X" "$B" 2>/dev/null
xcrun simctl install "$U" "$B" && echo "signed + installed"
rm -rf "$T"
