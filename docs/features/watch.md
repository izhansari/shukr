# Apple Watch — current state

Read with CLAUDE.md (rules, traps). When a feature changes, replace its lines here: current behaviour only,
≤ ~15 lines a feature; the story goes in the commit message. History: docs/history/.

**Apple Watch** (shukrWatch/, shukrWatchShared/, WatchSync.swift, WatchZikrSync.swift)
- Pages Zikr ← Salah → Settings; the phone's ring; marking with Undo through an id'd outbox; qibla arrow (true north); zikr wheel (never lazy — a lazy stack jumped on hard flicks; `.viewAligned(limitBehavior: .never)`; soft rings (`WatchSoftBand` + 6 pt glowing arc); centred on the whole screen, neighbours 0.25× smaller than the phone's with less pull; the phone's dot scrubber on the left, its own view; circles are Buttons; Freestyle's zikr chip on the bottom edge) and counter (Crown: `WatchCrownGate` — one count per step the counting way, a step the other way reloads, a 0.3 s pause reloads too; the first turn of each crown-mode start picks the way (no setting since 2026-10-06); `-demoWatchCrownTest` self-test), two-page pause (pause top left, − / +N top right; ‹ top left resumes — it holds the ✕ slot, so pause ignores taps 0.7 s after; Finish early is the big capsule), `WatchHaptics` (no setting: soft `.click` per count, `.directionUp` for each 100 / Tasbih Fatimah step / onto results — one haptic per count, the milestone replaces the count's: two back to back and watchOS drops one); inputs, one mode per session (owner, 2026-10-06; `WatchCountMode`, Settings → Count with = the default, the pause
  screen's second page switches it): **tap & pinch** (touches and drag-downs; Double Tap = `WatchDoubleTapScroller` (the only Double Tap way: "Button"
  and "Scroll auto" are gone), a 40-page list under the counter holding the Crown's focus — a move counts once, forwards, a quarter of the way in,
  against `base`, the real page, re-synced on rest (the `scrollPosition` binding doesn't follow Double Tap: 10 pinches
  → 55); a Crown scroll reports phases, a pinch never does, so nothing counts while a phase is live or for
  `crownQuiet` 0.6 s after — a flicked Crown reports idle while still sliding; the Crown never counts and never switches
  the mode, it shows "Crown is off"; its system buzz while scrolling the list stays) or **Crown** (`crownOwner` = the
  counter, the list `scrollDisabled`, taps / pinch don't count; a glass "Crown mode" pill on the bottom edge's centre, its Crown
  without an arrow until the way is picked, then ↑ / ↓; every start of crown mode picks the way again (Auto); it counts
  with the wrist down too — a tap goes back to tap & pinch, recreating the list (`scrollerGeneration`: a list once locked never took the Crown
  back); one `@FocusState crownOwner`, two fought). Nothing reaches the app with the screen off (Laraib's watch): no
  Double Tap (30 s of pinches, an empty log) and no Crown turn — watchOS takes them to wake the screen (a continuous
  buzz), and counting resumes once it's on; `screen dimmed` / `bright` lines in the log. `-watchPinchLogPrint` + `devicectl … process launch --console` streams
  `WatchPinchLog` live; DEBUG `-demoWatchCrown`, `-watchScrollFingerTest`, `-demoWatchDoubleTapScroll`; Tasbih Fatimah; complications. No schema change; the watch never creates or edits tasks; `WatchScoring` mirrors `PrayerScoring`.
- Salah list (`WatchPrayerList`): only the dot marks / asks to unmark (its own tap: 20 pt wide, the row's height);
  anywhere else on the row flips the time like the phone's `timeTap`; times `.fixedSize()` (scaled to fit, they came
  out different sizes) (to come: "in 2h 5m"; prayed: `WatchScoring.summary`; current / missed: no flip), back after
  `flipSeconds` 3 s; the ring's flip goes back after 3 s too, except in an unmarked prayer's last hour, where time left is the default (the phone's `lastHourLeft`). DEBUG `-demoWatchFlip "Fajr,Asr"`.
- Qibla map (WatchQiblaMap.swift, ask watch-qibla-map): the ring's Qibla arrow has its own tap → a full-screen SwiftUI
  `Map`, the phone's qibla mode only (no Explore / prayers / mosques): north, then Qibla-up after 0.35 s, the camera a
  little ahead so the dot sits low; the geodesic line (green 90 %, 3 pt), 🕋; `WatchQiblaRing` = the phone's
  CircleWithArrowOverlay; the pill "← Turn left N°" / "Turn right N° →" / "Facing Mecca 🕋"; aligned (the phone's
  accuracy, let go +1.5°) = green ring + edge glow, .success then a click each second. From the watch's own fix if
  recent, else the phone's spot. DEBUG `-demoWatchQiblaMap YES -demoWatchHeading 40`.
- Look (WatchLook.swift, ask watch-appearance): the phone sends `modeToggleNew` as `appearance` (0 light · 1 dark · 2
  auto; resent on change from shukrApp's root) — unless watch Settings → Look (`WatchLookChoice`: iPhone · Light · Dark · Auto) picks its own; auto = the phone's rule, light from sunrise to Maghrib, from the watch's
  own times, re-checked at each switch; wrist down = dark. The phone's public soft look (greyBlue): `WatchNeu.bg(scheme)`
  grey-blue / charcoal on every page, `WatchSoftBand` = the raised band, the arc fine and round with a glow. **watchOS
  draws the top-level clock and the sideways page dots white whatever the look** — no recolour, no hide (5 ways tried;
  inside a session or a sheet it follows the look); on the grey-blue it stays readable (decision watch-light-clock B).
  Every sheet / cover's content gets `.watchLookRoot()`; each root page `.watchPageBackground()`. DEBUG `-watchLook light|dark|auto`, `-watchPage 0|1|2`.
- The ring's look is `WatchRingFace` and the complication's view `PrayerComplicationView` / entry, both in shukrWatchShared (with `WatchNeu`'s soft colours and `WatchSoftBand`), which the iPhone app also compiles (Explore draws the real watch): `WatchPrayerRing` keeps the taps / hold / haptics on top; nothing watch-only in shukrWatchShared (`#if os(watchOS)` for the corner); `WatchRingFace.drawsStatically` (set in the iPhone's App.init, never on the watch) draws the complication's timer gauges from now.
- Untried on a real watch: wrist-down runtime, outbox catch-up, compass, memo, complications. DEBUG `-demoWatch`.

