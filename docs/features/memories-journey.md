# Prayer photos, Memories, Journey — current state

Read with CLAUDE.md (rules, traps). When a feature changes, replace its lines here: current behaviour only,
≤ ~15 lines a feature; the story goes in the commit message. History: docs/history/.

**Prayer photos** (PrayerPhotos.swift; decisions (a) pill section, prayer-photos-day A)
- After a mark, the post-salah pill's second section (camera) → `PrayerPhotoCapture`: `DualCamera` = front + back at
  once (`AVCaptureMultiCamSession`, iPhone XS+; else the back), run on its own queue; review → Save. Files only, no
  schema: Application Support/PrayerPhotos/`<dayKey>-<name>-back|front.heic` (`PrayerPhotos.key`, Jumu'ah = Dhuhr; HEIC at
  1200 / 700 px since decision prayer-photo-storage A, cropped to the centre square on save (every view shows a square; owner 2026-10-08); older .jpg ones still read — go through `url` /
  `key(fromFile:)`, never a fixed extension); private, never synced, in the phone's backup; Memories' ⚙ → Space used
  (`PrayerPhotoStorageRow`). Add / Retake / Remove from the hold editor's "Your photo" row only while the prayer is on
  and marked; seen any time. **Unmarking deletes the photo** (`PrayerPhotos.discard(for:)` on every unmark path — the app's
  list, the widget's alert, the watch's unmark and undo). The list's and the widget's unmark ask with one card, `UnmarkPrompt` (PrayerPhotos.swift, in `OverlayAlert`'s window — owner 2026-10-15): "Unmark Asr?", the alert's old words ("Are you sure…", + "Its photo will be deleted too." — owner: keep the copy) · Unmark / Cancel; with a photo the photo itself sits in it (veiled while developing); the system alert only if another overlay is already up. `PrayerPhotoCard` = the Locket look (rounded squares, the front inset; a tap → `PrayerPhotoViewer`, a card
  over the blurred page (a clear `fullScreenCover`, no system slide; zooms out of the small photo and back — the card is
  scaled / moved from the small photo's global frame, the small photo hidden while it's out, the tag fading in; it
  follows a drag in any direction (shrinking a little) and zooms home past 120 pt; Share fades the share options up at
  the bottom over the page — the card previews them; a tap on the page around it puts the share options away, else closes; `PrayerPhotoFace` takes taps only on its rounded square (`contentShape` — a
  tall photo's cut-off parts caught taps above it and beside the buttons); tap outside / swipe down / ✕ close); `PrayerPhotoFramed` (decision prayer-photo-style C), also what Share sends: the prayer's symbol,
  name and day on a glass tag inside the photo, a shukr pill top right, and the place (masjid, else the spot's address) when Memories' ⚙ (`MemoriesSettings`) → Show where is on —
  `PrayerPhotos.showPlaceKey`, off by default, decision prayer-photo-location A). **The back photo is always the main
  picture** (owner 2026-10-08; the stored choice `PrayerPhotoMain` is gone, its key cleared once): a tap in the camera's
  review, the viewer, Memories' pile (`swapped`, back as the pile closes) or the share page swaps them on that screen only. **Developing** (PhotoDevelop / DevelopReveal, PrayerPhotos.swift): a day's photos are veiled ("Developing", the 10 px `veil`) until all five are marked or midnight; then each photo stays veiled with a calm "Tap to develop" (grey, light, `.ultraThinMaterial` capsule) until tapped — that tap only reveals (an overlay takes it: no open / zoom / swap), the veil fading off over 2.4 s (owner, 2026-10-14, option A; it used to clear the whole day by itself). Revealed per photo key (`prayerPhotos.revealedPhotos`, last 60; a trimmed key raises `revealedBefore`, the floor — photos on or before it count as revealed; the old per-day list still counts). Every copy clears with it (`PhotoRevealState`); the day ring's dot thumbnail takes no tap. Never a live blur over the pile's cards (flattened + masked, the app was killed opening a pile) — the veil image is laid over and masked to the photo. DEBUG `-demoMemories -photosDeveloping -photosDevelopAfter s`. A fifth whose photo waits for its tap breathes: a halo in its grade colour swells and fades behind the dot, three 2.5 s breaths after the ring draws in, again on the next open, never once developed (`DevelopBreath`, DaySummary.swift; Reduce Motion: a still soft halo). Day ring: dots
  only (photos on the ring went back to dots — owner); a photographed prayer's fifth tapped shows the photo in the centre (the circle's own tap layer steps aside: `DayPageState.photoInCentre`) (the strip
  under the line was dropped — it fought the list card). Map: the prayer's page shows it. DEBUG
  `-demoPostSalahOffer -demoPillPhoto` (the simulator's shutter makes a stand-in photo), `-demoPhotoViewer`.
- **Memories** — users read **Moments** (owner 2026-10-15: every visible "Memories"; code, keys and the `widgetMemories` flag keep the old name; Siri still takes "memories") (briefly "Journal" — the owner went back to Memories and its photo.stack icon; PrayerMemories.swift, ask prayer-memories; Journey's Moments tile, or the day page's pill while a developed photo waits ("N photos to develop ›", a thin grey ring by its icon; otherwise the pill is "Journey ›" — see Journey) — a full-screen cover via `MemoriesPresenter.open` (its tab bar needs to be a root; it was pushed for swipe-back, decision swipe-back-pages A, until the owner chose Photos' tab bar); the pile is a clear cover over it
  exists — `PrayerPhotoRevision.hasPhotos`; ⚙ top right = `MemoriesSettings`: Show where, Space used — not in Settings
  any more). Opens on Days. A tap on a day's stack (its newest) or a prayer's square opens `MemoriesDeck` in the page's
  own clear `fullScreenCover` over a frosted backdrop; it ZOOMS out of the tapped square and back into its day's square (owner 2026-10-10, replacing the 10-08 fade): `MemoryFrames` (a UIView per square, read only at open / close), built invisible then placed once its top card stops moving, driven frame by frame by `DeckZoomDriver` (a display link on SwiftUI's Spring — as SwiftUI animations the phone dropped ~1 in 3; Info.plist `CADisableMinimumFrameDurationOnPhone` for 120 Hz); no square (search, On this day, a day off screen) = the fade. Never start a second animation or a quiet transaction on the cover in the same turn as a zoom, and no `.animation(nil, …)` inside it. Before the chrome comes in, the cards under the top and the chrome are drawn at `MemoriesDeck.warm` (0.02), never 0: drawn first mid-zoom, they held it at ~90 %. Only the day's next card follows a swipe (the rest wait off the right edge). A fading close takes no touches. The share page is pushed on the cover's own NavigationStack (`.containerBackground(.clear, for: .navigation)`). **One day's pile at a time** (owner): within a day swipe left = the day's next one comes in from the right
  onto the top, swipe right = the top one goes back off to the right; past the day's last (first) photo the whole pile
  changes day like pages, in the strip's order (owner: forward must move the pile left): the previous day's pile waits off
  the left edge, the next day's off the right (`neighbour`, drawn exactly as they'll be — `restingPile`, lies picked for
  them too); past a day's edge all three follow the finger, then `page(to:)` slides them a width (`paging`) and `land`
  makes the new day current in place, quietly; a strip jump stands in on its side (`incoming`); `pendingTop` /
  `shownIndex` let the caption and strip move at once; `MemoryCard` keeps the last 40 decoded pairs so nothing flashes on
  landing. Landing on
  its first (last) photo. The seen ones lie under it (4 shown), each at a random `Lie` (nudge +
  tilt, not stored — owner); the top one is centred, 0.3 × its tilt; the deck's `index` is set in `init`. Cards are the
  plain photo (no text — owner). **The day strip** (`MemoriesDayStrip`, decision memories-day-strip A) along the bottom, under a 1 pt line (primary 22 %; the system Divider was too faint on the frost):
  every day from the first photo to today (days without photos faint; a rest on one moves on to the nearest photo day),
  the number + weekday; the centred day is the pile's — bigger and full, the rest shrink and fade by distance
  (`visualEffect` in `.scrollView` space); `viewAligned` + `contentMargins` centre it and `scrollPosition(id:)` has NO
  anchor (`.center` with the margins landed 4 days off); its days are built in `init`; it's positioned by us with
  `ScrollPosition.scrollTo(x:)` (the id binding left a short strip, three days, on the wrong day) — measured 2026-10-16
  (d1f85f3): an animated scrollTo counts from the content's start (x = index × cell), an INSTANT one sets the content offset
  itself (x = index × cell − margin), so the opening scroll subtracts the margin and waits until the margins are in
  (`openOnPileDay`); before, the strip opened 4 days past the pile's day, and on iOS 27 the scroll and the snap fought every
  frame (100 % CPU, the pile frozen part-way). Measure the offsets before changing it. The pile moves the strip; dragging the strip moves the pile live, day by day under the finger (`onScrub`,
  the centred index from `onScrollGeometryChange` contentOffset + insets — the position binding only caught up at rest;
  photo days only), and at rest — only after a finger moved it (`touched`; the strip's own scrolls also came to rest, and one at its start sent the pile to the first day) — an empty day snaps the strip and pile to the nearest photo day (`onRest`); a tap jumps; a tick per day. Month name + "N photos" over each 1st; the month of the earliest
  visible day (`onScrollTargetVisibilityChange`) is pinned at the left edge and pushed out by the next month's 1st
  (positions measured in the strip's own named space — `.scrollView` space reported a stale 50). DEBUG `-logDayStrip`.
  Captions come from `infos` (`prepareInfo`: the day and both neighbours worked out before they show, so the caption
  moves as one view — filled in afterwards its lines moved separately). Under the pile the prayer's name, "Prayed 1:12 PM", the place on its own line (always: the masjid, else
  `PrayerPlaceNames`, looked up once), then the score as a ring in its grade colour + the grade word (fixed heights, so
  nothing moves); the caption follows a horizontal drag (0.35 × drag, ±90, fading) and hands over to the next on landing;
  a tap on the place opens `PrayerPlaceMapSheet` (SwiftUI Map: the prayer's Marker in its grade colour, masjid / hands
  glyph as on the app map; the app map's glass capsule — globe = Standard ⇄ Satellite on the shared `MapModes.satelliteKey`,
  then back to the pin, green while centred; DEBUG `-demoPlace` gives stand-ins a Manhattan spot)
  (+ the place with Show where; `PrayerPhotos.facts` / `placeText`) and the note (tap → edit in an alert; notes are
  `<key>-note.txt` beside the photos, written from the camera's review — "Add a note" — or the pile; the pile shows 3 lines in
  a fixed 58 pt box so nothing moves from photo to photo, a tap opens a TextEditor sheet) — the three slide
  sideways together with every photo (`wentBack` picks the side, flipped a turn before the move — `moving(back:)` — or the leaving name took the old side),
  above the strip the day's five prayer symbols (`prayerMarks`: the top one bright, others with a photo dim, without faint; tap → it), then Share and ✕ (grey circles, no nav bar) → `PrayerPhotoShareComposer`
  (pushed): the framed card (`PrayerPhotoFramed`: shukr + prayer + day always; one shared `PrayerShareOptions` + `PrayerShareControls` +
  `PrayerShareButton` for this page and the viewer's panel — edit them once; Location and Prayer score — a ring,
  `score:` — as toggles; the place as City (default — owner) or Address — `PrayerSpotAddress.city`, "Cary, NC"; the pile's line uses the masjid, else the city; tap the picture to choose the main one), the picture rendered only when an option changes. A tap
  on a card swaps the pictures; a drag down follows the finger anywhere (`freeDrag`), the cards under the top gathering in (`fold`), and closes;
  closing zooms it home from where it is (the deck's own drag picks the axis on its first move, leaning sideways: only
  within ~40° of straight down closes, only the way down counts; the neighbouring days are out of the view while dragged
  down or zooming). **Finding** (decision memories-finding C): a heart in the pile
  (`PrayerPhotoFavorites`, UserDefaults); the bottom bar (see **The bars**). The pile is a clear `fullScreenCover` (no slide) so the bars are never hidden / re-shown. Searching shows a
  results LIST (`resultsList`: chips Favorites · Jumu'ah · At a masjid · With a note on top, rows = photo, prayer, date,
  the note / masjid / place; a tap opens the pile over the results only); words (all must match, folded: no case / accents /
  apostrophes) search `buildIndex`'s text per photo — prayer, note, masjid, Gregorian + Hijri (`islamicUmmAlQura`) dates,
  the place's name (`PrayerPlaceNames`: the prayer's own spot named once per ~1 km and kept as words only — no location
  copied, owner); results feed `visible` (levels and pile); toggling search re-ids the level's ScrollView so it starts at
  the bottom. **Smooth switches:** thumbnails come in two sizes only (180 / 360 px, cost-limited NSCache) and a
  re-drawn square takes its cached image in `init`; `parse` / `monthTitle` share one formatter and memo; `months` is
  grouped once per change (`FrameBook.months`); piles under 60 pt get a 2 pt shadow. "On this day" cards (earlier years, today's date) under today's month (DEBUG `-demoOnThisDay` with
  `-demoMemories`). **Three levels** (`MemoriesPage.Level`, like Photos): Prayers (the strips) · Days (a
  calendar per month, Sun–Sat rows from `Calendar.firstWeekday`; a day with photos = a small stack, else its faint number; up to today only)
  · Months (a stack per month). **One prayer** (`MemoriesPage(onlyPrayer:)`, from Prayer scores' "N photos ›"; owner
  2026-10-16: "Just make it look like the Photos app on Apple"): `onePrayerGrid` — four square columns, oldest top-left,
  opening at the bottom on the newest, titled with the prayer, no level switch (search stays); a tap opens that prayer's pile. No pinch and no flying squares (owner: dropped with the zoom); **One pushed screen** (owner 2026-10-08: swipe-back first, then pinch with flying squares, then search on a tap): pushed (`navigationDestination`, system back = swipe back); the three levels swapped in place in ONE view so `matchedGeometryEffect` in `pinch` flies the squares into their stacks — from a pinch (`MagnifyGesture` < 0.8 up, > 1.25 down) or the switch (`go`, a spring). The bottom bar is the page's own `safeAreaInset` (`bottomBar`: `levelSwitch` — buttons + a sliding `levelPill` — and a magnifier; searching, our TextField + ✕), glass from `barGlass` (`glassEffect(.regular.interactive())`, material before 26) — NOT the system toolbar (its shared glass left ghost circles / dead taps on his phone) and NOT a TabView (a tab bar's search needs a full screen: no swipe-back; pushed, its field never appeared — 3 ways tried). XCUITest's pinch-in never reaches the gesture (pinch out does): test pinches with the simulator tool's two-finger path. Prayers rows: five squares share the width. the levels change from the bar; a tap on a stack goes down into it (`go(_:at:)`, the level opens at that id, else at the month on screen; `tops` / `pinned`). Each level has its own ScrollView, swapped whole. DEBUG `-demoMemories` (seeds stand-in photos), `-demoMemoriesOpen`, `-demoShareScore 0.86` (a score, a place and both share options on for stand-ins), `-heicSelfTest` (encode + decode
  times, run on a phone with `devicectl … process launch --console`). **Sim trap:** the simulator hangs decoding HEIC
  (never returns, starving the task pool so even JPEGs stop loading), so `encoded` writes JPEG there; phones decode it in ~30 ms.

**Journey** (Journey.swift, JourneyDay.swift, JourneyMakeUp.swift; spec + phases board/mocks/journey/spec.md, mock-ups v5; Bradley builds it)
- ☰ → Journey (`JourneyPresenter.open`, pushed on the root stack) replaces Insights and the Moments row; the day page's pill
  (`MemoriesFooterLink`) reads "Journey ›" (still "N photos to develop ›" → Moments while one waits); deep link / What's new
  link "journey" ("insights" too). The old Insights pages are gone (2026-10-21). iOS 26's back button shows no page name.
- Journey on one screen (owner 2026-10-16, board/mocks/journey-v6/build-plan.md): `JourneyPage` doesn't scroll — "Journey"
  + "Since <date>" with Prayer scores' ring on its right (`JourneyMiniRing` at 54 pt, the way in: the page zooms out of it,
  `.navigationTransition(.zoom)`, and the edge swipe shrinks it back — owner 2026-10-18); the card (`JourneyHomeCard`,
  YourJourney.swift); three rows (`JourneyHomeRow`): To make up · Moments · Milestones (→ `JourneyMilestonesPage`); This
  month went with the goal (owner 2026-10-18). The card's streak and best streak are the Salah page's rule (`PrayerGoal`).
- **The goal and the fresh start** (PrayerGoal.swift, FreshStart.swift; owner 2026-10-18, his picks for
  board/goal-reset-inventory.md): Your goal — Settings → Journey, or Journey's own row (Opening · Middle · In its window ·
  Prayed, `PrayerGoal.title`; under the old `prayerStreakMode` key; v2, owner 2026-10-21, spec
  board/mocks/your-goal-v2/spec.md + spec-pics/): the title and the rule, verbatim, the same for every step ("Set a goal for
  how early you aim to pray. Don't miss a prayer, and keep nearly all at your goal: that's a strong week"); the editor's
  dial with no clock (GoalHero.swift: `GoalKnobBox` 300 pt — the thirds unbroken, made-up grey, the hollow dot where the
  step stops counting, `PrayerGoal.edge`), the step's name + one line ("Prayed before its window ends" …); the steps
  (`GoalStepRow`: Opening · Middle · In Window · Prayed, a dot under yours); a tap glides the dial (spring 0.75 / 0.84), a
  drag in the box turns it and the nearest step goes live (selection buzz); "At this goal, last week" (GoalLastWeek.swift,
  the last finished full week at the step tried, `GoalPreview.lastWeek`): "was strong" (green, ✓ None missed · ✓ N later
  than goal · 3 allowed) / "wasn't strong" (ink outlines, only what broke it: N missed — unmarked + 5 a no-record day —,
  later only past 3, never on Prayed) / "was excused" ("Nothing was asked of you.") / before a full week "After your
  first full week…"; excused prayers as a frosted "Tuesday excused ›" chip → "How excused plays towards goal:" (a measured
  sheet, the week's own numbers, "Got it"). No link off the page (owner: "just say 7 missed"). "Aim for <step>" (live
  only off your goal) → success buzz, "✓ Saved", the page stays; the back button off during it; Back never saves.
  Words, verdicts and the button swap out, then in (`OutThenIn`). Tried and dropped: v7's Prayer circle card over a radio
  list with the streak in the ring (round 1); three rings over a list; "you'd have had 25 of 35". New installs start on
  In its window, existing users keep what an unset goal meant — FirstRunSetup.migrateDefaults) and Fresh start (one prayer day; the page,
  Design 2026-10-19: soft look, 30 pt title; Az-Zumar 39:53 centred in a pressed 256 pt ring that is itself held 1.5 s,
  "Hold the ring" a caption low in it with a light sweeping over it; a sage glow from the bottom, growing with the hold;
  then the ring rises (NeuLiftCard) and holds Day N, the facts give way to "One prayer at a time." + Bukhari 6464,
  Done · Undo; four flat lines on what changes and stays, one a "Reset prayers to make up" toggle (`freshStartClearsMakeUp`, off by default; Start fresh = To make up
  and Prayer scores' "to make up" count from its day, made up ones too; nothing deleted); swaps are `.blurReplace` in
  fixed slots. Every later visit looks like the first (owner 2026-10-19): its hold starts again today (Undo right after
  brings back the one it replaced), "Counting since your fresh start on <date>" at the bottom, "Undo fresh start" →
  an alert). `PrayerGoal.meets` is
  the one rule (gradingCriteria, streakDay, `Day.metGoal`); `PrayerStats.countsFrom` the one date; either change posts
  `PrayerStats.rulesChanged` → a silent recount (no hearts, milestones recorded as seen), Max recounted from rows. From
  the date: the whole card (days and prayers marked, the rate "N% of days met your goal" after 3 finished days, best),
  the streak, rank, runs, Prayer scores' All time (the line under its chart "since Oct 17"; the chip stays "All time") and trends, Journey's ring; the header line
  "Since your fresh start, Oct 17 ⇄" flips the card to lifetime and back (`JourneyStore.lifetime`); lifetime always: month lines,
  firsts; kept: Moments, and To make up unless Start fresh. Days before it draw at
  0.35 everywhere (`JourneyTileColor.beforeFreshStart`); a quiet "Fresh start" milestone (never celebrated). Both travel
  in Your Data's copy. Not built: "Show earlier" (the calendar still scrolls back).
  One layout of four (`JourneyPage.fits`: the loosest whose content fits the room, measured from a `Color.clear`; rows
  scroll under a 12-week card only where nothing else fits) — never four built copies (perf #2).
- **The week card** (JourneyWeekHero.swift; behind `MetricsLook.on` — DEBUG on, Release off until he OKs the look): this week as
  one ring toward a strong week, each kind of prayer its own pill with a gap between, no shared track (owner, 2026-10-21, on
  https://claude.ai/artifact/XowC56NDXsAUPk2NzcvbGt: "different arcs pills instead of sharing a common track … no overlap").
  `JourneyGoalRing`, from the top going right: green for the prayers that met your goal, then a dashed hairline for those
  still to come (`UpcomingTrack`, the Salah ring's own). From the top going left: excused (frost, crosshatched), below your
  goal (light grey), then one hollow pill, "not marked" — the missed prayers and the days with no record together (owner,
  option B: simpler, and it never calls a day with no record missed), past below. The "strong" tick is the finish line, fixed: 3 short
  of what the week asks (the top on Prayed: every prayer); it no longer moves onto the not-marked pill (owner, 2026-10-21,
  Fable's critique: it read as "strong is halfway"). All of it sits in the Salah circle's raised band (11 pt, NeuRingTrack's
  surface, shade and light), the parts 6 pt inside it, the green with the Salah arc's glow (owner: "looks very similar to
  the Salah ring"). Days before the first mark ever are left off the ring. A tap on a pill or the tick
  dims the rest; the centre says its count and words, and its line takes the line slot under the days ("17 · not marked" —
  "Sun – Tue: fill them in. Today: make up 2."; the tick: "32 · for a strong week" — "Fill in Sun – Tue and make up 2
  first…"); the same part or off a pill puts it back.
  No "up to 3" under below your goal (it read as if 3 were allowed with a prayer missed). Centre "15 of 35" over your goal's
  words ("in their windows"); a week that asks
  nothing "– · excused this week". Under it the seven days as dots: every prayer marked → the Salah list's filled light-grey
  done dot, any unmarked (to come, missed, partly) hollow (owner: "hollow gray for unmarked and filled light gray for
  marked"), no record dotted, all excused frosted, today's initial in ink; a tap opens the day's page ("tapping those days
  can just push the day ring page for now"; today only once all five are in), a dotted day its Pick sheet. One line under
  them, the first that's true: Excused Mode on → "Excused Mode is on. Your week picks up when it ends." (owner, 2026-10-21,
  A; no tick, no make-up / fill-in asks, a picked part keeps this line, no "Did you pray?"); out of reach → the mid-week line ("Your goal this week, every prayer in its window, is out of
  reach now. You've still got 19 prayers left, so make them count." — owner: "account for the messaging for when they miss
  their strong week"); a missed prayer → "Make up today's Fajr for a strong week" (several: "Make up N missed prayers…");
  a no-record day → "Fill in Monday for a strong week"; both → "Make up 2 missed prayers and fill in 3 days for a
  strong week"; when making up would take all 3 spare (above Prayed a made-up prayer is below the goal): "Make up 3 missed
  and fill in 3 days, then pray the rest in their windows for a strong week". Above In its window a day with no record
  can only be filled in below the goal, so it counts against the spare (`Week.stillPossible`); enough already → "A strong week, so far"; else the rule in Your
  goal's words: "Don't miss a prayer, and keep 32 at your goal: that's a strong week" (Sunday: "A new week. " first; on
  Prayed just "Don't miss a prayer") (a fixed 3-line slot). The header names the strong-week streak from 1 ("This week · Oct 11 – 17 · 1 strong week in a row"; nothing at 0;
  owner, 2026-10-21: "do item 9"). The last two finished weeks banked
  ("Oct 4 – 10 · 34 of 35 · strong"; a complete week "35 of 35 · strong" — "complete" was never explained); a day with no record asked in their slot ("Yesterday has no record. Did
  you pray?" · Pick which · Not now — steps aside after 3 visits; owner, 2026-10-20). All from `PrayerMetrics`, off the main
  thread on `log.version`. Its ↗ opens the calendar; the day dots fly into it and back (`JourneyFlightGeometry.ringTiles`).
  No header ring (owner: "looks weird to have the upper right ring so busy … make it a list item"): "Your prayers" is a row ("35 of 35 in their time · last 7 days"), the page zooming out of it. Above it, "Your goal" ("How early you aim to pray", the goal's name on the right) pushes the same `PrayerGoalPage` as Settings' row (owner, 2026-10-21: "so its not tucked away in settings" → "Make it a list item for now"); Milestones now sits below the fold on a 17 Pro (the rows scroll).
- Journey is pushed from ☰ (and the day page's link, To make up's pill, What's new) — owner 2026-10-19, after two days as the
  pager's right page (its in-pager band and pager hold were deleted 2026-10-20, cleanup tangle 4).
- The card: the count ("631 days you marked a prayer"; a picked day takes its place), "THE LAST N WEEKS" (or the months in
  view) · the current streak ("N-day streak" / "Start a streak today"; it and "best streak" are the Salah page's streak at
  the goal, from the fresh start; today never breaks it), the expand button; under the grid prayers marked · % of days met
  your goal · best streak. The grid a
  week a row (`JourneyCardRow`, Equatable: a row redraws only for its own days / pick / streak light / look / log version):
  a 40 pt right-aligned column of grey month names (tap → that month), seven 11 pt bars (corner 4) in `JourneyTileColor`
  (kind × the user's own heat rank; unmarked = a hairline only). Opens on today's week (pinned until a finger scrolls).
  A tap picks a tile (ringed; a tap near it lets it go; a scroll lets it go); hold 0.3 s and move to pick across rows
  (`JourneyHoldPick`, UIKit, per row; a quick drag scrolls). The month rail: hold the names 0.22 s, then the finger's height
  is the month (a pill names it, a tick each, the grid follows; a slim scroll bar at rest). "best streak" tapped lights its
  days and scrolls there; again, back to where you were. A picked day: the top is `JourneyDayTop` (fifths ring with the
  score, date, "Day N · Rth of M", its kind; the ring flies into the day page), the bottom `JourneyDayExtrasRow` (notes ·
  photos · on the map · min of zikr → the day page back card's destinations; the photo pile rises, fades out).
- The expanded card (`JourneyExpandedPage`, JourneyExpanded.swift; owner 2026-10-17, board/journey-expand-plan.md): the card's ↗
  (a month name: that month focused and centred) grows the card to the whole screen in Journey's host — its top
  (the count · a picked day's JourneyDayTop · a focused month's numbers) and bottom (the three numbers · the day's extras),
  between them the same continuous weeks as rings (`JourneyExpandedRow`, Equatable; JourneyDayCell), each month's name with
  "N days" / "score N" centred on its month's rows ("Feb ’25" outside this year). Focus only by a tap: a ring (picks its day
  too) or a name (its numbers at the top); a finger scroll lets both go. Hold 0.3 s and drag: picks across rows. Hold the
  names: the month rail, its month in focus as it goes (and after). Pinch in: the year (spread there: back). "best streak" at
  the bottom lights its days and scrolls there (again: back). With MetricsLook (prayer-metrics rows 6 + 11) the line under
  the count is the Salah bar's ("N strong weeks", or "N in their windows this week") and the three numbers are prayers
  marked · "your typical week, then and now" (26 → 31; PrayerMetrics.typicalWeek, from 16 fully logged weeks) · the best
  streak of strong weeks (its weeks lit), all from `YourJourneyStats.strongRun` / `typicalWeek` — no lifetime average,
  and the same count as the bar. Under the numbers the legend Goal met · All five
  (not at Pray all five) · Incomplete lights only those days (`JourneyHighlight`); a scroll, ring, month, rail or the year lets either go. The
  tiles look (`setTiles`) is no longer reached (cleanup later). The toggle top right
  (square.grid.3x3 ↔ calendar) flies the focused / middle month into the year and a small month's name back. The old
  month page (window of months, neighbours, month rail) is gone.
- The year (`JourneyYearView`, JourneyYear.swift): every year from the first, opening on this one; twelve small months
  (`JourneyYearMonth`, Equatable) each with its name, "N days · score N" (the month's average score) or "Away", and its days
  as one picture (`JourneyYearSquares`, a Canvas: tile colors, unmarked hairline, future faint, today outlined; the picked
  ring drawn over it); a tap on a month (its name or squares) flies back into the expanded weeks with it focused; the
  squares' geometry is one set of statics on `JourneyYearSquares` (drawing, hit test, layout, the flight); ‹, the edge swipe and the toggle go back to the weeks (`JourneyFlightGeometry.yearBack`).
- **Your prayers** (the rethink's phase 3; behind `MetricsLook.on`): Prayer scores' page as built — its motion, rows,
  chart, chips and back dial — titled "Your prayers", with no ring (owner, 2026-10-20: "get rid of the ring for the your
  prayers altogether. And the main thing can just be the histogram"); one ring both ways (`YourPrayersRing`, YourPrayers.swift):
  all five, the day ring's fifths, each prayer's hollow dot at its usual place in its window over the chips' span, the fifth
  in that third's colour, "when you usually pray" in the middle, a fifth tapped opens that prayer. Open, its fifth unfolds
  into its whole window (CircleMotion.ringMove; the others gone first): the thirds come apart into their colours (faint past
  the dot), the dot turns to the same place, "29% · into its window, usually" in the middle; the open ring takes no tap (a tap
  for the latest mark's time was tried and dropped — owner: "That means nothing to me because I don't even know the window").
  ‹ / the edge fold it on the dial. The rows'
  and the open prayer's line "in its time 224 of 329" over the span the chips pick; the open prayer's "Usually a third of the way
  in · about 26 minutes in today" (in words, not a percent — Frank's check) (`Prayer.usualShare`, the median place in its window over the span's in-window
  marks — season-proof, owner 2026-10-20; today's window from PrayerMetrics.recent; "1 h 41 min" past an hour) — never a
  clock time ("the times of prayers shift"); no score insight, no score trend.
- Prayer scores (`PrayerScoresPage`, PrayerScores.swift): its title + the one-liner beside the day page's own ring at 70 %
  (`DayRing` on the raised disc: each prayer's fifth in its average grade, its dot at its usual place in the window; under the
  number "average lifetime score" / "… last 30 days"); All time · 30 days · 7 days under the header (`PrayerScores.build(span:)`,
  kept in `prayerScores.span`; a span's trend reads against the span before). The one-liner never names the strongest as the
  one that "needs you most" (a tie → the lowest score). The ring = the score when prayed; rows "97 · 98% prayed" + their dots (`PrayerScoresChart`: 14 slots across the window +
  a Qaza block). A row's (or a fifth's) tap: its symbol, name and line rise over the switch into the header (the "97 · "
  folds away), the rest after it lands; the way back runs on one dial (`ScoresBack`): ‹ plays it, a left-edge swipe holds
  it under the finger (¼ / a flick finishes, else springs back; cancel-safe), the hero flying by measured frames
  (`ScoresHeroFrames`) and turning white → grey as it lands; another fifth switches straight to that prayer. A span switch
  keeps what's shown until the new data is in, then everything moves in place in one smooth 0.45 s, never blank (owner
  2026-10-21): numbers roll, the ring's dots turn, each chart's columns grow or drain a dot at a time
  (`PrayerScoresChart.dots`, animatable) as its height eases; what sits under the chart (chips, its line, the rows)
  rides that height and switches its words at once — rolled or faded while sliding they ghosted (owner 2026-10-21: "I care
  more about the histogram than anything else"); all five's rows re-rank by sliding. Held until his layout pass (owner 2026-10-18, layout first): the open's scripted beats, the
  first-draw hitch, the bar title snap; 7 days' empty one-liner, "100 · 100% prayed" wrapping. A prayer's page: "Lately, usually…" + its trend, the big chart — tap or hold-drag a slot → "A–B min after it
  starts · N prayers (P%)" (Qaza: "Made up after it ended · …"; no grade word) in the place of the line under the chart
  ("238 prayed since Nov 2024" — no missed count, the To make up row has it; owner 2026-10-18), crossfaded. Rows and the sentence rank by in its time over due, the rows' own number ("Asr is your strongest. Fajr needs
  you most."; a grey "You pray Isha latest in its window" when that's a third prayer; all equal: "All five (or "All 3") in
  their time alike.") — Fable's review, owner's yes 2026-10-21; no per-prayer day-streak insight; grade chips, insight, To make up,
  photos, Where you pray it. Thin data: "Not enough yet" (kept steady through the rise).
- `JourneyLog.build`: every row once, one per prayer per day (completed wins); a mark = done / missed / to come / excused /
  none; **active day** = ≥ 1 mark, rates and dues only over active days; days before the first mark don't exist; Excused
  badges and keys only once `Excused.ranges` isn't empty.
- Off the main thread: `JourneyLog.load` and `JourneyMakeUpPage.entries` read on a detached task with their own
  `ModelContext` and return values; Journey reads the log once per open and builds Prayer scores' row from it (one `now`,
  one set of excused ranges). **JourneyStore** (JourneyStore.swift, 2026-10-20) is the one owner of Journey's numbers: the log,
  the card's stats, the header ring, To make up's count and list, Prayer scores' spans, the lens; one loader (`load`, landing
  via `JourneyFlights.whenIdle`, a newer load drops an older one); a mark / outside mark / Excused change marks it stale, a
  goal or fresh-start change also empties the spans and resets the lens; `loadIfNeeded` (the map day sheet's "Day N" reads
  without Journey opened first). Pages never open blank; a page under another reloads on its return (`dirty`).
- Transitions (JourneyTransitions.swift, the host `journeyMonthHost`): card ↔ expanded (every tile in view flies into its ring
  by its place, the card's month names to their labels; the card's rows report their own place — `.cardWeek`; the page
  comes down 0.35 s after the flight back lands), expanded ↔ year (a month's days fly to their squares), a ring → its day page (from its ring in the expanded weeks or
  the card's top ring; ‹ / edge swipe fly back). `JourneyFrameLog` (journey-transitions.log) only in DEBUG or with -journeyFrameLog or -demoJourneyFlightRun.
- Perf log (`JourneyPerf`, JourneyPerf.swift; DEBUG, or Release with -journeyPerf): each move opens a window — frames, late,
  hitch, worst gap, main busy, body counts, timed loads — in Library/Caches/journey-perf.log. Phone runs:
  `PERF_ARGS="-journeyPerf" zsh scripts/perf-paging.sh <label> testJourneyPerfPass` (a scripted pass; its month steps
  predate the expanded card). Rules it taught: no hidden sizing copies of a page, rows / months
  as Equatable views keyed on `JourneyLog.version`, many small shapes → one Canvas.
- The day page (`JourneyDayPage`, on the Salah tab's day page pieces — the day page merge, owner 2026-10-15, DayPage.swift;
  the full behaviour in salah.md "The day page merge"): the date centred on top ("Thursday, October 15" / "Today · Jumada I 4"),
  `DayRing` + `DayCentre` on a raised 222 pt disc, the picked prayer's note and place under it (`DayPickLines`), the list card
  (dot · name · time prayed with the grade under it; a tap picks, a hold opens the prayer editor) between two plain chevrons
  (owner: no soft-ring chevrons), the pill under it ("Your day" / "Prayers", placeholders) fades the card to the day's rows
  and back (`DayFadeCard`: out, then in, on one card surface — owner 2026-10-16, it flipped before; `DayBackCard`: Notes ·
  Photos · On the map · Zikr); the side shown belongs to the page, so the next day comes in on it; a drag sideways moves a day (the left edge stays the system's back);
  days change at once, no fade. A day opens only once over or all five marked (`JourneyPage.open`, `canGoForward`) — never
  live rows. The back's Photos row → that day's pile (`MemoriesPage(openPile:leaveWithPile: true)`, pushed without a slide),
  On the map → `JourneyDayMapSheet`, Zikr → `ZikrDaySessionsPage`; a missed prayer picked → "N to make up ›" → To make up.
  A whole excused day: `ExcusedDayCard("Excused that day")`.
- A day row (owner, 2026-10-21: "use the same editor as in the salah tab prayer list. and delete the old" sheet): a hold on a
  marked prayer opens the Salah list's editor (`PrayerTimeEditSheet`, the same range and saves — `PrayerTimeEditSheet.range`,
  `PrayerViewModel.applyEditorChange`; applied at once, no day-page wait); a hold on an unmarked prayer whose window is over
  asks the late-mark question (Set a time · I don't know the time · Making it up now) and marks through
  `markFromJourney(_:_:)` — Journey's own path, no spot (where it was prayed then isn't known; the editor can add one). A tap
  on the dot does what the Salah list's does: a marked prayer unmarks after the same "Are you sure…" alert
  (`unmarkFromJourney`), an unmarked one gets the question; a tap anywhere else picks. `.journeyChanged` reloads the pages.
  (The old Journey prayer sheet, 2026-10-15 — ring, window bar, wheel, map card, trash — was deleted.)
- To make up (`JourneyMakeUpPage`): unmarked ended prayers on active days only, never excused; Made up = Qaza now. From
  Prayer scores (`startOnly:`) it opens with that prayer's tile on. Always all months (owner, 2026-10-17: no "<month> | All
  months"). Top: the total missed, made up · % left, the bar, then five raised prayer tiles — Prayer scores' grade tiles,
  each prayer's count over its name (a tap shows only it; the one on pressed in; none left faint); months newest first as pinned headings with "N left · N made up"; the month scrubber on the right edge is the
  Zikr wheel's dots (owner: not the soft look; > 3 months; the top month's dot bigger, a cleared month sage, a pill naming
  the month while dragging, a tick each). Made up keeps the row in place as "✓ Made up · Undo" for 3 s (`settling`; Undo = unmark; decision
  makeup-made-feedback A), then it leaves the list (made up = marked on a later prayer day); a month with nothing left drops
  out; "✓ N made up · Show" under the total (`journey.showMadeUp`, Reminders' Show Completed — owner: not folded under each
  month) puts them back in their months, greyed, by date; an empty side shows "All caught up" (a check drawn in + a
  success buzz). A row opens its sheet (decision makeup-row-tap: kept).
- Milestones (`JourneyMilestone.earned`, YourJourney.swift; earned once, dated, newest first, a hollow dot each): Day one,
  first Jumu'ah / first prayer at a masjid, 7…365 days in a row at the goal ("…, all Perfect"; from the fresh start, its
  id carries it), Fresh start (quiet), each streak that beat the best ("Your best
  streak: N days" over its dates on the latest), every hundredth prayer (the list keeps the 100th, 500th, every thousandth
  and the latest), each prayer's 100th/500th, a perfect day, Welcome back (the latest return only), years since day one.
  Each carries its card: symbol, about, how, day.
- Milestone celebration (`MilestoneCelebration`, `MilestoneCelebrationLayer` over the Salah page): after a mark (2.4 s)
  and on every activation, a new milestone plays the first mark's glow + card (`TourOverlay` .celebrate) in its words,
  "Added to Your journey.", Continue; seen ids in `journey.milestones.seen` (the first check records silently, and so does the first after a
  `seenVersion` bump — 2: every hundred prayers; never over the tour). DEBUG `-demoMilestoneCelebration`.
- DEBUG `-demoJourney [-demoJourneySeed] [-demoJourneyMonth N] [-demoJourneyDay N
  [-demoJourneySheet 0…4]] [-demoJourneyMakeUp]` (`-demoJourneySeed` adds ~100 earlier days where none, a break with four
  "opened, nothing marked" days; the demo opens only every other launch — ☰ always works).

