#!/bin/zsh
# circle-check.sh — the circle system's check (board/circle-system.md, step 0). Simulators only, never a phone.
#
#   scripts/circle-check.sh build <commit>
#       Builds that commit for the simulator (cached in build/circle-check/apps/<hash>/) and prints the .app path.
#   scripts/circle-check.sh shots <base> <new> [options]
#       Every fixed state (looks × modes × states), first with <base>, then with <new> (each a commit or a .app),
#       compared pixel by pixel → build/circle-check/shots-<time>/report.txt, plus a base | new | diff sheet per
#       state that differs. Exit 1 if anything differs. A difference of at most 4 levels (of 255) is reported as
#       noise and passes: the soft shadows' dither shifts when the view tree around them changes.
#   scripts/circle-check.sh strip <moment> [app|commit] [options]
#       Records one moment: a Play item (mark begins welcome morning lost perfect streaks) or `launch` (a cold
#       launch). Re-timed to 60 fps → an overview strip, a 30 fps strip of the moment, and the one-frame jumps
#       (blinks / pops) jumps.py finds. Without an app it uses what's installed.
#
# Options:
#   --sim <udid|name>     default $CIRCLE_SIM, else the booted iPhone simulator
#   --looks today,soft    --modes dark,light    --states salah,list,zikr,pause
#   --clock "HH:MM"       the app's wall clock, pinned (today at that time, or "YYYY-MM-DD HH:MM"). Default: shots
#                         04:00 (before Fajr: no partial arc — inside a prayer's window the arc's tip moves 1–2 px
#                         between launches, the times being recomputed to the second), strips 21:30 (Isha, mid-window)
#   --text-size <size>    shots at a Dynamic Type size (e.g. accessibility-extra-extra-extra-large)
#   --settle <s>          wait after launch before a shot (default 5)
#   --secs <s>            strip length (default 12)      --from <s>   strip: ignore jumps before this (default 3)
#   --soft-palette <p>    the soft look's palette (default stone)
#
# Fixtures, so two runs can be identical (Frank, circle-system.md):
#   • the app's wall clock starts at --clock and runs at real speed (scripts/circle-check/fakeclock.c, loaded with
#     DYLD_INSERT_LIBRARIES; no app code), so every run sees the same time of day; a frozen clock stalled SwiftUI's
#     springs until the next 1 s tick (CIRCLE_CLOCK_FROZEN=1 still freezes it);
#   • the status bar is overridden (9:41, full battery, Wi-Fi); the simulator's location is left as it is
#     (setting it made the first fix land at a different moment each run, moving the times by seconds);
#   • the app group's store is copied before the run and restored before every launch (no state leaks between
#     shots; nothing the check does is kept);
#   • `-demoCircleCheck` skips the welcome for shots (any -demo… argument does); the `launch` strip leaves it out.
# Reduce Motion has no simctl switch: turn it on in the simulator's Settings → Accessibility → Motion, then run
# `strip` again.

set -e
setopt extended_glob
ROOT=${0:A:h:h}
OUT=$ROOT/build/circle-check
BUNDLE=com.betternorms.shukr
mkdir -p $OUT

die() { print -u2 "circle-check: $*"; exit 2 }

# ---- options
cmd=${1:-help}; (( $# )) && shift
positional=(); looks=(today soft); modes=(dark light); states=(salah list zikr pause)
clock=""; textsize=""; settle=5; secs=12; from=3; palette=stone; sim=${CIRCLE_SIM:-}
while (( $# )); do
  case $1 in
    --sim) sim=$2; shift 2 ;;
    --looks) looks=(${(s:,:)2}); shift 2 ;;
    --modes) modes=(${(s:,:)2}); shift 2 ;;
    --states) states=(${(s:,:)2}); shift 2 ;;
    --clock) clock=$2; shift 2 ;;
    --text-size) textsize=$2; shift 2 ;;
    --settle) settle=$2; shift 2 ;;
    --secs) secs=$2; shift 2 ;;
    --from) from=$2; shift 2 ;;
    --soft-palette) palette=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) positional+=$1; shift ;;
  esac
done

# ---- the simulator (a simulator only: its udid must be in simctl's device list)
resolve_sim() {
  local list=$(xcrun simctl list devices available)
  if [[ -z $sim ]]; then
    sim=$(print -r -- $list | grep "iPhone" | grep "(Booted)" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    [[ -n $sim ]] || die "no booted iPhone simulator; pass --sim"
  elif [[ $sim != [0-9A-F]##-* ]]; then
    local name=$sim
    sim=$(print -r -- $list | grep -F "    $name (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    [[ -n $sim ]] || die "no simulator named \"$name\""
  fi
  print -r -- $list | grep -q $sim || die "$sim is not a simulator"
  xcrun simctl bootstatus $sim -b >/dev/null
}

# ---- an app: a .app path as is, else a commit built (and cached)
build_commit() {
  local hash=$(git -C $ROOT rev-parse --short "$1^{commit}") || die "no commit $1"
  local app=$OUT/apps/$hash/Build/Products/Debug-iphonesimulator/shukr.app
  if [[ ! -d $app ]]; then
    local src=$OUT/src/$hash
    rm -rf $src; mkdir -p $src $OUT/apps
    git -C $ROOT archive $hash | tar -x -C $src
    print -u2 "building $hash (log: $OUT/apps/$hash.log)…"
    ( cd $src && xcodebuild -project shukr.xcodeproj -scheme shukr -destination "id=$sim" \
        -derivedDataPath $OUT/apps/$hash SHUKR_BUILD_STAMP="$hash" build > $OUT/apps/$hash.log 2>&1 ) \
      || die "build of $hash failed: $OUT/apps/$hash.log"
  fi
  print -r -- $app
}
app_for() { [[ $1 == *.app && -d $1 ]] && print -r -- ${1:A} || build_commit $1 }

# ---- fixtures
fakeclock() {
  local lib=$OUT/fakeclock.dylib src=$ROOT/scripts/circle-check/fakeclock.c
  if [[ ! -f $lib || $src -nt $lib ]]; then
    xcrun -sdk iphonesimulator clang -dynamiclib -arch arm64 -target arm64-apple-ios18.0-simulator \
      -framework CoreFoundation -O2 $src -o $lib || die "fakeclock build failed"
  fi
  print -r -- $lib
}
clock_epoch() {
  if [[ $clock == *-*-*" "*:* ]]; then date -j -f "%Y-%m-%d %H:%M" "$clock" +%s
  else date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $clock" +%s; fi
}
group_dir() { xcrun simctl get_app_container $sim $BUNDLE groups 2>/dev/null | awk '/shukrWidget/ {print $2}' }
STORE_SNAP=""
snapshot_store() {
  local g=$(group_dir); [[ -n $g ]] || die "install shukr on the simulator once first"
  STORE_SNAP=$OUT/store-$$; rm -rf $STORE_SNAP; mkdir -p $STORE_SNAP
  xcrun simctl terminate $sim $BUNDLE 2>/dev/null || true
  cp -p $g/shukr.store* $STORE_SNAP/ 2>/dev/null || true
  [[ -d $g/.shukr_SUPPORT ]] && cp -Rp $g/.shukr_SUPPORT $STORE_SNAP/
}
restore_store() {
  local g=$(group_dir)
  rm -f $g/shukr.store*; cp -p $STORE_SNAP/shukr.store* $g/ 2>/dev/null || true
  if [[ -d $STORE_SNAP/.shukr_SUPPORT ]]; then rm -rf $g/.shukr_SUPPORT; cp -Rp $STORE_SNAP/.shukr_SUPPORT $g/; fi
}
fixtures_on() {
  xcrun simctl status_bar $sim override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode notSupported >/dev/null
  [[ -n $textsize ]] && xcrun simctl ui $sim content_size $textsize
  snapshot_store
}
fixtures_off() {
  xcrun simctl terminate $sim $BUNDLE 2>/dev/null || true
  [[ -n $STORE_SNAP ]] && { restore_store; rm -rf $STORE_SNAP; STORE_SNAP="" }
  xcrun simctl status_bar $sim clear >/dev/null 2>&1 || true
  [[ -n $textsize ]] && xcrun simctl ui $sim content_size large
  return 0
}

look_args() {
  case $1 in
    today) print -r -- "-salahLook.list today -salahLook.softRing NO -salahLook.lines YES -salahLook.rowMotion today" ;;
    soft)  print -r -- "-salahLook.list well -salahLook.softRing YES -salahLook.palette $palette -salahLook.lines NO -salahLook.rowMotion room" ;;
    *) die "unknown look $1" ;;
  esac
}
state_args() {
  case $1 in
    salah) print -r -- "" ;;
    list)  print -r -- "-demoPrayerListOpen" ;;
    zikr)  print -r -- "-demoZikrPage" ;;
    pause) print -r -- "-demoPauseScreen" ;;
    *) die "unknown state $1" ;;
  esac
}
# launch <look> <mode> <extra args…>: the app, fresh, clock pinned, store restored
launch() {
  local look=$1 mode=$2; shift 2
  xcrun simctl terminate $sim $BUNDLE 2>/dev/null || true
  restore_store
  xcrun simctl ui $sim appearance $mode
  local dark=$([[ $mode == dark ]] && print 1 || print 0)
  SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$(fakeclock) SIMCTL_CHILD_CIRCLE_CLOCK=$(clock_epoch) SIMCTL_CHILD_CIRCLE_CLOCK_FROZEN=${FROZEN_NOW:-${CIRCLE_CLOCK_FROZEN:-0}} \
    xcrun simctl launch $sim $BUNDLE ${=$(look_args $look)} -modeToggleNew $dark "$@" >/dev/null
}

# ---- shots
# Base and new are shot back to back for each state (base, new; then new, base for the next…), so a slow drift
# (the location's first fix, a minute ticking over somewhere) never separates them. One install per state.
CURRENT_APP=""
use_app() { [[ $CURRENT_APP == $1 ]] && return; xcrun simctl install $sim $1; CURRENT_APP=$1
  launch ${looks[1]} ${modes[1]} -demoCircleCheck YES; sleep $settle }   # warm-up after an install, not shot
shoot() {       # shoot <app> <file> <look> <mode> <state>
  use_app $1
  # The pause screen shows a demo session's time and rate, measured as it opens: frozen there, so they read 0 every
  # run (running, the rate jittered 0.08 / 0.09 s).
  local FROZEN_NOW=$([[ $5 == pause ]] && print 1 || print "")
  launch $3 $4 -demoCircleCheck YES ${=$(state_args $5)}
  sleep $settle
  xcrun simctl io $sim screenshot $2 >/dev/null 2>&1
}
shoot_pairs() { # shoot_pairs <base app> <new app> <run dir>
  local base=$1 new=$2 run=$3 look mode state first=1 flip=0
  mkdir -p $run/base $run/new
  for look in $looks; do
    for mode in $modes; do
      for state in $states; do
        local n=$look-$mode-$state
        if (( flip )); then shoot $new $run/new/$n.png $look $mode $state; shoot $base $run/base/$n.png $look $mode $state
        else shoot $base $run/base/$n.png $look $mode $state; shoot $new $run/new/$n.png $look $mode $state; fi
        if (( first )); then   # stability: the same build, the same state, again
          shoot $base $run/base-again.png $look $mode $state
          [[ $(compare $run/base/$n.png $run/base-again.png) == same* ]] \
            || print "UNSTABLE: $n differs from itself with the same build — fix the fixtures before trusting this run" >> $run/report.txt
          first=0
        fi
        flip=$(( 1 - flip ))
      done
    done
  done
}
compare() {     # compare <a.png> <b.png> → "same" or "max box"
  local stats=$(ffmpeg -hide_banner -nostats -v info -i $1 -i $2 -filter_complex \
    "[0]crop=iw:ih-ih*0.065:0:ih*0.065[a];[1]crop=iw:ih-ih*0.065:0:ih*0.065[b];[a][b]blend=all_mode=difference,format=gray,signalstats,metadata=print:key=lavfi.signalstats.YMAX:file=-,bbox=min_val=1" \
    -f null - 2>&1)
  local max=$(print -r -- $stats | sed -nE 's/.*YMAX=([0-9]+).*/\1/p' | head -1)
  if [[ ${max:-0} == 0 ]]; then print same
  elif (( max <= 4 )); then print "same (noise: max $max — shadow dither, invisible)"
  else print "differs (max $max, box $(print -r -- $stats | sed -nE 's/.*x1:([0-9]+) x2:([0-9]+) y1:([0-9]+) y2:([0-9]+).*/x \1–\2, y \3–\4/p' | head -1))"; fi
}
cmd_shots() {
  (( ${#positional} == 2 )) || die "shots <base> <new>"
  : ${clock:=04:00}
  resolve_sim
  local base=$(app_for $positional[1]) new=$(app_for $positional[2])
  local run=$OUT/shots-$(date +%Y%m%d-%H%M%S); mkdir -p $run
  fixtures_on
  print "base: $base\nnew:  $new\nclock: $clock · sim $sim${textsize:+ · text $textsize}\n" > $run/report.txt
  shoot_pairs $base $new $run
  fixtures_off
  xcrun simctl install $sim $new    # leave the new one installed
  local bad=0
  grep -q UNSTABLE $run/report.txt && bad=1
  for f in $run/base/*.png; do
    local n=${f:t:r} verdict=$(compare $f $run/new/${f:t})
    printf "%-22s %s\n" $n $verdict >> $run/report.txt
    if [[ $verdict != same* ]]; then
      bad=1
      ffmpeg -v error -y -i $f -i $run/new/${f:t} -filter_complex \
        "[0][1]blend=all_mode=difference,format=gray,lutyuv=y=val*8,format=rgb24[d];[0][1][d]hstack=3,scale=900:-1" \
        $run/diff-$n.png
    fi
  done
  cat $run/report.txt
  print "\n$run"
  return $bad
}

# ---- strip
cmd_strip() {
  local moment=${positional[1]:-}; [[ -n $moment ]] || die "strip <moment> [app|commit]"
  : ${clock:=21:30}
  resolve_sim
  [[ -n ${positional[2]:-} ]] && xcrun simctl install $sim "$(app_for $positional[2])"
  local look=${looks[1]} mode=${modes[1]}
  local name=$moment-$look-$mode-$(date +%H%M%S) dir=$OUT/strips; mkdir -p $dir
  fixtures_on
  xcrun simctl terminate $sim $BUNDLE 2>/dev/null || true
  xcrun simctl io $sim recordVideo --codec=h264 --force $dir/$name.mp4 >/dev/null 2>&1 &
  local rec=$!
  sleep 1.5                         # the recorder needs a moment; the app must be in front when it starts
  if [[ $moment == launch ]]; then launch $look $mode
  else launch $look $mode -demoCircleCheck YES -salahPlay $moment; fi
  sleep $secs
  kill -INT $rec; wait $rec 2>/dev/null || true
  fixtures_off
  # Re-time (the recorder writes a frame only on change), then the strips and the jumps.
  ffmpeg -v error -y -i $dir/$name.mp4 -vf "fps=10,scale=60:-1,tile=40x$(( (secs * 10 + 2 + 39) / 40 ))" \
    -frames:v 1 $dir/$name-overview.png
  ffmpeg -v error -y -i $dir/$name.mp4 -vf "fps=30,trim=start=$from,setpts=PTS-STARTPTS,crop=iw:ih*0.62:0:ih*0.2,scale=100:-1,tile=30x$(( ((secs - from) * 30 + 29) / 30 ))" \
    -frames:v 1 $dir/$name-30fps.png
  print "moment $moment · $look $mode · clock $clock\n$dir/$name.mp4\n$dir/$name-overview.png (10 fps)\n$dir/$name-30fps.png (30 fps from ${from}s, one row a second)\n"
  ffmpeg -v error -i $dir/$name.mp4 -vf "fps=60,trim=start=$from,setpts=PTS-STARTPTS,scale=120:262,format=gray" -f rawvideo - \
    | python3 $ROOT/scripts/circle-check/jumps.py 120 262 60 3 $from | tee $dir/$name-jumps.txt
  print "\nLook at the strip too: never two rings or two texts in one frame, never an empty circle between states."
}

# Whatever happens, put the simulator back: the store, the status bar, the text size.
trap 'fixtures_off; exit 130' INT TERM
trap 'fixtures_off' EXIT
case $cmd in
  build) resolve_sim; build_commit ${positional[1]:-HEAD} ;;
  shots) cmd_shots ;;
  strip) cmd_strip ;;
  *) sed -n '2,33p' ${0:A} | sed 's/^# \{0,1\}//' ;;
esac
