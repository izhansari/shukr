#!/bin/zsh
# Get your own simulator ready for a shukr test in one command, so nobody gets stuck on a first-run screen (owner,
# 2026-10-20: agents "get stuck on very silly simulator issues … he couldnt get past the notification screen").
# It finds or makes "<Name> – <model>", boots it, installs a build if you pass one, allows + sets location, can load his
# data, and launches with -demoLand — a -demo… arg skips the welcome, setup, the tour and every permission prompt, so the
# notifications alert never comes up (simctl can't pre-allow notifications). Then it takes a screenshot: look at it first.
#
#   zsh scripts/sim-ready.sh Frank                         Frank – iPhone 17 Pro, newest iOS, Salah page
#   zsh scripts/sim-ready.sh Sami --app build/sim/Build/Products/Debug-iphonesimulator/shukr.app --page zikr
#   zsh scripts/sim-ready.sh Zoe --model "iPhone 17 Pro Max" --data latest -- -demoMarkMixed
#   zsh scripts/sim-ready.sh <udid> --fresh                erase first (a stuck alert or old state), then the same
#
# Options: --model "<device type>" (iPhone 17 Pro) · --ios <version> (newest installed) · --app <path.app> (install it;
# without it the installed build is used) · --page salah|zikr|journey|settings (salah) · --data original|latest (copy his
# data from ~/Library/Application Support/shukr-team/izhan-data-copies/) · --place <lat,lon> (New York) · --fresh ·
# --no-launch. Anything after -- goes to the app as launch args.
# The app sometimes misses demo args on its first launch after an install / erase / data copy: the script launches twice
# then. Prints the udid on the last line ("udid <id>") so you can name it in every later command.
set -u
BUNDLE=com.betternorms.shukr
GROUP=group.betternorms.shukr.shukrWidget
DATA_DIR="$HOME/Library/Application Support/shukr-team/izhan-data-copies"

who=${1:-}; [[ -z $who || $who == -* ]] && { sed -n '2,20p' $0; exit 1; }; shift
model="iPhone 17 Pro"; ios=""; app=""; page=salah; data=""; place="40.7128,-74.0060"; fresh=0; launch=1; extra=()
while (( $# )); do
  case $1 in
    --model) model=$2; shift 2;;  --ios) ios=$2; shift 2;;  --app) app=$2; shift 2;;  --page) page=$2; shift 2;;
    --data) data=$2; shift 2;;  --place) place=$2; shift 2;;  --fresh) fresh=1; shift;;  --no-launch) launch=0; shift;;
    --) shift; extra=("$@"); break;;
    *) echo "✗ unknown option $1"; exit 1;;
  esac
done
say() { print -P "%B›%b $*"; }

# 1. The device: a udid as given, else "<Name> – <model>" (found or made).
if [[ $who =~ '^[0-9A-F-]{36}$' ]]; then
  udid=$who
else
  name="${(C)who} – $model"
  udid=$(xcrun simctl list devices available | grep -F "    $name (" | head -1 | grep -oE '[0-9A-F-]{36}')
  if [[ -z $udid ]]; then
    runtime=$(xcrun simctl list runtimes available | grep -E "^iOS ${ios:-[0-9]}" | tail -1 | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+')
    [[ -z $runtime ]] && { echo "✗ no iOS ${ios:-} runtime installed"; exit 1; }
    udid=$(xcrun simctl create "$name" "$model" "$runtime") || { echo "✗ couldn't make $name"; exit 1; }
    say "made $name ($runtime) $udid"; fresh=2
  else
    say "found $name $udid"
  fi
fi

# 2. Fresh: erase (needs it shut down) — clears a stuck system alert, old data and permissions.
if (( fresh == 1 )); then
  xcrun simctl shutdown $udid 2>/dev/null; xcrun simctl erase $udid && say "erased"
fi
xcrun simctl boot $udid 2>/dev/null; xcrun simctl bootstatus $udid -b >/dev/null 2>&1; say "booted"
first=$(( fresh > 0 ))

# 3. The build.
if [[ -n $app ]]; then
  [[ -d $app ]] || { echo "✗ no app at $app"; exit 1; }
  xcrun simctl install $udid "$app" && say "installed ${app:t}, built $(stat -f '%Sm' -t '%m-%d %H:%M' "$app") (an old build has old bugs)" || exit 1; first=1
elif ! xcrun simctl get_app_container $udid $BUNDLE >/dev/null 2>&1; then
  echo "✗ shukr isn't installed on it: build for this sim and pass --app <…/Debug-iphonesimulator/shukr.app>"; exit 1
fi

# 4. Location: allowed (with no location the app opens on setup's location step whatever the args) and set.
xcrun simctl privacy $udid grant location $BUNDLE 2>/dev/null
xcrun simctl location $udid set "$place" >/dev/null 2>&1 && say "location allowed, set to $place"

# 5. His data (optional): into the app group, the app stopped first.
if [[ -n $data ]]; then
  src="$DATA_DIR/$( [[ $data == original ]] && echo 2026-10-02-original || echo 2026-10-18-latest )"
  [[ -f $src/shukr.store ]] || { echo "✗ no data copy at $src"; exit 1; }
  grp=$(xcrun simctl get_app_container $udid $BUNDLE groups 2>/dev/null | awk -F'\t' -v g=$GROUP '$1==g{print $2}')
  if [[ ! -d $grp ]]; then   # a fresh install has no group container until the app has run once
    xcrun simctl launch --terminate-running-process $udid $BUNDLE -demoLand salah >/dev/null; sleep 5
    grp=$(xcrun simctl get_app_container $udid $BUNDLE groups 2>/dev/null | awk -F'\t' -v g=$GROUP '$1==g{print $2}')
  fi
  [[ -d $grp ]] || { echo "✗ no app group container for $GROUP"; exit 1; }
  xcrun simctl terminate $udid $BUNDLE 2>/dev/null; sleep 1
  rm -f "$grp"/shukr.store-wal "$grp"/shukr.store-shm; cp "$src"/shukr.store* "$grp"/ && say "his data ($data) copied in"; first=1
fi

# 6. Launch past the opening, twice when the first launch may miss the args; then a screenshot to look at.
if (( launch )); then
  args=(-demoLand $page "${extra[@]}")
  if (( first )); then
    xcrun simctl launch --terminate-running-process $udid $BUNDLE "${args[@]}" >/dev/null; sleep 4
  fi
  xcrun simctl launch --terminate-running-process $udid $BUNDLE "${args[@]}" >/dev/null && say "launched: ${args[*]}"
  sleep 5
  shot="${TMPDIR:-/tmp}/sim-ready-${udid[1,8]}.png"
  xcrun simctl io $udid screenshot "$shot" >/dev/null 2>&1 && say "screenshot $shot — look at it before testing: a system alert or a setup screen there means stop and fix that first (--fresh clears a stuck alert)"
fi
echo "udid $udid"
