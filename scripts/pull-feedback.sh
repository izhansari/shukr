#!/bin/zsh
# Pull "What's new" feedback from the phones (notes #19) into shukrGit/feedback/.
# The app keeps it in the app group's Library/Feedback: feedback.json, feedback.md (unsent first), state.json
# and photos/. Each phone that's connected and has feedback gives:
#   shukrGit/feedback/<date>-<phone>.md          the summary, photo links fixed up
#   shukrGit/feedback/<date>-<phone>/            feedback.json + photos/
# Never overwrites: if that name is taken it becomes <date>-<phone>-<HHMM>, then -2, -3…
# Then it writes received.json back to the phone (notes #23): every pulled note's id → when it was
# first pulled, so the app shows "Received by Claude · <time>" and a fresh box for new feedback.
# Dev builds only (`devicectl device copy to` can't write into a TestFlight install): a failure
# is logged and the pull still counts.
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
  base="$DAY-$name"
  if [[ -e "$OUT/$base.md" || -e "$OUT/$base" ]]; then
    base="$DAY-$name-$(date +%H%M)"
    n=2; stem="$base"
    while [[ -e "$OUT/$base.md" || -e "$OUT/$base" ]]; do base="$stem-$n"; n=$((n + 1)); done
  fi
  mkdir -p "$OUT/$base"
  cp "$tmp/Feedback/feedback.json" "$OUT/$base/" 2>/dev/null
  # state.json: acknowledged topics, chat-request checks, tested ticks (states kept in the app's defaults).
  cp "$tmp/Feedback/state.json" "$OUT/$base/" 2>/dev/null
  [[ -d "$tmp/Feedback/photos" ]] && cp -R "$tmp/Feedback/photos" "$OUT/$base/"
  # "Photo: photos/x.jpg" → a Markdown image pointing into the folder next to the file.
  sed -E "s#^- Photo: photos/(.*)\$#- Photo: ![](${base}/photos/\\1)#" "$tmp/Feedback/feedback.md" > "$OUT/$base.md"
  unsent=$(grep -c '^- Status: unsent' "$OUT/$base.md")
  echo "✓ $name → $OUT/$base.md ($unsent unsent)"
  # received.json: the phone's existing one (pulled with the folder) + every id in feedback.json,
  # first-pulled time kept.
  python3 - "$tmp/Feedback" "$tmp/received.json" <<'PY'
import json, sys, datetime, pathlib
folder, out = pathlib.Path(sys.argv[1]), sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
try:
    have = json.loads((folder / "received.json").read_text()).get("received", {})
except Exception:
    have = {}
items = json.loads((folder / "feedback.json").read_text())
added = 0
for item in items:
    i = str(item.get("id", "")).upper()
    if i and i not in have:
        have[i] = now
        added += 1
pathlib.Path(out).write_text(json.dumps({"received": have}, indent=2, sort_keys=True))
print(f"  received.json: {len(have)} ids ({added} new)")
PY
  if xcrun devicectl device copy to --device "$udid" --domain-type appGroupDataContainer \
       --domain-identifier "$GROUP" --source "$tmp/received.json" \
       --destination Library/Feedback/received.json >/dev/null 2>&1; then
    echo "  ✓ marked received on $name"
  else
    echo "  · couldn't write received.json to $name (TestFlight install, or it went away) — fine"
  fi
  pulled=$((pulled + 1))
  rm -rf "$tmp"
done
[[ $pulled -gt 0 ]] || exit 1
