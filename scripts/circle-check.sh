#!/bin/zsh
# circle-check.sh — the circle's motion check (board/circle-system.md). Simulators only, never a phone.
#
# Only for a change to a circle moment or its motion: CircleMoments.swift, CircleMotion.swift, mainCircle.swift's moment
# runner (run / playMarking / the swaps), or a new animation on the Salah circle. Copy, colors and small looks don't
# run it (CLAUDE.md, "Checks sized to the change": the build plus one screenshot). Owner, 2026-10-17: "when we were
# using the same circle everywhere … make sure that the animation and motion were correct … it's not really relevant
# anymore … I think it was a little bit OD."
#
#   scripts/circle-check.sh shots <base> [new] [options]                         ~2–3 min on a warm cache
#       The public look, dark and light, Salah page and open list (4 states), shot with <base>, then with [new], and
#       compared pixel by pixel → build/circle-check/shots-<time>/report.txt, plus a base | new | diff sheet per state
#       that differs. Exit 1 if anything differs. A difference of at most 4 levels (of 255) is reported as noise and
#       passes: the soft shadows' dither shifts when the view tree around them changes.
#       Each side is a commit or a .app. [new] left out = --new-app, else the .app you last built from this checkout
#       (Xcode's DerivedData for this shukr.xcodeproj; it warns when a .swift file is newer than it).
#       A commit is built incrementally in one shared worktree (build/circle-check/base-src, its derived data in
#       build/circle-check/dd, reused by every run) and its .app cached by hash (build/circle-check/apps/<hash>).
#       Each build is installed once: every state with base, then every state with new (the fake clock pins the time).
#   scripts/circle-check.sh build <commit>
#       Builds that commit as above and prints the .app path.
#   scripts/circle-check.sh strip <moment> [app|commit] [options]                 the part that checks motion
#       Records one moment: a Play item (mark begins welcome morning lost perfect streaks) or `launch` (a cold
#       launch). Re-timed to 60 fps → an overview strip, a 30 fps strip of the moment, and the one-frame jumps
#       (blinks / pops) jumps.py finds. Without an app it uses what's installed.
#
# Options:
#   --sim <udid|name>     default $CIRCLE_SIM, else the booted iPhone simulator (name your own: three sessions share
#                         this Mac)
#   --new-app <path>      shots: the new side's .app
#   --looks public,today,soft   default public (CircleTheme.standard: the raised list, soft ring, grey-blue)
#   --modes dark,light    --states salah,list,zikr,pause   default salah,list (zikr / pause: opt-in, the circle no
#                         longer carries over into the zikr wheel or the counting ring)
#   --strict              shots: re-install base after new and shoot every state again; any change → UNSTABLE, fail
#   --clock "HH:MM"       the app's wall clock, pinned (today at that time, or "YYYY-MM-DD HH:MM"). Default: shots
#                         04:00 (before Fajr: no partial arc — inside a prayer's window the arc's tip moves 1–2 px
#                         between launches, the times being recomputed to the second), strips 21:30 (Isha, mid-window)
#   --text-size <size>    shots at a Dynamic Type size (e.g. accessibility-extra-extra-extra-large)
#   --settle <s>          wait after launch before a shot (default 2), then until the screen holds still
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
#   • shots launch with `-demoCircleCheck still`: the welcome skipped (any -demo… argument does) and, in DEBUG builds
#     that know it, the day ring and its score shown whole at once (no draw-in, count-up or glow — summaryCircle's
#     `stillForCheck`), so a shot never lands mid-draw. Strips pass `-demoCircleCheck YES` and keep that motion;
#     the `launch` strip leaves it out.
# Notifications follow the real clock: a prayer's banner can land on a shot (it shows in the diff sheet); run again.
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
positional=(); looks=(public); modes=(dark light); states=(salah list)
clock=""; textsize=""; settle=2; strict=0; newapp=""; secs=12; from=3; palette=stone; sim=${CIRCLE_SIM:-}
while (( $# )); do
  case $1 in
    --sim) sim=$2; shift 2 ;;
    --new-app) newapp=$2; shift 2 ;;
    --strict) strict=1; shift ;;
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
# Commits build in one worktree (checked out to each in turn) with one derived data, so a build only compiles what
# changed since the last one; the .app is copied out per hash, so a commit is built once.
SRC=$OUT/base-src DD=$OUT/dd
build_commit() {
  local hash=$(git -C $ROOT rev-parse --short "$1^{commit}") || die "no commit $1"
  local app=$OUT/apps/$hash/shukr.app
  if [[ ! -d $app ]]; then
    mkdir -p $OUT/apps
    if [[ ! -e $SRC/.git ]]; then
      rm -rf $SRC; git -C $ROOT worktree prune
      git -C $ROOT worktree add -q --detach $SRC $hash >&2 || die "worktree add failed"
    else
      git -C $SRC checkout -q -f --detach $hash || die "checkout of $hash in $SRC failed"
    fi
    print -u2 "building $hash (log: $OUT/apps/$hash.log)…"
    ( cd $SRC && xcodebuild -project shukr.xcodeproj -scheme shukr -destination "id=$sim" \
        -derivedDataPath $DD SHUKR_BUILD_STAMP="$hash" build > $OUT/apps/$hash.log 2>&1 ) \
      || die "build of $hash failed: $OUT/apps/$hash.log"
    rm -rf $OUT/apps/$hash; mkdir -p $OUT/apps/$hash
    cp -Rp $DD/Build/Products/Debug-iphonesimulator/shukr.app $app
  fi
  print -r -- $app
}
app_for() { [[ $1 == *.app && -d $1 ]] && print -r -- ${1:A} || build_commit $1 }
# The .app last built from this checkout (Xcode / xcodebuild's DerivedData for this project).
own_app() {
  local d best="" bt=0 t
  for d in ~/Library/Developer/Xcode/DerivedData/shukr-*(N/); do
    [[ $(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" $d/info.plist 2>/dev/null) == $ROOT/shukr.xcodeproj ]] || continue
    local a=$d/Build/Products/Debug-iphonesimulator/shukr.app
    [[ -d $a ]] || continue
    t=$(stat -f %m $a/shukr); (( t > bt )) && { best=$a; bt=$t }
  done
  [[ -n $best ]] || die "no simulator build of this checkout; build it, or pass [new] / --new-app"
  local newer=$(find $ROOT/shukr $ROOT/shukrWidget -name '*.swift' -newer $best/shukr 2>/dev/null | head -1)
  [[ -n $newer ]] && print -u2 "circle-check: warning: ${newer#$ROOT/} is newer than $best — build first?"
  print -r -- $best
}

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
# terminate returns before the app is gone; a write it made on the way out landed after a restore (the store's WAL
# was newer than the restore, 2026-10-17). Wait until its process is gone (at most 5 s).
quit_app() {
  xcrun simctl terminate $sim $BUNDLE 2>/dev/null || true
  local i
  for i in {1..25}; do
    xcrun simctl spawn $sim launchctl list 2>/dev/null | grep -qE "^[0-9]+.*UIKitApplication:$BUNDLE\[" || return 0
    sleep 0.2
  done
  return 0
}
group_dir() { xcrun simctl get_app_container $sim $BUNDLE groups 2>/dev/null | awk '/shukrWidget/ {print $2}' }
STORE_SNAP=""
snapshot_store() {
  local g=$(group_dir); [[ -n $g ]] || die "install shukr on the simulator once first"
  STORE_SNAP=$OUT/store-$$; rm -rf $STORE_SNAP; mkdir -p $STORE_SNAP
  quit_app
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
  quit_app
  [[ -n $STORE_SNAP ]] && { restore_store; rm -rf $STORE_SNAP; STORE_SNAP="" }
  xcrun simctl status_bar $sim clear >/dev/null 2>&1 || true
  [[ -n $textsize ]] && xcrun simctl ui $sim content_size large
  return 0
}

look_args() {
  case $1 in
    public) print -r -- "-salahLook.list raised -salahLook.softRing YES -salahLook.palette greyBlue -salahLook.lines NO -salahLook.rowMotion settle" ;;   # CircleTheme.standard + RowMotion.standard
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
  quit_app
  restore_store
  xcrun simctl ui $sim appearance $mode
  local dark=$([[ $mode == dark ]] && print 1 || print 0)
  SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$(fakeclock) SIMCTL_CHILD_CIRCLE_CLOCK=$(clock_epoch) SIMCTL_CHILD_CIRCLE_CLOCK_FROZEN=${FROZEN_NOW:-${CIRCLE_CLOCK_FROZEN:-0}} \
    xcrun simctl launch $sim $BUNDLE ${=$(look_args $look)} -modeToggleNew $dark "$@" >/dev/null
}

# ---- shots
# One install per build: every state with base, then every state with new. The fake clock pins the time of day, so
# the minutes between them don't move anything.
install_app() { xcrun simctl install $sim $1
  launch ${looks[1]} ${modes[1]} -demoCircleCheck still; sleep $settle; still_shot $OUT/warm.png; rm -f $OUT/warm.png }   # warm-up: a demo flag misses on the first launch after an install
shoot() {       # shoot <file> <look> <mode> <state>
  # The pause screen shows a demo session's time and rate, measured as it opens: frozen there, so they read 0 every
  # run (running, the rate jittered 0.08 / 0.09 s).
  local FROZEN_NOW=$([[ $4 == pause ]] && print 1 || print "")
  launch $2 $3 -demoCircleCheck still ${=$(state_args $4)}
  sleep $settle
  still_shot $1 ${1:h:h}/report.txt
}
# The screen once it's drawn and still: two screenshots in a row that compare `same`, neither of them blank (a
# launch screen is one flat color; at most 12 tries, 0.4 s apart). A fixed wait shot the launch screen or a first
# frame fading in now and then with a dozen simulators booted on this Mac (load ~450). A still screen's PNG bytes
# differ shot to shot, so it's the pixels that are compared. Anything that never settles is shot after the last
# try and noted in the report.
still_shot() {  # still_shot <file> [report]
  local prev=$1.prev.png i have=0
  for i in {1..12}; do
    (( i > 1 )) && sleep 0.4
    xcrun simctl io $sim screenshot $1 >/dev/null 2>&1
    blank $1 && continue
    if (( have )) && [[ $(compare $prev $1) == same* ]]; then rm -f $prev; return 0; fi
    mv -f $1 $prev; have=1
  done
  (( have )) && mv -f $prev $1
  [[ -n ${2:-} ]] && print "MOVING: ${1:t:r} never settled (12 tries) — shot anyway" >> $2
  return 0
}
blank() {       # blank <png>: one flat color between the status bar and the home indicator
  local st=$(ffmpeg -hide_banner -nostats -v info -i $1 -vf "crop=iw:ih*0.915:0:ih*0.065,format=gray,signalstats,metadata=print:file=-" \
    -f null - 2>&1)
  local lo=$(print -r -- $st | sed -nE 's/.*YMIN=([0-9]+).*/\1/p' | head -1) hi=$(print -r -- $st | sed -nE 's/.*YMAX=([0-9]+).*/\1/p' | head -1)
  (( ${hi:-0} - ${lo:-0} <= 2 ))
}
shoot_all() {   # shoot_all <app> <dir>
  local look mode state
  mkdir -p $2
  install_app $1
  for look in $looks; do
    for mode in $modes; do
      for state in $states; do shoot $2/$look-$mode-$state.png $look $mode $state; done
    done
  done
}
# The status bar (top 6.5 %) and the home indicator (bottom 2 %) are left out: both are iOS's, and the indicator re-tints
# itself a beat after the content under it changes, so it differed between launches of the same build.
compare() {     # compare <a.png> <b.png> → "same" or "max box" (box y in the cropped image: + 6.5 % of the height)
  local stats=$(ffmpeg -hide_banner -nostats -v info -i $1 -i $2 -filter_complex \
    "[0]crop=iw:ih*0.915:0:ih*0.065[a];[1]crop=iw:ih*0.915:0:ih*0.065[b];[a][b]blend=all_mode=difference,format=gray,signalstats,metadata=print:key=lavfi.signalstats.YMAX:file=-,bbox=min_val=1" \
    -f null - 2>&1)
  local max=$(print -r -- $stats | sed -nE 's/.*YMAX=([0-9]+).*/\1/p' | head -1)
  if [[ ${max:-0} == 0 ]]; then print same
  elif (( max <= 4 )); then print "same (noise: max $max — shadow dither, invisible)"
  else print "differs (max $max, box $(print -r -- $stats | sed -nE 's/.*x1:([0-9]+) x2:([0-9]+) y1:([0-9]+) y2:([0-9]+).*/x \1–\2, y \3–\4/p' | head -1))"; fi
}
cmd_shots() {
  (( ${#positional} >= 1 && ${#positional} <= 2 )) || die "shots <base> [new]"
  : ${clock:=04:00}
  local t0=$SECONDS
  resolve_sim
  local base=$(app_for $positional[1]) new
  if (( ${#positional} == 2 )); then new=$(app_for $positional[2])
  elif [[ -n $newapp ]]; then new=$(app_for $newapp)
  else new=$(own_app); fi
  local run=$OUT/shots-$(date +%Y%m%d-%H%M%S); mkdir -p $run
  local tb=$SECONDS
  fixtures_on
  print "base: $base\nnew:  $new\nclock: $clock · sim $sim${textsize:+ · text $textsize}\nstates: ${(j:,:)looks} × ${(j:,:)modes} × ${(j:,:)states}\n" > $run/report.txt
  shoot_all $base $run/base
  shoot_all $new $run/new
  if (( strict )); then   # stability: base again, after new — the same build must shoot the same pixels
    shoot_all $base $run/base-again
    for f in $run/base/*.png; do
      [[ $(compare $f $run/base-again/${f:t}) == same* ]] \
        || print "UNSTABLE: ${f:t:r} differs from itself with the same build — fix the fixtures before trusting this run" >> $run/report.txt
    done
    xcrun simctl install $sim $new    # leave the new one installed
  fi
  fixtures_off
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
  print "\nbuilds $(( tb - t0 )) s · shots $(( SECONDS - tb )) s · total $(( SECONDS - t0 )) s" >> $run/report.txt
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
  quit_app
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
  *) sed -n '2,57p' ${0:A} | sed 's/^# \{0,1\}//' ;;
esac
