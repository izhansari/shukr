#!/bin/zsh
# Install the newest pushed shukr (the team line) on Izhan's phone, his wife's, or both — a Debug build, no TestFlight.
# CONFIG=Release zsh scripts/install.sh me: the same, built Release (to feel the real speed; DEBUG-only extras are off).
#
#   zsh scripts/install.sh            both phones
#   zsh scripts/install.sh me         13 Pro Max only
#   zsh scripts/install.sh her        15 Pro only
#
# It builds from its own clean copy of origin/claude/tasbeeh-zikr-updates (shukrGit/install-build), never from an
# engineer's working folder, so half-done work is never installed and nobody's files are touched.
set -u

ME=00008110-001C041C2203801E      # Izhan's 13 Pro Max
HER=00008130-00027DDE0AE8001C     # his wife's 15 Pro
BRANCH=claude/tasbeeh-zikr-updates
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8"   # passed by path only, never read here

case "${1:-both}" in
  me)   PHONES=($ME) ;;
  her)  PHONES=($HER) ;;
  both) PHONES=($ME $HER) ;;
  *)    echo "usage: install.sh [me|her|both]"; exit 2 ;;
esac

REPO="${0:A:h:h}"                       # shukrGit/shukr
COPY="${REPO:h}/install-build"          # shukrGit/install-build

echo "→ Fetching the newest team line…"
git -C "$REPO" fetch -q origin "$BRANCH" || { echo "✗ couldn't reach GitHub"; exit 1; }
if [[ -d "$COPY/.git" || -f "$COPY/.git" ]]; then
  git -C "$COPY" checkout -q --detach "origin/$BRANCH" || { echo "✗ couldn't update $COPY"; exit 1; }
else
  git -C "$REPO" worktree add -q --detach "$COPY" "origin/$BRANCH" || { echo "✗ couldn't make $COPY"; exit 1; }
fi
HASH=$(git -C "$COPY" rev-parse --short HEAD)
echo "→ Building $HASH: $(git -C "$COPY" log -1 --format=%s | cut -c1-90)"

cd "$COPY" || exit 1
mkdir -p build
CONFIG="${CONFIG:-Debug}"
DERIVED=build/device; [[ $CONFIG == Release ]] && DERIVED=build/device-release
xcodebuild -project shukr.xcodeproj -scheme shukr -configuration "$CONFIG" -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID 6K2RUXRJ92 \
  -authenticationKeyIssuerID 60a885ac-0315-4323-974d-57783a7392a2 \
  SHUKR_BUILD_STAMP="$HASH" build > build/install-build.log 2>&1
if ! grep -q "BUILD SUCCEEDED" build/install-build.log; then
  echo "✗ The build failed (nothing installed). The errors:"
  grep -E "error:" build/install-build.log | head -10
  echo "  Full log: $COPY/build/install-build.log"
  exit 1
fi

APP="$DERIVED/Build/Products/$CONFIG-iphoneos/shukr.app"
FAILED=0
for phone in $PHONES; do
  name=$([[ $phone == $ME ]] && echo "your 13 Pro Max" || echo "her 15 Pro")
  echo "→ Installing on $name…"
  ok=0
  for try in 1 2 3; do
    if xcrun devicectl device install app --device "$phone" "$APP" > build/install-$phone.log 2>&1; then ok=1; break; fi
    sleep 5    # CoreDeviceError 4016 and a phone waking up usually pass on a retry
  done
  if (( ok )); then echo "✓ $name has $HASH ($CONFIG)"
  else
    FAILED=1
    echo "✗ $name: not installed — is it unlocked, and on the same Wi-Fi or plugged in?"
    grep -iE "error|unavailable" build/install-$phone.log | head -3
  fi
done
(( FAILED )) && exit 1
echo "Done. The build line at the bottom of ☰ / Settings reads $HASH."
