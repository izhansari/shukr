#!/bin/zsh
# Free disk space on the team Mac, safely — run when Izhan says "clean disk" (owner, 2026-10-22: "disk space often fills
# up … something we can do to deal with it routinely when i say"; it filled on 10-06, 10-14 (agents stuck), 10-17, 10-22).
# Dry run by default: lists what would go and how much. `--go` deletes.
#
#   zsh scripts/disk-clean.sh          what would be freed, and the big things only their owner can clear
#   zsh scripts/disk-clean.sh --go     delete it
#
# Only things that rebuild themselves: build output in every engineer's folder, Xcode's DerivedData, old iOS / watchOS
# symbol caches (Xcode copies a version again when a phone on it connects), Instruments recordings, scratch folders of
# sessions untouched for 2 days, simulators Xcode marks unavailable. Anything touched in the last hour is skipped, so
# nobody's running build or test breaks.
# Never: chat history (~/.claude/projects), his data copies, git repos / the board, install-build (install.sh's copy),
# release archives (*.xcarchive: their dSYMs read crash reports), *results* folders (measurements),
# a simulator in use — big ones are only listed, for their owner to clear (they hold test state).
set -u
ROOT="$HOME/Coding and Tinkering/shukrGit"
SCRATCH="/private/tmp/claude-$(id -u)"
go=0; [[ ${1:-} == --go ]] && go=1
total=0
typeset -a plan

fresh() { [[ -n $(find "$1" -newermt "-60 minutes" -print -quit 2>/dev/null) ]]; }   # touched in the last hour
add() {   # add <path> <label>: plan it unless fresh or a git checkout
  local p=$1 label=$2
  [[ -e $p ]] || return
  [[ -e $p/.git ]] && return
  [[ $p == $ROOT/board* || $p == *.xcarchive || $p == *results* ]] && return   # the board, release archives (dSYMs), measurements
  (( ${plan[(Ie)$p]} )) && return                                               # already listed
  if fresh "$p"; then print "  skip (in use)  $label"; return; fi
  local kb=$(du -sk "$p" 2>/dev/null | cut -f1); (( kb < 10240 )) && return   # under 10 MB: not worth it
  total=$(( total + kb )); plan+=("$p"); printf '  %6.1f GB  %s\n' $(( kb / 1048576.0 )) "$label"
}
free_gb() { df -k /System/Volumes/Data | awk 'NR==2{printf "%.1f", $4/1048576}'; }

print -P "%BFree now:%b $(free_gb) GB"
print -P "\n%BBuild output%b (each folder's build/, rebuilt by the next build)"
for co in "$ROOT"/shukr "$ROOT"/shukr-* "$ROOT"/shukr/.claude/worktrees/*(N/); do
  [[ -d $co/build ]] || continue
  for b in "$co"/build/*(N/); do add "$b" "${co#$ROOT/}/build/${b:t}"; done
done
print -P "\n%BXcode DerivedData%b"
for d in ~/Library/Developer/Xcode/DerivedData/*(N/); do add "$d" "DerivedData/${d:t}"; done
print -P "\n%BOld phone / watch symbol caches%b (the newest 2 per platform stay)"
for plat in "iOS DeviceSupport" "watchOS DeviceSupport"; do
  dir=~/Library/Developer/Xcode/$plat; [[ -d $dir ]] || continue
  for d in "$dir"/*(N/om[3,-1]); do add "$d" "$plat/${d:t}"; done
done
print -P "\n%BInstruments recordings%b (*.trace)"
find "$ROOT" "$SCRATCH" -maxdepth 6 -name '*.trace' -prune 2>/dev/null | while read -r t; do
  [[ $t == */build/* ]] || add "$t" "${t#$HOME/}"   # build/ ones are counted above
done
print -P "\n%BScratch folders of sessions untouched for 2 days%b"
for s in "$SCRATCH"/*/*(N/); do
  [[ -n $(find "$s" -mtime -2 -print -quit 2>/dev/null) ]] && continue
  proj=${s:h:t}; add "$s" "scratch ${proj#-Users-izhanansari-Coding-and-Tinkering-}/${${s:t}[1,8]}"
done

print -P "\n%BWould free: $(printf '%.1f' $(( total / 1048576.0 ))) GB%b"
print -P "\n%BOnly their owner can clear these%b (simulators over 5 GB — they hold test state; erase with \`xcrun simctl erase <udid>\`):"
xcrun simctl list devices | grep -oE '^    .+ \([0-9A-F-]{36}\)' | while read -r line; do
  u=$(echo $line | grep -oE '[0-9A-F-]{36}'); kb=$(du -sk ~/Library/Developer/CoreSimulator/Devices/$u 2>/dev/null | cut -f1)
  (( ${kb:-0} > 5242880 )) && printf '  %6.1f GB  %s\n' $(( kb / 1048576.0 )) "${line## }"
done
unavail=$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(')
(( unavail )) && print "  + $unavail unavailable simulator(s): removed with --go"

if (( go )); then
  print -P "\n%BDeleting…%b"
  for p in $plan; do rm -rf "$p"; done
  (( unavail )) && xcrun simctl delete unavailable
  git -C "$ROOT/shukr" worktree prune 2>/dev/null
  print -P "%BFree now:%b $(free_gb) GB"
else
  print "\nDry run: nothing deleted. \`zsh scripts/disk-clean.sh --go\` deletes the list above."
fi
