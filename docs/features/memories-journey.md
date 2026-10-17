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

**Journey** (Journey.swift, JourneyDay.swift, JourneyPrayerSheet.swift, JourneyMakeUp.swift; spec + phases board/mocks/journey/spec.md, mock-ups v5; Bradley builds it)
- ☰ → Journey (`JourneyPresenter.open`, pushed on the root stack) replaces Insights and the Moments row; the day page's pill
  (`MemoriesFooterLink`) reads "Journey ›" (still "N photos to develop ›" → Moments while one waits); deep link / What's new
  link "journey" ("insights" too). InsightsView is kept in code, unreached. iOS 26's back button shows no page name.
- Journey on one screen (owner 2026-10-16, board/mocks/journey-v6/build-plan.md): `JourneyPage` doesn't scroll — "Journey"
  + "Since <date>"; the card (`JourneyHomeCard`, YourJourney.swift); five rows (`JourneyHomeRow`): This month (hold →
  `ThisMonthMeasure`, `journey.thisMonth`) · Prayer scores · To make up · Moments · Milestones (→ `JourneyMilestonesPage`).
  One layout of four (`JourneyPage.fits`: the loosest whose content fits the room, measured from a `Color.clear`; rows
  scroll under a 12-week card only where nothing else fits) — never four built copies (perf #2).
- The card: the count ("631 days you marked a prayer"; a picked day takes its place), "THE LAST N WEEKS" (or the months in
  view) · the current streak ("N-day streak" / "Start a streak today"), the expand button top right → the month. The grid a
  week a row (`JourneyCardRow`, Equatable: a row redraws only for its own days / pick / streak light / look / log version):
  a 40 pt right-aligned column of grey month names (tap → that month), seven 11 pt bars (corner 4) in `JourneyTileColor`
  (kind × the user's own heat rank; unmarked = a hairline only). Opens on today's week (pinned until a finger scrolls).
  A tap picks a tile (ringed; a tap near it lets it go; a scroll lets it go); hold 0.3 s and move to pick across rows
  (`JourneyHoldPick`, UIKit, per row; a quick drag scrolls). The month rail: hold the names 0.22 s, then the finger's height
  is the month (a pill names it, a tick each, the grid follows; a slim scroll bar at rest). "best streak" tapped lights its
  days and scrolls there; again, back to where you were. A picked day: the top is `JourneyDayTop` (fifths ring with the
  score, date, "Day N · Rth of M", its kind; the ring flies into the day page), the bottom `JourneyDayExtrasRow` (notes ·
  photos · on the map · min of zikr → the day page back card's destinations; the photo pile rises, fades out).
- The month (`JourneyMonthPage`, JourneyMonth.swift): the title with an up-down symbol (tap → the year); Month | Year in the
  top bar (it fades while a day is open); the numbers with the key's rings (a tap lights those days); a window of months:
  this one in the middle, its neighbours faded above and below with "· N days · score N" (a tap on one turns to it), a drag
  turns past a quarter or a flick; the month rail down the right edge; the rings (`JourneyDayRing`). A ring's tap picks the
  day: its top (`JourneyDayTop`, a line under it) and its bottom (`JourneyDayExtrasRow`, a line over it); a tap on the top
  opens the day, its ring flying from its cell in the calendar. Day size 1 / 0.9 / 0.8 / 0.7 worked out from the room (`fitScale`); a turn redraws only the
  calendars whose part changed (Equatable). Pinch in → the year.
- The year (`JourneyYearView`, JourneyYear.swift): every year from the first, opening on this one; twelve small months
  (`JourneyYearMonth`, Equatable) each with its name, "N days · score N" (the month's average score) or "Away", and its days
  as one picture (`JourneyYearSquares`, a Canvas: tile colors, unmarked hairline, future faint, today outlined; the picked
  ring drawn over it); a square's tap picks it (its line at the bottom, → the day); a name opens its month; ‹ and the edge
  swipe go back to the month it came from (`JourneyFlightGeometry.yearBack`), not the card.
- Prayer scores (`PrayerScoresPage`, PrayerScores.swift): All time · 30 days · 7 days under the header (`PrayerScores.build(span:)`);
  the ring = the score when prayed; rows "97 · 98% prayed" + their dots (`PrayerScoresChart`: 14 slots across the window +
  a Qaza block). A row's (or a fifth's) tap: its symbol, name and line rise over the switch into the header (the "97 · "
  folds away), the rest after it lands; ‹ in the bar or a left-edge swipe sinks it back; another fifth switches straight to
  that prayer. A prayer's page: "Lately, usually…" + its trend, the big chart — tap or hold-drag a slot → "N prayers (P%) ·
  A–B min after it starts · <grade>" (Qaza: "made up as Qaza") in those lines' place; grade chips, insight, To make up,
  photos, Where you pray it. Thin data: "Not enough yet" (kept steady through the rise).
- `JourneyLog.build`: every row once, one per prayer per day (completed wins); a mark = done / missed / to come / excused /
  none; **active day** = ≥ 1 mark, rates and dues only over active days; days before the first mark don't exist; Excused
  badges and keys only once `Excused.ranges` isn't empty.
- Off the main thread: `JourneyLog.load` and `JourneyMakeUpPage.entries` read on a detached task with their own
  `ModelContext` and return values; Journey reads the log once per open and builds Prayer scores' row from it (one `now`,
  one set of excused ranges); the last results are kept (`JourneyLog.last`, `PrayerScores.lastBySpan`) so pages never open
  blank; a newer load drops an older one (`loadToken`); a page under another reloads on its return (`dirty`).
- Transitions (JourneyTransitions.swift, the host `journeyMonthHost`): card ↔ month (tiles fly into rings, the month name
  becomes the title), month ↔ year (days fly to their squares), a ring → its day page (from a month cell or the card's top
  ring; ‹ / edge swipe fly back). `JourneyFrameLog` (journey-transitions.log) only in DEBUG or with -journeyFrameLog or -demoJourneyFlightRun.
- Perf log (`JourneyPerf`, JourneyPerf.swift; DEBUG, or Release with -journeyPerf): each move opens a window — frames, late,
  hitch, worst gap, main busy, body counts, timed loads — in Library/Caches/journey-perf.log. Phone runs:
  `PERF_ARGS="-journeyPerf" zsh scripts/perf-paging.sh <label> testJourneyPerfPass` (a scripted pass) or `testJourneyTurnRun`
  (month turns, no screen reads; `-demoJourneyTurnRun N`). Rules it taught: no hidden sizing copies of a page, rows / months
  as Equatable views keyed on `JourneyLog.version`, many small shapes → one Canvas.
- The day page (`JourneyDayPage`, on the Salah tab's day page pieces — the day page merge, owner 2026-10-15, DayPage.swift;
  the full behaviour in salah.md "The day page merge"): the date centred on top ("Thursday, October 15" / "Today · Jumada I 4"),
  `DayRing` + `DayCentre` on a raised 222 pt disc, the picked prayer's note and place under it (`DayPickLines`), the list card
  (dot · name · time prayed with the grade under it; a tap picks, a hold opens the prayer sheet) between two plain chevrons
  (owner: no soft-ring chevrons), the pill under it ("Your day" / "Prayers", placeholders) fades the card to the day's rows
  and back (`DayFadeCard`: out, then in, on one card surface — owner 2026-10-16, it flipped before; `DayBackCard`: Notes ·
  Photos · On the map · Zikr); the side shown belongs to the page, so the next day comes in on it; a drag sideways moves a day (the left edge stays the system's back);
  days change at once, no fade. A day opens only once over or all five marked (`JourneyPage.open`, `canGoForward`) — never
  live rows. The back's Photos row → that day's pile (`MemoriesPage(openPile:leaveWithPile: true)`, pushed without a slide),
  On the map → `JourneyDayMapSheet`, Zikr → `ZikrDaySessionsPage`; a missed prayer picked → "N to make up ›" → To make up.
  A whole excused day: `ExcusedDayCard("Excused that day")`.
- The prayer sheet (`JourneyPrayerSheet`, any day, marked or not): ~half height (`resting` 480; `withButtons` 548 once edited
  or unmarked; large while the wheel or the map is open); top right only the trash (unmark: Sami's `UnmarkPrompt`, the
  system alert if another overlay is up); once the time, place or note differs, the Salah editor's `SaveCancelButtons` come
  in at the bottom (owner); a swipe down is held while edited; the date line says "not saved"; no sage anywhere on it
  (owner) — the Mark pill is Save's green edge. Score ring + `PrayerWindowBar` (tap / drag sets the time) — no
  sentence (owner: it got old); "Prayed at ⌄" → a date + time wheel inline (start…now) with "Prayed it on <its day>? ›" /
  "Made up today instead ›"; the place as a map card with its name on it (`JourneyPlaceMap`: grows in place, movable, pin
  kept, "Move the pin" → `PrayerLocationPicker`; no spot → "Add where you prayed") and the photo as itself (`PrayerPhotoCard`,
  the viewer in place; a dashed camera only while marked and on) — never the same box (owner); note (an alert, a draft).
  Unmarked: the "Mark <prayer>" pill. **An unmarked past prayer defaults to
  made up now = Qaza, wheel closed, the time grey** (owner: another day / time is there, never the main choice). Marks go
  through `PrayerViewModel.markFromJourney` (the prayer on now, marked now → the list's own path; else scored at the
  picked time, no spot, `mosqueName = ""`, streaks / day score / DayHistory / widgets / Live Activities) and
  `unmarkFromJourney`; edits through `editPrayerTime` / `movePrayer` (recorded time / spot kept). `.journeyChanged` reloads
  the pages.
- To make up (`JourneyMakeUpPage`): unmarked ended prayers on active days only, never excused; Made up = Qaza now. From
  Prayer scores (`startOnly:`) it opens on All months with that prayer's chip on (`allThisVisit`; the switch clears it). Top: the
  count, "<month> | All months" (`journey.makeUpAll`), then each prayer's count (a tap shows only it — owner: under the
  switch); months newest first as pinned headings with "N left · N made up"; the month scrubber on the right edge is the
  Zikr wheel's dots (owner: not the soft look; > 3 months; the top month's dot bigger, a cleared month sage, a pill naming
  the month while dragging, a tick each). Made up keeps the row in place as "✓ Made up · Undo" for 3 s (`settling`; Undo = unmark; decision
  makeup-made-feedback A), then it leaves the list (made up = marked on a later prayer day); a month with nothing left drops
  out; "✓ N made up · Show" under the total (`journey.showMadeUp`, Reminders' Show Completed — owner: not folded under each
  month) puts them back in their months, greyed, by date; an empty side shows "All caught up" (a check drawn in + a
  success buzz). A row opens its sheet (decision makeup-row-tap: kept).
- Milestones (`JourneyMilestone.earned`, YourJourney.swift; earned once, dated, newest first, a hollow dot each): Day one,
  first Jumu'ah / first prayer at a masjid, 7…365 days all in time in a row, each streak that beat the best ("Your best
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

