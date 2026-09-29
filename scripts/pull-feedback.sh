#!/bin/zsh
# Pull "What's new" feedback from the phones (notes #19) into shukrGit/feedback/.
# The app keeps it in the app group's Library/Feedback: feedback.json, feedback.md (unsent first), state.json,
# received.json and photos/ (jpg + mp4). Each phone that's connected and has feedback gets ONE mirror:
#   shukrGit/feedback/<phone>/feedback.json, state.json, feedback.md   overwritten on every pull
#   shukrGit/feedback/<phone>/photos/                                  only ever added to, nothing deleted
#   shukrGit/feedback/<phone>.md                                       the summary, photo links fixed up
#                                                                      (- Photo: → image, - Video: → plain link)
# Nothing heavy crosses the cable twice: feedback.json / feedback.md / state.json / received.json are copied one
# by one, then only the media files named in feedback.json (each item's `media` array + the old `photo` field)
# that the mirror doesn't have yet, one file each. A name already in the mirror is not fetched again.
# Then it writes received.json back to the phone (notes #23): {"received": id → when first pulled,
# "seen": id → that note's `updated` as pulled}, so the app shows "Received by Claude · <time>" and a fresh box
# for new feedback. Dev builds only (`devicectl device copy to` can't write into a TestFlight install): a failure
# is logged and the pull still counts.
#
#   scripts/pull-feedback.sh            # both phones
#   scripts/pull-feedback.sh 15Pro      # one: 13ProMax | 15Pro | <udid> (a udid's mirror folder is the udid)
#
# Testing without a phone (never touches devicectl):
#   PULL_FAKE_DEVICE_DIR=<dir> PULL_OUT_DIR=<scratch> scripts/pull-feedback.sh
# <dir> stands for the app group container (it holds Library/Feedback/...); the loop runs once as "FakePhone" and
# received.json is written into <dir>/Library/Feedback/. PULL_OUT_DIR replaces shukrGit/feedback.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${PULL_OUT_DIR:-$(cd .. && pwd)/feedback}"
FAKE="${PULL_FAKE_DEVICE_DIR:-}"
GROUP=group.betternorms.shukr.shukrWidget
typeset -A PHONES
PHONES=(13ProMax 00008110-001C041C2203801E 15Pro 00008130-00027DDE0AE8001C)

if [[ -n "$FAKE" ]]; then
  PHONES=(FakePhone fake); PICK=(FakePhone)
elif [[ $# -ge 1 ]]; then
  if [[ -n "${PHONES[$1]:-}" ]]; then PICK=("$1"); else PHONES=("$1" "$1"); PICK=("$1"); fi
else
  PICK=(13ProMax 15Pro)
fi

# fetch <path inside the app group container> <local file>  → 0 when the file landed at <local file>.
# The one place that talks to a phone (or, with PULL_FAKE_DEVICE_DIR, to a local folder).
fetch() {
  local src=$1 dst=$2
  rm -rf "$dst"
  if [[ -n "$FAKE" ]]; then
    [[ -f "$FAKE/$src" ]] || return 1
    cp "$FAKE/$src" "$dst"
    return $?
  fi
  xcrun devicectl device copy from --device "$udid" --domain-type appGroupDataContainer \
    --domain-identifier "$GROUP" --source "$src" --destination "$dst" >/dev/null 2>&1 || { rm -rf "$dst"; return 1; }
  # If devicectl treated the destination as a folder, lift the file out of it.
  if [[ -d "$dst" ]]; then
    local inner
    inner=$(find "$dst" -type f | head -1)
    [[ -n "$inner" ]] || { rm -rf "$dst"; return 1; }
    mv "$inner" "$dst.lifted" && rm -rf "$dst" && mv "$dst.lifted" "$dst"
  fi
  [[ -f "$dst" ]]
}

mkdir -p "$OUT"
pulled=0
for name in "${PICK[@]}"; do
  udid=${PHONES[$name]}
  tmp=$(mktemp -d)
  if ! fetch Library/Feedback/feedback.json "$tmp/feedback.json"; then
    echo "· $name: not reachable (locked, away, or no feedback yet)"
    rm -rf "$tmp"; continue
  fi
  if ! fetch Library/Feedback/feedback.md "$tmp/feedback.md"; then
    echo "· $name: no feedback yet"; rm -rf "$tmp"; continue
  fi
  # state.json: acknowledged topics, chat-request checks, tested ticks (states kept in the app's defaults).
  # received.json: the phone's existing one, so first-pulled times are kept. Both optional.
  fetch Library/Feedback/state.json "$tmp/state.json"
  fetch Library/Feedback/received.json "$tmp/received.json"

  # The media names feedback.json points at (also proves it parses before the mirror is touched).
  if ! python3 - "$tmp/feedback.json" > "$tmp/media.txt" <<'PY'
import json, os, sys
try:
    items = json.load(open(sys.argv[1]))
except Exception as e:
    raise SystemExit(f"  feedback.json: {e}")
if not isinstance(items, list):
    raise SystemExit("  feedback.json is not a list")
names = []
def add(v):
    if isinstance(v, dict):
        v = v.get("name") or v.get("file") or v.get("filename") or v.get("path")
    if isinstance(v, str):
        v = os.path.basename(v.strip())
        if v and v not in (".", "..") and v not in names:
            names.append(v)
for item in items:
    if not isinstance(item, dict):
        continue
    for v in (item.get("media") or []):
        add(v)
    add(item.get("photo"))
print("\n".join(names))
PY
  then
    echo "· $name: feedback.json didn't parse — left the mirror alone"
    rm -rf "$tmp"; continue
  fi

  dir="$OUT/$name"
  mkdir -p "$dir/photos"
  cp "$tmp/feedback.json" "$dir/feedback.json"
  cp "$tmp/feedback.md" "$dir/feedback.md"
  [[ -f "$tmp/state.json" ]] && cp "$tmp/state.json" "$dir/state.json"

  # Media: only what the mirror doesn't have. Never deleted, never overwritten.
  copied=0; had=0; gone=0
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    if [[ -f "$dir/photos/$m" ]]; then had=$((had + 1)); continue; fi
    if fetch "Library/Feedback/photos/$m" "$tmp/media.part"; then
      mv "$tmp/media.part" "$dir/photos/$m"; copied=$((copied + 1))
    else
      rm -rf "$tmp/media.part"; gone=$((gone + 1)); echo "  · $m isn't on the phone"
    fi
  done < "$tmp/media.txt"

  # "Photo: photos/x.jpg" → a Markdown image, "Video: photos/x.mp4" → a plain link, both pointing into the
  # mirror folder next to the file.
  sed -E -e "s#^- Photo: photos/(.*)\$#- Photo: ![](${name}/photos/\\1)#" \
         -e "s#^- Video: photos/(.*)\$#- Video: [\\1](${name}/photos/\\1)#" \
         "$tmp/feedback.md" > "$OUT/$name.md"
  unsent=$(grep -c '^- Status: unsent' "$OUT/$name.md")
  echo "✓ $name → $OUT/$name.md ($unsent unsent)"
  mediaLine="  media: $copied copied, $had already mirrored"
  [[ $gone -gt 0 ]] && mediaLine="$mediaLine, $gone missing on the phone"
  echo "$mediaLine"
  # received.json: the phone's existing one + every id in feedback.json, first-pulled time kept;
  # seen: every id → its `updated` as pulled.
  mkdir -p "$tmp/out"
  python3 - "$tmp" "$tmp/out/received.json" <<'PY'
import json, sys, datetime, pathlib
folder, out = pathlib.Path(sys.argv[1]), sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
try:
    old = json.loads((folder / "received.json").read_text())
except Exception:
    old = {}
have = old.get("received", {}) if isinstance(old, dict) else {}
seen = old.get("seen", {}) if isinstance(old, dict) else {}
items = json.loads((folder / "feedback.json").read_text())
added = 0
for item in items:
    i = str(item.get("id", "")).upper()
    if not i:
        continue
    if i not in have:
        have[i] = now
        added += 1
    seen[i] = item.get("updated") or item.get("created") or ""
pathlib.Path(out).write_text(json.dumps({"received": have, "seen": seen}, indent=2, sort_keys=True))
print(f"  received.json: {len(have)} ids ({added} new)")
PY
  if [[ -n "$FAKE" ]]; then
    mkdir -p "$FAKE/Library/Feedback" && cp "$tmp/out/received.json" "$FAKE/Library/Feedback/received.json" \
      && echo "  ✓ marked received on $name (fake device)"
  elif xcrun devicectl device copy to --device "$udid" --domain-type appGroupDataContainer \
       --domain-identifier "$GROUP" --source "$tmp/out/received.json" \
       --destination Library/Feedback/received.json >/dev/null 2>&1; then
    echo "  ✓ marked received on $name"
  else
    echo "  · couldn't write received.json to $name (TestFlight install, or it went away) — fine"
  fi
  pulled=$((pulled + 1))
  rm -rf "$tmp"
done
[[ $pulled -gt 0 ]] || exit 1
