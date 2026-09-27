#!/bin/zsh
# Pull "What's new" feedback from the phones (notes #19) into shukrGit/feedback/.
# The app keeps it in the app group's Library/Feedback: feedback.json, feedback.md (unsent first)
# and photos/. Each phone that's connected and has feedback gives:
#   shukrGit/feedback/<date>[-<phone>].md          the summary, photo links fixed up
#   shukrGit/feedback/<date>[-<phone>]/            feedback.json + photos/
#
#   scripts/pull-feedback.sh            # both phones
#   scripts/pull-feedback.sh 15Pro      # one: 13ProMax | 15Pro | <udid>
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="$(cd .. && pwd)/feedback"
GROUP=group.betternorms.shukr.shukrWidget
typeset -A PHONES
PHONES=(13ProMax 00008110-001C041C2203801E 15Pro 00008130-00027DDE0AE8001C)

if [[ $# -ge 1 ]]; then
  if [[ -n "${PHONES[$1]:-}" ]]; then PICK=("$1"); else PHONES=(custom "$1"); PICK=(custom); fi
else
  PICK=(13ProMax 15Pro)
fi

DAY=$(date +%Y-%m-%d)
mkdir -p "$OUT"
pulled=0
for name in "${PICK[@]}"; do
  udid=${PHONES[$name]}
  tmp=$(mktemp -d)
  if ! xcrun devicectl device copy from --device "$udid" --domain-type appGroupDataContainer \
       --domain-identifier "$GROUP" --source Library/Feedback --destination "$tmp/Feedback" >/dev/null 2>&1; then
    echo "· $name: not reachable (locked, away, or no feedback yet)"
    rm -rf "$tmp"; continue
  fi
  if [[ ! -f "$tmp/Feedback/feedback.md" ]]; then
    echo "· $name: no feedback yet"; rm -rf "$tmp"; continue
  fi
  base="$DAY"
  [[ ${#PICK[@]} -gt 1 ]] && base="$DAY-$name"
  rm -rf "$OUT/$base"; mkdir -p "$OUT/$base"
  cp "$tmp/Feedback/feedback.json" "$OUT/$base/" 2>/dev/null
  [[ -d "$tmp/Feedback/photos" ]] && cp -R "$tmp/Feedback/photos" "$OUT/$base/"
  # "Photo: photos/x.jpg" → a Markdown image pointing into the folder next to the file.
  sed -E "s#^- Photo: photos/(.*)\$#- Photo: ![](${base}/photos/\\1)#" "$tmp/Feedback/feedback.md" > "$OUT/$base.md"
  unsent=$(grep -c '^- Status: unsent' "$OUT/$base.md")
  echo "✓ $name → $OUT/$base.md ($unsent unsent)"
  pulled=$((pulled + 1))
  rm -rf "$tmp"
done
[[ $pulled -gt 0 ]] || exit 1
