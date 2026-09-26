# shukr — working notes

iOS SwiftUI app (iOS 18.0+, SwiftData, WidgetKit extension, adhan-swift). Prayer times +
tracker, qibla, tasbeeh/zikr counter, daily zikr tasks, duas, daily ayah. No CI, no tests
beyond Xcode templates. Build/run happens in Xcode on the owner's machine; this repo has no
scripts to run. A local agent can build with
`xcodebuild -project shukr.xcodeproj -scheme shukr -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.

Layout: `shukr/` app target (most UI in `Utils.swift`, `CursorSwift/`, `tasbeehView.swift`),
`shukr/Models/AllModels.swift` (SwiftData models + `SharedStateClass`), `shukrWidget/`
(PrayersWidget + AppIntents shared with the app via `SharedTargetForIntents.swift`).
Widget and app share `UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")`.

## Feature list (for the App Store listing)

What shukr does, meatiest first — keep this current; it's the source for the description,
keywords, "What's New" and screenshot captions.

**Prayer**
- Accurate daily prayer times for where you are (GPS, or a city you pick), with the
  calculation method and madhab (Hanafi / Shafi'i) of your choice.
- The main circle: the current or next prayer with a live ring of how much of its window is
  left, coloured by the score you'd get right now; tap to flip between "ends at" and time left.
- Prayer tracker: mark each prayer as prayed; it's scored by *when* — Early (first 30 min) ·
  On time · Late · Qaza (after the window) · Missed — and each day gets a score.
- A satisfying completion moment (the ring sweeps closed, a haptic, "✓ Asr · On time · 88"),
  done prayers fold away, all five come back with a "perfect day" flourish.
- Edit when you prayed with a custom time wheel that won't let you pick an impossible time.
- The prayer day runs Fajr to Fajr, so a late Isha after midnight still counts for its day.
- Streaks: the day streak, "in-time days" (no Qaza), best streaks, with celebrations.
- Notifications at each prayer with "I already prayed" / "nudge me in 5 / 10 min" actions,
  per-prayer on / off / nudge settings, and an optional daily Fajr alarm.
- Home-screen widget: the current prayer's ring and time, mark it prayed right from the
  widget (the check fills once the current prayer is prayed and the circle moves on to the next),
  and corner buttons for today's times, the qibla and tasbeeh.

**More widgets**
- Zikr: today's zikr tasks like the Reminders widget — an overall progress ring, how many are
  left, and each task with a circle that fills as you go.
- Name of the Day: one of the 99 Names each day, in Arabic inside the app's circle, with its
  meaning — in the mint / forest look of the share card.
- Daily Ayah: today's verse on your home screen, once you've revealed it in the app (it never
  spoils the reveal).

**Mosque finder**
- One tap on the map finds the mosques around you (Apple Maps search for mosque / masjid /
  Islamic center, filtered to real places of prayer — no halal shops or restaurants).
- Tap a mosque: how far it is by car, a street-level Look Around view of the entrance,
  Directions in Apple Maps or Google Maps, Call, its website in-app, and Apple Maps' place card (photos where Apple has them).
- Pan anywhere and "Search this area".
- A list of every mosque found, nearest first with the distance; tap one to fly straight to it.

**Qibla & map**
- Qibla direction on the main circle; a full map with the great-circle line to the Kaaba from
  where you stand, a compass ring on your dot that tells you which way to turn, and a glow
  when you're facing Mecca.
- Qibla-up map: it turns so the line to the Kaaba points straight up your screen — hold the
  phone out, turn until the streets match, and the top of your phone is the qibla. Worked out
  from where you are, so it's right even when the phone's compass isn't. Rotate freely; one tap
  puts the qibla back up.
- A short illustrated guide the first time you open each map layer (qibla, prayer spots,
  mosques), and a ? to bring it back.
- Explore: pick prayer spots or mosques and their controls sit right on the map — date range and
  one-tap prayer filters, drive / walk times, a list — with ✕ back to the qibla.
- Every prayer you've marked, pinned where you prayed it, coloured by score; tap a pin or a
  cluster for the prayers there; filter by prayer and date range.

**Insights**
- "Am I getting better?" — each prayer ranked by its recent score with an 8-week trend.
- "How am I scoring?" — average score ring with the grade makeup, per-prayer rings, week /
  month / all time.
- "How consistent am I?" — streaks and a 14-day prayer grid you can scrub.

**Zikr (tasbeeh)**
- A tap-anywhere tasbeeh counter with haptics (light / medium / strong), bead animation,
  sleep mode that dims the screen, and auto-stop at your goal.
- Freestyle, count goals (e.g. 100) or time goals (e.g. 10 min), with a live finish estimate.
- Daily zikr tasks shown as a wheel of circles, each ringed with today's progress; continue
  where you left off or start over; arrange them home-screen style.
- Mantras: your own library of dhikr with the full Arabic / transliteration and notes (who
  taught you, why), shown right on the pause screen; lifetime count, time and pace per mantra.
- Count in sets: switch on a per-mantra "+N" and every tap counts N — for when you recite a set
  on your fingers and tap once.
- Post-salah tasbih (Tasbih Fatimah): 33 · 33 · 34 in one flowing session, the phrase
  changing as you go, with the hadith on why it matters.
- Zikr history: all-time total, a 14-day chart you can scrub, every session with its pace;
  swipe to delete or jump to the mantra.

**Quran & more**
- Daily Ayah: a verse a day (Arabic in the Uthmani script + translation) to reveal, with a
  beautiful 9:16 share card for Stories.
- 99 Names of Allah: each name with its meaning and explanation, and flashcards to learn
  them (with a "known" progress ring).

**Privacy & feel**
- Nothing leaves the device: no accounts, no tracking; location is used only on-device.
- Light / dark / automatic appearance; a calm, rounded, circle-based design throughout.
- A short welcome — "shukr" writes itself inside a ring that settles onto the prayer circle, with
  a soft heartbeat haptic — when the app starts fresh.

## Handoff — 2026-09-25 evening (read this first)

Branch `claude/tasbeeh-zikr-updates`. Everything since eac68fc is committed (798823a + the
follow-up tweak commit). The owner iterated from screenshots and skipped several of the agent's
replies, so the questions below are still open. "Sim" = checked by the agent in the iOS 26
simulator; "phone" = installed on the owner's 13 Pro Max (iOS 27), and they reacted to it.

**Next agent — the two bigger items the owner handed over:**
1. **History ⇄ Mantras paging: rethink it.** The owner isn't a fan: "users are swiping delete by
   accident or paging when deleting". `ZikrLibraryView` (MantrasView.swift) is a custom horizontal
   pager with `NoPageZones` so rows keep their swipe actions. Row swipes and page swipes share an
   axis and still collide. Likely direction: drop horizontal paging for a segmented control / two
   tabs, or push Mantras from History. Ask the owner before building.
2. **Map pin → pin sheet flow: redesign it.** The mosque finder itself works well (owner). But
   tapping pin after pin closes and reopens the sheet each time (`LocationViewModel.present`:
   dismiss, then present again 0.4 s later), the detents vary (compact / medium / large), and it
   feels slow. The owner calls it "a flow/paging redesign". Idea: one persistent sheet whose content
   swaps in place, with a fixed detent that the user controls (like Apple Maps' place card).
   Covers both prayer-spot pins and mosque pins (`MosqueSheet`).
3. ~~**Lag before the completion page**~~ (owner: clean now). Notes kept: after Finish on the pause screen, and when a task hits its
   goal (auto stop). Tried 2026-09-25 (untested on the phone): the shared-state writes after the save
   (`selectedTask = nil`, which re-renders the whole home screen under the cover) now wait until
   `completeStopTimer` (0.5 s), and the results fade is 0.25 s ease-out instead of 0.5 s ease-in-out.
   If it still lags, measure first: time from tap to results-visible with signposts. The next
   suspect is `context.insert(session)` in `saveSession`, which refreshes every `@Query` on
   sessions behind the cover (DailyTasksView ×2, the TopBar stats in Utils.swift ~3337). Also
   check `ResultsView.taskToday`, which walks `task.sessions`.

**Owner's answers (2026-09-25):**
- **Zikr wheel:** "gentle arc / half tilt" is the default (`ZikrWheelStyle.gentle`). The others
  stay in dev settings.
- **Post-salah prompt:** the bottom pill is final and the default. Keep the circle and top-pill
  variants in dev settings. Both pills now share `FlickAway` (PrayerCompletionFX.swift): a
  resisted pull of ~70 pt in any direction that fades as it goes; past 60 pt (or on a flick) it
  finishes fading in place and is removed without animation. No edge wall. The top pill
  (`FloatingChainZikrButton`) was rebuilt on it and is built only while shown.
- **Confirmed good:** the mosque finder, the "fine" ring, the "N done" footer, the time editor's
  colour-bar scrub (lag fixed), the two-tap Finish, and the pause fade.
- **Two-tap Finish:** the owner asked for a smoother change between states. The two labels are
  now stacked and crossfade with a soft blur, the green fill and edge ease in over 0.35 s, and a
  stale 3 s disarm can't cancel a newer arm (`finishArmToken`). Sim ✓.
- **Light / dark / auto toast:** was too close to the bottom and easy to miss. Now it drops in
  under the Settings header, below the toggle. It then drifted off-centre for a moment on each
  switch (one capsule changing width while its text swapped). Now it's one capsule per mode,
  crossfaded. Untested on the phone.
- **Completion lag:** the owner says it's "clean now" after the deferral and the faster fade.
- **Count in sets is a toggle** (owner, 2026-09-25): the "+N" button at the top of a session
  switches it on. Then every tap / drag is worth N and − takes N off (`tasbeehView.countingInSets`
  / `tapWorth`). The button shows it's on with green text on a green tint with a green edge. One
  buzz per tap. The every-hundred buzz checks for a crossing, because a set can jump over the
  exact multiple. It's off at the start of each session, and turns off if the mantra's step drops
  to ≤ 1. Sim ✓ (12 → 18 in two taps).
- **Fajr rollover and the 15 Pro migration:** "haven't checked but I guess it's fine...?" Still
  unverified. Between midnight and Fajr, yesterday's prayers should still be up and zikr should
  count for yesterday. On the 15 Pro's first open, look for `✅ schema V2 data pass` and no ❌.

**Late 2026-09-25:**
- **Widget:** a redesigned "shukr" widget (`ShukrDayWidget`) was built and **dropped**. The owner
  said it "kinda sucks … not performant", and the code is gone. The kept "Prayers" widget got small
  fixes.
  - **"Fajr at <now>" bug:** since 46176a5 (2026-09-23) the circle skipped completed prayers. Once
    Isha was marked nothing was left, and it fell through to the original placeholder
    `("Fajr", Date(), …)`.
  - **Done state — reverted:** keeping a prayed prayer on the circle was tried and rejected. The
    owner wants the circle to move on to the next prayer, as before. The top-left check fills
    instead, when the prayer whose window is open (`prayerInWindow`, never Sunrise) has been prayed.
  - **Corner buttons:** they replace the boxed bottom row (owner liked the dropped widget's corners).
    Today's times top left, mark prayed top right (swapped by the owner), qibla bottom left, tasbeeh bottom right. Same
    intents (`CornerButton`), same single-entry timeline.
  - **After Isha:** the circle shows tomorrow's real Fajr (`entry.nextFajr`).
  - **Sunrise** can't be marked any more.
  - `NSWidgetWantsLocation` was removed from the widget's Info.plist. The widget reads the app
    group's location, and the key made iOS ask "Allow widgets to use your location?".
  - `markPrayerComplete` and the app reload all timelines.
  - Sim ✓ (marked Isha shows done). Not seen on the phone yet.
- **Prayer list dot:** the owner picked **"Score colour, faded"** (the default now).
  `PrayerDotStyle` / `PrayerStatusDot` in PrayerCompletionFX.swift. The other styles are still in
  Settings → My Dev Stuff → Prayer list dot; delete them when convenient.
- **Welcome animation** (`CursorSwift/WelcomeAnimation.swift`, `.welcomeOnLaunch()` on the root
  NavigationStack in shukrApp):
  - "shukr" (44 pt thin rounded) fades up letter by letter out of a blur, and a hairline sage ring
    draws round it.
  - The ring is the main circle's 200 pt, in its place, so it lands on the real circle.
  - A sage light sweeps over the word, with two soft taps like a heartbeat.
  - It holds about 1.1 s (owner: "a little longer"), then fades (0.7 s, no scale). About 2.5 s in
    all.
  - Plays on a cold launch, and after more than 5 min in the background
    (`WelcomeGate.awayThreshold`).
  - Reduce Motion: just the fade. DEBUG `-demo…` args skip it (`-demoWelcome` forces it).

- **Qibla map: rotation + first-time guide** (owner: people find the map compass confusing, since
  its arrows don't follow the phone like the Salah page's circle; they want to turn the map
  instead of the phone):
  - **Rotation:** the map rotates with two fingers now (`isRotateEnabled = true`; it was
    north-up). The ring on the dot draws in screen space, so its triangle, chevron and arc subtract
    `MapAnchor.mapHeading`. The coordinator writes the camera heading on every frame, and only the
    ring and the north button read it. The green line is an overlay and turns with the map for
    free.
  - **North button:** `MapNorthButton` (red needle, in the map-style / locate capsule) shows only
    while the map is turned; tap → north-up (`LocationViewModel.resetMapHeading`). MapKit's own
    compass is off.
  - **Guide:** `QiblaMapGuide` (CursorSwift/QiblaMapGuide.swift). Three pages, each with a small
    moving picture:
    1. the green line is computed, so it's right even when the compass isn't;
    2. turn the map until a street or wall runs like the real one, then face along the line;
    3. the ring is only the compass — the blue arrow meets the triangle; trust the line when they
       disagree.
  - The guide opens once, 0.7 s after the map first appears (`qiblaMapGuideSeen`), and from a new
    ? button under locate. DEBUG `-demo…` args skip it; `-demoQiblaGuide` shows it.
  - Sim ✓: guide pages; a two-finger rotate turned the map, the triangle stayed on the line, and the
    north button appeared.
  - The "Turn left / right" pill is still compass-only.
  - Rotation is for lining up only: switching to prayer spots or mosques (`setMode`) turns the
    map north-up and locks it; back to the qibla unlocks it.
  - **Qibla-up** (owner, 2026-09-26: so the phone and the arrow never point different ways):
    - The map opens turned so the green line points straight up the screen
      (`LocationViewModel.pointQiblaUp`: camera heading = bearing to Mecca), and swings round once
      it's on screen. Hold the phone in front of you, turn until the streets match, and the top of
      the phone is the qibla.
    - Free rotation stays on. Coming back from prayer spots / mosques re-centres on the user and
      returns to qibla-up in one camera move.
    - The home button (`MapNorthButton`) shows only when the map is turned away from home. In qibla
      mode that's a green arrow pointing where the qibla is on screen, tap → qibla-up; otherwise a
      red north needle.
    - Guide page 2 is now "The top of your phone is the qibla".
  - Qibla zoom is `Coordinator.qiblaSpan` (~220 m across, 4× closer than `closeSpan`; owner) on
    open, on coming back from a layer and for locate in qibla mode. The green line is redrawn once
    the dot moves ~2 m (it was 25 m, which left it visibly starting off the dot at this zoom).
  - **Explore only picks (2026-09-26, owner: "let's just try it — if we don't like it we revert").**
    - **Chooser:** 🔍 opens `MapExploreSheet`, now just a short chooser: Qibla · My prayer spots ·
      Mosques. Halal food is hidden until it exists. A pick closes the sheet.
    - **Layer bar:** the layer's controls sit on the map in a glass bar at the bottom.
      - `PrayerLayerBar`: a range `Menu` (All time / This week / 30 days / This year / 12 months /
        Custom… → `CustomRangeSheet`: just From / To, applied live, Done; opens on the last 30
        days when the range was a preset. It used to reopen the old `FilterView`, which repeated the
        bar — owner). Then the five prayer icons as chips. With all shown
        none is lit; tap one = only it; tap more to add; tap the last lit one = all again. Then ✕.
      - `MosqueLayerBar`: List | 🚗 🚶 (drive / walk) | ✕. List (or a tap on the top pill) opens
        `MosqueListSheet` (MosqueFinder.swift): every mosque found, nearest to you first, with
        address and distance. Tap one → `focusMosque` flies the map there (close enough that it
        isn't in a cluster), selects its pin and opens its sheet. `openMosqueList` closes an open
        mosque sheet first. The pill says "N mosques in this area" when the last search wasn't
        around you.
      - Search fix: `MosqueSearch.find` sets `regionPriority = .required` and searches at least
        ~5 km across. With the region only a hint, "Search this area" somewhere else returned the
        same places near you again (owner: "28 in my area" with no pins in view). Not re-tried
        after a real pan.
      - ✕ = back to the qibla (qibla-up, centred).
    - **Layer button:** the round button beside the bar wears the layer's icon (green) and reopens
      the chooser.
    - **Before:** layer settings lived inside Explore, and prayer filters were Explore → filter
      line → filter sheet. The top pill no longer opens filters.
    - **Rotation lock:** `setMode` turns north first and locks rotation 0.6 s later. With
      `isRotateEnabled = false` set first, MapKit ignored the heading change and pins came up
      qibla-rotated.
    - Sim ✓: chooser → prayer spots (north-up, bar), Fajr chip → "2 prayers in view · every
      Fajr", ✕ → qibla-up, Custom… → the date sheet. The mosque bar is not tried in the sim.
  - Guide animations: every `PhaseAnimator` uses real holds, as the phase's `.delay`, instead of
    repeated phases. A phase with no change finishes instantly, so the loops ran nonstop ("kinda
    spazzing" — owner).
  - **The ? is per layer** (`MapGuide(topic:)`, QiblaMapGuide.swift; `MapGuideTopic` qibla /
    prayers / mosques). Same sheet and style, three pages each with small animations:
    - **Prayer spots:** pins dropping in score colours; a cluster opening its sheet; filter chips
      rewriting the pill.
    - **Mosques:** pins popping round the dot; the mosque card flipping drive ⇄ walk; the map
      panning to "Search this area".
    - Each layer's guide also opens once by itself the first time it's shown (after the Explore
      sheet closes). Seen keys: `qiblaMapGuideSeen`, `mapGuideSeen.prayers`,
      `mapGuideSeen.mosques` (standard defaults), marked only when the guide actually showed.
  - Sim ✓: qibla-up on open, the qibla guide, mosques → first-time mosque guide (north-up,
    locked), back to qibla → qibla-up centred. The prayer-spots guide is not seen in the sim yet.

**2026-09-26 — three more widgets** (`shukrWidget/MoreWidgets.swift`, added to the widget target
in the pbxproj by hand — `shukrWidget/` is not a synchronized group; kinds in
`Models/WidgetPayloads.swift` → `WidgetKinds`). Owner: "a few simple ones". Each has one timeline
entry and a far-off refresh; the app reloads them when something changes (the owner found a
many-entry widget "not performant"):
- **Zikr** (small / medium), laid out like the iOS Reminders widget (owner):
  - **Layout:** today's overall ring top left (each task's share of its goal, averaged; beads
    inside, sage ✓ when all done), a big "N left today" count, "Zikr" in brand green, then the
    tasks as rows. Each row has a circle that fills with its progress (filled sage ✓ when done),
    the name, and "5/100" (medium only; small shows names only, max 3 rows, "+N more").
  - **Data:** reads the shared
  store (`TaskModel.progress(in:)` over sessions since `PrayerDay.sessionDayStart()`). Refreshes
  at the next Fajr, plus the app reloads it after every saved session (tasbeehView `stopTimer`
  saves the context first) and on going to the background. Tap → Zikr page (`OpenTasbeehIntent`).
- **Name and Ayah look:** both wear the Daily Ayah share card's mint look (forest in dark mode,
  `BrandBackground`), with tracked lowercase captions (`BrandCaption`), deep-green ink and a
  leaf-green accent. The name sits in a thin double ring (the app's circle). The ayah is laid out
  like the share card, and its waiting state shows blurred lines under "today's ayah is waiting ·
  tap to reveal".
- **Name of the Day** (small / medium): `NamesOfAllah.nameOfTheDay()` — Allah, then the 99 in
  order, one a day from 2026-01-01. Arabic in the Uthmani font; medium adds the explanation. Tap →
  99 Names (`OpenNamesIntent`, flag `widgetNames`). `NamesOfAllahData.swift` moved to `Models/`
  so the widget has it.
- **Daily Ayah** (medium / large): shows today's verse **only after it's been revealed** in the
  app. Until then: "Today's ayah is waiting · tap to reveal it". The app writes
  `DailyAyahWidgetPayload` (arabic, english, "Surah · s:a") to the app group on reveal / page open
  / translation change, and only when it changed. Tap → Daily Ayah (`OpenDailyAyahIntent`, flag
  `widgetDailyAyah`, handled next to widgetCompass in PrayerTimesAndTracker).
- Sim ✓: all three render in the gallery with real data (Zikr tasks, today's name). Taps into the
  app and the reveal → widget update are not tested yet.

**Earlier builds (details in the sections below):**
1. Mantra page (`MantraEditorView`), phone ✓:
   - pause-card look, read-only until ✎, nav bar never changes height;
   - Save is green text only when there's a change;
   - count in sets is live (skips 1);
   - lifetime bento;
   - tasks as centred circles;
   - sessions by day with swipe-to-delete.
2. History ⇄ Mantras custom pager (see item 1 above; to be rethought).
3. Zikr wheel: five `ZikrWheelStyle`s; gentle is the default.
4. Map, phone ✓:
   - Liquid Glass controls, ⌄ to close;
   - 🔍 Explore bottom-right, opening a layers sheet (My prayer spots · Mosques · Halal food "soon");
   - the top pill shows the count and the active filter.
5. Mosque finder (`MosqueFinder.swift`):
   - drive/walk time, Look Around;
   - Directions menu (Apple / Google / Waze / Share location);
   - Call, website, Apple's place card.
   Owner: works well. Untested around Cary: false positives in the filter, and whether place-card
   photos show.
6. Post-salah pill (above).
7. Tasbih Fatimah: its own pause card, locked results, four rotating reminders. **The reminder
   wording paraphrases hadith and needs a knowledgeable review before release.**
8. Time editor: Save stays gray until the time changes; scrub lag fixed.
9. Ring playground plus the "fine" ring style (owner ✓). The agent suggested lowering fine's turn
   speed from 23°/s to 12–15; the owner hasn't answered.
10. Prayer list "N done" footer (owner ✓).

**Questions asked and never answered (don't assume — ask):**
- Map: how to turn a layer off. The agent recommended a ✕ on the top pill (alternatives: 🔍 → ✕,
  or 🔍 clears).
- Mosque icon style (dev picker).
- Masjid-aware prayers: should jama'ah at any masjid score like Jumu'ah, or only Jumu'ah itself?
- Post-salah "points": see that section (+N vs 3/5, its own streak, whether the 33/33/34 must be
  complete).
- Reminders: keep rotating all four, or pick one or two.

**Release / TestFlight:** **2.0 (6) was uploaded 2026-09-25** from 28e418f (archive:
`build/shukr-2.0-6.xcarchive`). 2.0 (5) was never uploaded. Next upload: bump
`CURRENT_PROJECT_VERSION` (8 occurrences) to 7. Upload with
`env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive … -exportOptionsPlist
build/ExportOptions.plist`. Homebrew's rsync breaks the export, so keep PATH as shown. A
"missing Xcode-Token" line in the log was harmless this time: the upload still succeeded. The dev
toggles (wheel / mosque icon / post-salah style / ring playground) live in the `#if DEBUG`
"My Dev Stuff" section, so they won't ship.

## Start here: outstanding work, in priority order

Branch: `claude/tasbeeh-zikr-updates` (from `claude/map-rework`; neither merged to `main`). Everything below
the first block is unbuilt by the agent that wrote it; the owner builds in Xcode / a local
agent builds with xcodebuild. Nothing here has CI.

1. **Verify the schema V2 migration on the owner's phone.** Back up first:
   `xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer
   --domain-identifier group.betternorms.shukr.shukrWidget --source shukr.store --destination …`
   (plus `-wal` / `-shm`). First launch must print `✅ schema V1→V2: mantras=N … tasks linked=…
   sessions linked=…` followed by `✅ legacy import: tasks=0 …` (everything already merged) —
   then the Zikr cards still show their names, hamburger → Mantras lists the built-ins plus the
   13 custom ones, history titles are intact. A `❌`/`Fatal error: Could not create
   ModelContainer` means the migration failed: restore the backup, do not relaunch repeatedly.
   (Legacy import itself is verified on the phone, 2026-09-23: `tasks=10 sessions=492
   mantras=13 duas=2 prayers=2096 (merged 1) scores=278`.)
2. **Verify horizontal paging on the phone.** Owner reported "dragging left/right does nothing"
   on an earlier commit while the simulator paged fine. b4071db moved the vertical gesture onto
   the ScrollView itself, which removes every known way a page could block paging. If it still
   fails on device, find out whether it fails everywhere or only when the finger starts on the
   circle / prayer list, and whether the build on the phone is actually current.
3. **Verify the rest of b4071db on device:** salah sheet stays open across paging; hamburger
   `Menu` is instant; Settings header (back / title / light-dark-auto) works.
4. **Widget, still unverified:** does the nudge notification for a widget-completed prayer
   still fire (can an extension cancel the app's pending notifications)? Widget tap before a
   prayer starts (should no-op). Sim-verified 2026-09-23: widget added before the app is ever
   opened creates no store and its checkmark is inert; widget on a V1 store waits for the app
   to migrate. Still unverified on a real device.
5. **General sluggishness lever:** migrate `SharedStateClass` from `ObservableObject` to
   `@Observable` (see Navigation section). Do it with a compiler in the loop.
6. **Compass freezes while moving** (owner, 2026-09-24, on device). The qibla arrow on the
   circle stops updating while walking/driving and works again when standing still; the iOS
   Compass app is fine at the same time, so it's ours. Not investigated yet. Leads, all
   unverified: every GPS fix while moving goes through `PrayerViewModel.handleLocationChange`
   (reverse geocode + `fetchPrayerTimes` + SwiftData save + notification rescheduling every
   500 m / 30 s) and `storeLastCoordinate` writes the app group every ~50 m, which invalidates
   every `@AppStorage` on it (see Re-render hygiene); `didUpdateHeading`'s 0.5° guard compares
   against `compass.heading`; and whether `updateQibla()` from location fixes races the heading
   path. Reproduce on device by walking with the app open, and check `Self._printChanges()` /
   heading callback frequency.
7. **Paging lag fix — committed, still to re-measure on device (owner wants to do it later).**
   2026-09-24, measured with `Self._printChanges()` + a main-thread watchdog on the owner's
   phone (Release): 90 s of fast paging = 944 SettingsView renders, 395 PrayerTimesView, only
   two >150 ms stalls — death by re-render. Cause: `shukrApp` held `sharedState` as
   `@StateObject`, so every page-turn publish re-ran the root body and rebuilt the whole tree
   (home rendered twice per change, Settings up to 3×). Fix: root holds it as `@State`;
   Settings takes `onBack` instead of observing `sharedState` and is wrapped in an always-equal
   `SettingsPage` (`.equatable()`). To re-measure: add `let _ = Self._printChanges()` to the
   bodies of PrayerTimesView / SalahPageContent / PagerChromeView / SettingsView /
   MainCircleView / DailyTasksView plus a main-thread ping watchdog, Release build to the phone,
   `devicectl device process launch --console` for 90 s (phone unlocked!) while the owner
   pages, compare with the numbers above, then remove it again. Remaining per-page-turn renders
   (MainCircleView, DailyTasksView, SalahPageContent via `_sharedState`) are item 5.
   Also seen: three `.ips` reports on 2026-09-24 (builds 1.0 (1) and 2.0 (4)), all a UIKit
   `NSAssertionHandler` abort in `_updateSnapshotAndStateRestorationWithAction` while going to
   the background. Not investigated.
8. **Insights page needs a rethink (owner, 2026-09-25: "still not happy with it, need to give it
   more thought").** `CursorSwift/InsightsView.swift`, hamburger → Insights. Second version is a
   minimal one-screen layout: range picker, a main-circle-style day-score hero (tap → grade
   split), one streak line, five prayer rings (tap → avg / % prayed), 12-week heatmap. First
   version (cards, area chart, stacked bar) was "information overload". Owner didn't know what
   "on time" meant there — it's now "in-time days" (see Streaks). Ask the owner what they want
   to learn from it before building a third version.
9. Then the App Store blockers below.

## Masjid-aware prayers (owner idea, 2026-09-25 — not built)

Trigger: the owner prayed Jumu'ah at his masjid, marked it, and it scored **Late**. Jumu'ah (and
jama'ah generally) follows the masjid's iqamah, not the window's start, so the timing score
punishes exactly the behaviour the app should reward. Wanted:

1. **Know a prayer was at a masjid.** When a prayer is marked (app, widget, notification action),
   check the spot it's recorded at (`latPrayedAt` / `longPrayedAt`, already stored) against
   mosques nearby — `MosqueSearch.find` around that point, a match within ~75 m (GPS indoors is
   loose; tune on device). Store it on the row: e.g. `PrayerModel.mosqueName: String?` (lightweight
   schema change → bump to 2.2.0; `makeContainer` backs the store up first). Past rows could be
   back-filled from their coordinates once.
2. **Score it fairly.** Jumu'ah = Friday's Dhuhr **marked at a masjid** — only then (owner:
   a Friday Dhuhr prayed anywhere else is a normal Dhuhr, scored by the clock as always). A
   Jumu'ah scores 100 (Early) regardless of the clock, and only that row is labelled "Jumu'ah"
   (list, circle, map sheet, widget) — never every Friday Dhuhr. Open question for the owner:
   should *any* prayer prayed at a masjid (jama'ah) also get full marks, or only Jumu'ah? Goes
   through `PrayerScoring` so the app, widget and notification action agree.
3. **Dua on entering the masjid.** A notification on arrival: "Allahumma-ftah li abwaba
   rahmatik" (the dua for entering; leaving: "Allahumma inni as'aluka min fadlik"). Needs region
   monitoring — `CLMonitor` (iOS 17+) / `CLCircularRegion` geofences (≤ 20 per app) around the
   user's own masajid (the ones they've prayed at most, from (1)), which needs **Always** location
   permission: its own opt-in with a clear reason string, and App Review scrutiny (5.1.1) — never
   make it a requirement. Consider limiting to the user's top few masajid.
4. **Map.** Prayer-spot pins prayed at a masjid get their own look (and the masjid's name in
   `PrayerSpotSheet`); a filter chip "at a masjid"; Insights could count jama'ah prayers.

Design all four together before building — the detection in (1) feeds the rest.

## Post-salah zikr "points" (owner is curious — discuss before building, 2026-09-25)

Idea: doing Tasbih Fatimah after a prayer earns something; all five in a day earns more.
Recommendation given (not yet agreed): **don't add it to the prayer score** — that score means "how
well you prayed on time"; grades, streaks, in-time days, perfect day and every Insights trend read
it, a bonus would let a Late prayer read On time, and past days can't earn it (no record of which
session followed which prayer), so trends would jump. Instead a **separate layer**: a bead mark on
each prayer followed by the tasbih (list + map sheet), "post-salah zikr 3/5" beside the day score
(maybe shown as a "+3", never mixed in), a moment for 5/5, maybe its own streak, one Insights stat.
Linking a session to its prayer: store it — the post-salah pill knows the prayer
(`PagerLiveState.postSalahNudge`), so the session would save e.g. `SessionDataModel.forPrayer`
(small lightweight schema change, backup first) — rather than inferring from times. Keep it
encouraging, never punitive (skipping lowers nothing), possibly switchable off. Open questions for
the owner: "+N" vs just "3/5"; its own streak or not; must the full 33/33/34 be completed (suggested
yes).

## Share card — CHECK ON RELEASE

The Daily Ayah share button (`DailyAyahView`, a `ShareLink`) sends only the image
(`AyahShareCard`, three looks) — no caption or link (owner, 2026-09-25). The card itself says
"download on the App Store", which is only true once shukr is live: until then testers get it
through TestFlight (public link `https://testflight.apple.com/join/GW5j85jk`). When a
TestFlight build goes out or the app is released, remind the owner to check the card's wording
(and whether to add a link back).

## Immediate goal: App Store submission

Audit done 2026-09. Nothing below is fixed yet unless marked.

Hard blockers (rejection or upload failure):
- [x] Location denied → infinite `GradientAnimationLoad()`. Fixed 2026-09-24: denied shows "open settings" + "or enter your city instead" (`CityPickerSheet`, MKLocalSearch); a picked city (`manualLocation` + lastLatitude/lastLongitude in the app group, `EnvLocationManager.effectiveLocation`) drives prayer times, widget and qibla; GPS wins when authorized. Revoking location after it was once allowed (`locationWasAuthorized`) drops the city so the welcome screen asks again. The welcome screen then asks for notifications (`NotificationStatus`); a quiet "continue without reminders" link keeps it non-blocking (App Review 4.5.4 / 5.1.1 — don't make it a hard gate). Unverified on device: whether heading updates arrive while location is denied (manual-city qibla may not turn).
- [x] (2026-09-24) Widget config placeholder strings ("the title wip...") in `shukrWidget/AppIntent.swift:18-22`, visible in Edit Widget.
- [x] (2026-09-24, removed from the bundle; file left) Template Live Activity ("Hello 😀", `http://www.apple.com`) registered in `shukrWidgetBundle.swift:15`. Delete.
- [x] (2026-09-24, `#if DEBUG`) Dev UI reachable by users: "My Dev Stuff" settings section toggled by tapping the "Calculation Method" header (`SettingsView.swift`, `showDevStuff`). Wrap in `#if DEBUG`. (The "Dev's WIP" menu entries are already `#if DEBUG` in the new hamburger `Menu`; the old `sideMenu` in Utils.swift still has them but is unreachable.)
- [x] (2026-09-24, removed) Dead buttons: "Suggest Feature" (`SettingsView.swift:312`), "Cancel for X" (`:351`).
- [x] (2026-09-24, removed) "Muslim Brand Explorer" links use expired signed CDN image URLs (`SettingsView.swift:77-83`) + third-party photos/marks. Remove or bundle own assets.
- [x] (2026-09-24: both targets, UserDefaults CA92.1 + 1C8F.1, no collected data — nothing leaves the device) No `PrivacyInfo.xcprivacy` in app or widget. UserDefaults is a required-reason API (`NSPrivacyAccessedAPICategoryUserDefaults`, `CA92.1`). Declare location collection.
- [x] (2026-09-24) `TARGETED_DEVICE_FAMILY = "1,2"` but UI is phone-only and icon set lacks 76x76@2x iPad slot. Set to `"1"`.
- [x] (signing works: 2.0 (3) uploaded to TestFlight 2026-09-24) Portal: App IDs need Time Sensitive Notifications + app group `group.betternorms.shukr.shukrWidget` enabled or archive signing fails.

App Store Connect (outside repo): privacy policy URL, support URL, App Privacy label (precise
location, on-device), screenshots 6.9"/6.5", description/keywords/category/age rating,
`ITSAppUsesNonExemptEncryption = false` in Info.plist (done 2026-09-24), content-rights docs for `quran.sqlite`,
`english_hilali.sqlite` (KFGQPC copyright) and `KFGQPCUthmanTahaNaskh.ttf`.

Quality (fix before launch):
- [x] (2026-09-24) Arabic font never loads: `DailyAyah.swift:420` passes the filename to `.custom()`, and the app target's `Info.plist` has no `UIAppFonts` (only the widget's does).
- [ ] `fatalError` on `ModelContainer` failure (`shukrApp.swift:45`) — first schema migration failure hard-crashes existing users.
- [x] (2026-09-25) ~190 `print()` calls, some logging coordinates: a release-only no-op `print` in SharedTargetForIntents.swift (both targets) shadows `Swift.print`.
- [x] (2026-09-25) `NSMotionUsageDescription` and the unreferenced `PrayerTracker.swift` removed.
- [x] (2026-09-25) `shukr/PrayerTimeAndTracker.swift` deleted. Still there: `CommentedOutHistoryPageView.swift`. (Both LocationMapView.swift copies deleted 2026-09-25.)
- [x] Deployment target is 18.0 on every target now (was 17.5 app / 18.0 widget). Needed for `onScrollPhaseChange`.
- [x] Removed stale `DEVELOPMENT_ASSET_PATHS = "shukr/Preview Content"` (folder deleted in 789632f; Xcode 27 errors on it).
- [x] (2026-09-25) App icons flattened to RGB (the alpha was all-opaque).

## Navigation (PrayerTimesAndTracker.swift)

Two independent pieces of nav state on `SharedStateClass`:
- `horizontalPage: HorizontalPage` (.zikr / .main / .settings) — which pager page is showing.
- `navPosition: ViewPosition` — the **center page's vertical state only** (.main = circle,
  .bottom = salah sheet open). Paging away never changes it, so the center page comes back
  exactly as it was left. `.left / .right / .top` and `cameFromNavPosition` are legacy, unused.

Horizontal is a **native paging `ScrollView`** with three full-width pages in a plain `HStack`
(all stay mounted), each `.clipped()`. `@State scrollPage` is bound with `.scrollPosition(id:)`
and is written only from `onChange(of: horizontalPage)` (and only while the pager is idle —
`live.pagerPhase`); user swipes flow the other way from `.onScrollGeometryChange`: the page is
committed (with the haptic) **when the nearest page changes** — the midpoint crossing during a
slow drag, a few frames into the coast for a flick — never at landing, which felt like the tick
came after arrival (owner, 2026-09-25). When the scroll settles, `scrollPage` is synced to the
landed page without animation: left stale, SwiftUI re-applied the old value on the next
re-layout and coming back from the home screen snapped the pager to Salah.
`.defaultScrollAnchor(.center)` starts on Main.

**The salah sheet pops; the finger never drags it.** `SalahPageContent` is the old
Spacer layout: `if showBottom` inserts the sheet (`.move(edge: .bottom)` + opacity) and two
extra Spacers above the circle; all of it animates from the `withAnimation(.spring(response:
0.35, dampingFraction: 0.85))` around the `navPosition` change. A vertical swipe past 30 pt on
the pager (`abstractedDragGesture`, `.simultaneousGesture` on the pager itself, ignored unless
`horizontalPage == .main`) flips it: up opens, down closes, down-while-closed refreshes.
**Axis lock:** the gesture has `minimumDistance: 0` and decides the axis after 6 pt of
movement, before the pager's own pan reaches its 10 pt slop. Vertical → `live.pagerLocked`
(the pager is `.scrollDisabled` while set), so sideways drift during a vertical drag can never
turn into a page swipe; horizontal → the gesture stays out of it. Cleared on release. Without
this, a diagonal-ish vertical swipe both paged and flipped the sheet (owner, twice). While the finger is down only `live.pull` moves (resisted ×0.5,
capped ±20): the chrome's chevron follows it and the open sheet fades a little. The bottom
86 pt of the VStack is an empty placeholder where the chevron / bottom bar used to sit, so the
Spacers split the page as before. `summaryCircle` crossfades score ↔ next-Fajr (opacity +
scale) in the same animation instead of a hard switch.

History, so nobody re-does it: on 2026-09-24 the owner asked for follow-the-finger, got a
custom DragGesture (three iterations: fixed spring, projected velocity + interpolating spring +
rubber band + axis lock), then a native vertical ScrollView with a snapping
`ScrollTargetBehavior` (which worked, with the inset gotcha that `ScrollGeometry.contentOffset`
carries the safe-area inset while `ScrollTarget` / `scrollTo(y:)` don't), then detent-style
commits with a progress-driven crossfade — and then asked for the pop back. The pop is what
they want. `git log 6de940a..2c5a110` has the other versions if ever needed.

**Per-frame values live in `PagerLiveState` (`@Observable`, held as `@State live`)**: `pull`
(the drag nudge), `scrollProgress` (0 Zikr, 1 Salah, 2 Settings, from the pager's
`.onScrollGeometryChange`) and `pagerLocked`. PrayerTimesView's body reads none of them, so
only the views that do re-render per frame: `SalahPageContent` and `PagerChromeView`. Keep it
that way. The sheet is always built when open and `TodaysPrayerListView` only builds buttons
for loaded prayers so `PrayerButton` can't fatalError before `loadTodaysPrayerObjects` runs.

**Backdrop and chrome while paging (2026-09-25).** `PagerBackdrop` (behind the pager, its own
view so only it re-renders per frame) is three page-coloured panels offset by
`live.scrollProgress`, status-bar strip included — it used to be one colour switched at the page
commit, which flashed the transparent Salah page gray mid-swipe. Toward Settings the chrome now
slides out with the Salah page (`visualEffect` offset by `settingsness`) instead of fading on
top of Settings.

**Top bar and bottom bar are fixed chrome** (`PagerChromeView`, a sibling of the pager in the
root ZStack): hamburger `Menu` + `TopBar` on Salah / "Zikr" title on Zikr; chevron hint on Salah
with the sheet closed; `CustomBottomBar` on Salah with the sheet up and always on Zikr. Opacities
come from `navPosition` (animated by the same `withAnimation`) and `live.scrollProgress`
(`zikrness`); the whole thing fades with `settingsness` so Settings slides in over nothing and
keeps its own header. Owner's call: no chrome on Settings. Settings must not set
`.navigationTitle`: it's inside the root NavigationStack, so its title became the back-button
label on every pushed page.

**The Zikr page is a vertical wheel of circles since 2026-09-25** (`ZikrCircleWheel` in
DailyTasksView.swift; see Tasbeeh → Zikr page). It scrolls on the other axis from the pager, so
the strip locks below no longer apply to it (the old `DailyTasksView` strip is kept, unused, and
still has them). History of the strip:

**The Zikr page's task strip holds the pager while touched.** Nested same-axis scroll views
chain in UIKit (a drag on the strip at its last card turned the page, 2026-09-24). Two locks,
both `live.pagerLocked` → the pager is `.scrollDisabled`: the strip sets it on touch-down
(`DragGesture(minimumDistance: 0)`, simultaneous) and clears it on release / settle; and the
pager's own gesture (`abstractedDragGesture`, global coordinates) sets it on the first move of
any touch that started inside `live.stripFrame` (the strip's global frame, written by
DailyTasksView) — the strip's own lock wasn't always early enough on device for a flick
(owner, 2026-09-25). Don't turn off the pager's bounce (`bounces = false` on the UIScrollView
was tried for the rubber band past Zikr / Settings): paging's settle physics ride on bounce
and the owner felt the paging go stiff within minutes. The rubber band is prevented at the
gesture instead: when the pager gesture decides a drag is horizontal, a drag that could only
overscroll (finger moving right on Zikr, left on Settings) sets `pagerLocked` for that drag. `live`
reaches `DailyTasksView` through `.environment(live)` on the pager (optional `@Environment`, nil
outside it). Centering a card is local state only: it used to write `sharedState.selectedTask`,
whose `didSet` writes four more `@Published` properties — five home-screen re-renders per card
passed, which is what made the strip stutter. The tap action sets `selectedTask`.

The geometry handler ignores reports while `contentSize.width < 2.5 × width`: the first one
arrives before the three pages exist (midX/width = 0.5 → "Zikr") and left
`horizontalPage = .zikr` on the Salah page at launch, which also disabled the vertical drag
until the user paged away and back.

Hamburger (Salah page only since 2026-09-25; the Zikr page has the History & Mantras button there) = a `.popover` (`presentationCompactAdaptation(.popover)`) with the "shukr" wordmark
on top like the old sidebar, then Daily Ayah, Mantras, Zikr History, `#if DEBUG` Salah History
V1/V2 — a native `Menu` can't show the wordmark. Rows set `pendingMenuAction` and close the
popover; the action runs 0.25 s after it's gone so the push doesn't collide with the dismissal.
Map and Settings were dropped from it 2026-09-25 (the map opens from the circle's qibla arrow,
Settings is a pager page). It drives
`.navigationDestination(isPresented:)` pushes on the root NavigationStack. The old drawer
(`sideMenu` in Utils.swift, `showSideMenu`) is parked: toggling it published shared state and
re-rendered the whole home screen to animate, which is why it felt laggy.

Settings page has its own header row (back chevron → `horizontalPage = .main`, title,
`ColorModeToggleButton` for light/dark/auto). Zikr page = `ZikrPageView`: `ZikrCircleView`
("Zikr / click to freestyle") above the `DailyTasksView` card frame. The bottom bar mirrors the
pager (Zikr | Salah | Settings).

Known: the pager ignores the bottom safe area (to keep the bottom bar flush), so the Settings
`Form`'s last row sits under the home indicator.

**Re-render hygiene (the "every picker flickers" bug, 2026-09-25).** On the phone every Menu
picker and the hamburger blinked; the iOS 18 sim was clean. `Self._printChanges()` on the phone
showed the root re-rendering ~1×/s and Settings with it. Causes, all fixed: (1) the compass —
`EnvLocationManager` published heading/qibla on every tick and the root holds it as
`@StateObject`, so every heading update re-rendered the whole app; heading/qibla now live in
`CompassState` (`@EnvironmentObject var compass`), subscribed to only by `MainCircleView` and
the map, with `headingFilter = 1` and a 0.5° change guard. (2) GPS — `userLocation` was
`@Published` on the same object; it's a plain var now and `PrayerViewModel` follows fixes via
`locationUpdates` (a `PassthroughSubject`). (3) App-group writes — every write to the group
suite (even the same value) invalidates every `@AppStorage` bound to it, i.e. Settings and the
root; `lastLatitude`/`lastLongitude` are written only when moved >50 m (`storeLastCoordinate`),
`lastCityName` only on change, the widget one-shot flags only when set, and the widget no
longer runs its own GPS + compass manager (`PrayersWidgetLocationManager` is unused; it
rewrote `lastCityName` on every fix from the extension process). Reading `_printChanges`:
a "`_qiblaSensitivity, _calculationMethod, … changed`" line on SettingsView is an artifact of
the struct being re-created by its parent (each `@AppStorage(store: UserDefaults(suiteName:))`
makes a new store instance), not evidence of a defaults write — look at the line before it.
Remaining renders are interaction-driven (`scenePhase`, `scrollPage`, `sharedState`).

Settings has a hold-to-repeat `HoldRepeatStepper` (qibla accuracy; SwiftUI's Stepper needed a
press per step). The tasbeeh's "+N" quick-add button is per mantra now (see Tasbeeh → Pause
screen); the old Settings field (`tasbeehSecondaryStep`) is gone and its value only seeds the
no-mantra step.

Broader lag lever not yet pulled: `SharedStateClass` is an `ObservableObject`, so *any*
`@Published` change re-renders every view holding `@EnvironmentObject sharedState` (nearly all
of them). Migrating it to `@Observable` (per-property tracking) would cut most of that. Mechanical
but wide: `@EnvironmentObject` → `@Environment(SharedStateClass.self)`, `$sharedState.x` needs
`@Bindable`. Do it with a builder in the loop.

Parked, not deleted: `DuaPageView` ("Notes") used to be the `.left` page; the block is
commented out in the body and there's no route to it now. `bottomTabPosition == .zikr` is
never set anymore; the branches in `BottomSharedView`, `mainCircle.swift`, and `TopBar` that
check it are dormant. `settingsViewNavBool` / its `.navigationDestination` push is unused.

## Prayer scoring (Models/PrayerScoring.swift)

Agreed with the owner 2026-09-24; the one rule, used by the app, the widget checkmark, the
"I already prayed" notification action and the time editor (`PrayerModel.setPrayerScore`).
`numberScore` = points / 100: **Early** (≤ 30 min after the adhan) 100 · **On time** (first
half of the rest of the window) 99–80 · **Late** (second half) 79–60 · **Qaza** (after the
window) 40 · **Missed** nil/0. Linear from 100 at 30 min to 60 at the window's end, so the
only drop is 60 → 40. Qaza counts on purpose (the app gamifies praying; late beats never).
Day score = average of the five, unmarked = 0 (`PrayerScoring.dayScore`). Colours: Early green,
On time yellow, Late red, Qaza gray (`PrayerScoring.color`, also the map pins). Day-chart
reference lines at 80 / 60 / 40. Streak modes 2 / 3 now mean "in window" / "on time or better".
Before this, `numberScore` was the fraction of the window left (0 = Kaza) and the day score
reshaped it (first quarter 100 %, else 65–90 %, Kaza 65 % — no reason to beat the deadline).
`recalculateHistoryIfNeeded` (launch, once, flag `prayerScoringV2Recalculated` in the app
group) rescored every completed row from `timeAtComplete` (2 rows without one got a tap time
back from the old score), moved old Isha ends to 11:59 PM and rewrote every `DailyPrayerScore`.
It first copies the store to `<group>/Library/Backups/shukr.store.before-scoring-v2` (Library is
reachable with `devicectl device copy from`; the store at the group root is not). Ran on the
owner's phone 2026-09-24; a copy of that backup is on their Desktop
(`shukr-backup-2026-09-24-before-scoring`). Owner's 802 completed prayers: Early 142, On time
222, Late 289, Qaza 149; average day score 29.3 → 28.2.
Not done yet: a "How scoring works" ⓘ card (Early / On time·Late / Qaza / Missed + "day score
is the average") on the day score; the "all five on time" streak.

**Isha ends at 11:59 PM** (`PrayerDay.ishaEnd`, or an hour after Isha starts if that's later,
for summers far north), no longer at the rollover. The rollover ("Day Rolls Over At" in
Settings) only keeps the day's prayers up so a late Isha can still be marked — as Qaza.

## Streaks, celebrations, completion moment (2026-09-24/25)

- **Streak** (`prayerStreak`, standard suite) counts a day once: `calculatePrayerStreak` runs on
  every mark / time edit / widget reconcile and used to +1 each time once all five were in, and
  −1 on every call after an unmark (streaks went negative; clamped at 0 now). Posts
  `.prayerStreakContinued` once.
- **In-time days** (keys still `onTimeStreak`, `maxOnTimeStreak`, `lastOnTimeStreakDate`):
  consecutive days with all five prayed within their windows — no Qaza, none missed (≥ 60,
  `PrayerScoring.inWindowFloor`). Owner, 2026-09-25: "days where there was no qaza". Named
  "in-time", not "on-time", because On time is already a grade (80–99). It was all five
  Early / On time (≥ 80) for a day. **Perfect day** (`lastPerfectDay`): all five **Early**.
  Both in `updateDayMilestones`, once a day, posting `.onTimeStreakContinued` / `.perfectDay`.
- **Top bar** (`TopBar` + `StreakLabel` in Utils.swift): tap the city → the streak for 5 s; tap
  the streak → in-time days → max. Once the day's done (the circle's summary condition) the streak
  stays up instead of the city (owner: keep the city otherwise). Celebrations: heart goes green,
  number rolls up, hearts float; the on-time beat follows ~2.4 s later with sparkles.
- **Completing a prayer** (`CursorSwift/PrayerCompletionFX.swift`): haptic, `.prayerCompleted`,
  the circle's `CompletionFlourish` (arc sweeps closed in the score colour, glow, "✓ Asr ·
  On time · 88"), the row's `CompletionDotPop`. The list folds done prayers into a footer row, "✓ N done ⌄" (tap to show
  them; the words stay "N done" and only the chevron turns — swapping to "hide done" morphed oddly), under a divider like the rows' with even air above and below (2026-09-25;
  it used to hang under the list with a bare gap; a top row of score dots was tried and dropped —
  owner); all five come back when the day's complete; perfect day pops the
  dots in turn and shows "✦ perfect day".
- **Main circle**: progress ring coloured by the score you'd get now; a tap only buzzes when
  there's text to flip. Type matches the Insights ring (2026-09-25): name 32 pt light rounded,
  icon 22 pt light, captions subheadline thin secondary, score 44 pt light over "today's score".
  Between the rollover and Fajr the summary circle shows **yesterday's** stored score ("yesterday's
  score") instead of the empty new day's 0 (owner's call; `showingYesterday` in `summaryCircle`).
- **Edit time** (`PrayerTimeEditSheet`): range = the prayer's start … min(now, the day's
  rollover), so a Qaza after midnight can be set. `PrayerTimeWheel` is our own UIPickerView
  (hour / minute / AM-PM; hours loop and AM/PM follows like the system wheel): system wheels
  either knew one day (Isha's 12 AM snapped to the start) or showed a day column (owner: no).
  Invalid times are grayed and *not* corrected; Save (gray until a different valid time is picked,
  then a green edge + green text — owner) is disabled and a line says why (before the
  start / not yet / after the rollover). A picked clock time lands on the prayer's day or the
  next, whichever is in range; after midnight a line spells out the day and time. The window bar
  (Early / On time / Late) is a scrubber; a Qaza time parks the marker at the end, gray. Scrubbing
  used to hang on device (owner): every minute wrote the parent's @State (re-rendering the row
  behind) and called `reloadAllComponents` on the 4800 / 12000-row looping wheel, whose hour rows
  each ran 120 calendar lookups. Now the sheet keeps a local `draft` until Save, the wheel only
  `selectRow`s (reloading minutes just when the hour changes) and hour validity is cached.
- DEBUG-only: hamburger "Test Streak Celebration" / "Test Perfect Day" / "Old Insights"; launch
  args `-demoStreakCelebration`, `-demoDayMilestones`, `-demoPrayerCompletion` (switches to the
  dev test prayer times and marks prayers), `-demoInsights`, `-demoShareCard` (writes every share
  look to `<app data>/tmp/share-card-*.png`); any `-demo…` arg skips the notification prompt.

**Tasbeeh ring "alive" style** (`AliveRingFill`, Utils.swift): its knobs live in `AliveRingTuning`
(JSON in `aliveRingTuning`): ring width, glow, gradient turn speed, highlight / shadow strength and
drift, grain amount / size / brightness / fade depth / fade speed. **Settings → My Dev Stuff → Ring
playground…** (`RingPlaygroundView`) shows the ring live with a slider per knob; changes are what the
real ring uses; Share / Copy send the values as readable text + JSON (the owner sends back what they
like — paste the JSON into `AliveRingTuning`'s defaults); Reset = defaults. The grain no longer re-scatters 12× a second (it glittered —
owner: "like Cinderella"): the specks are fixed and each fades in and out on its own phase; the
gradient turns 8°/s (was 18) and the lights drift slower. DEBUG `-demoRingPlayground`. Ring styles now: alive (follows the playground), **fine** (the
owner's playground pick, fixed in `AliveRingTuning.fine`: 6 pt band, 23°/s turn, highlight 0.03,
shade 0.32, drift 0.63, grain 1350 / 1.34 pt / 0.32 / fade 0.29 at 0.24/s, glow 0.45), gradient,
classic — Settings → My Dev Stuff → Tasbeeh Ring.

**Mantras / sessions:** Mantras page is searchable (name, full text, notes). The editor is a
viewer first: title = the mantra's name, Cancel / Save appear only after an edit, revert / save
in place (sheet stays, keyboard goes). **Rates use active time**: `SessionDataModel.activeSeconds`
= `avgTimePerClick × totalCount` (time at the last count, pauses excluded) — `secondsPassed`
runs until Stop, so a session left running idle showed e.g. 33.6 s/count for a real 5.1 s.
`secondsPerCount` (session row, Zikr History) and `MantraModel.secondsPerCount` both use it.
Hold a session row to feel its pace (`PaceHoldGesture`, a 0.2 s UIKit long press so scrolls that
start on a row still scroll): tick + edge glow at once, then the pill border fills over one count
(drawn from the clock in a TimelineView), tick, repeat, until the finger lifts.

**Insights** (`CursorSwift/InsightsView.swift`, `InsightsProgress.swift`): three swipeable pages
(a paging horizontal `ScrollView` with a `scrollTransition` "drum": pages rotate 65° about Y
and shrink / fade as they leave — owner asked for it exaggerated), each a question — "am I getting better?" (`PrayerProgressList`: verdict +
prayers ranked by their last-4-weeks score, missed = 0, with an 8-week sparkline you can scrub
and the change vs the 4 weeks before), "how am I scoring?" (avg-score ring — tap for the grade
makeup as coloured arcs — the Week / Month / All time switch, which only affects this page, and
the five prayer rings, tap for avg / % prayed), "how consistent am I?" (streaks + the 14-day
prayer grid: filled = prayed, tap / drag to reveal a square's colour and details). The flat
single-page version is `InsightsView(layout: .old)` (DEBUG "Old Insights"). Rethink still open
(Start here #8).

**Daily Ayah**: reveal once, it stays revealed for the day (`dailyAyah.revealedDay`); share →
`AyahShareOptionsSheet` picks a look (`ayahShareStyle`, remembered) and shares only the image —
9:16 `AyahShareCard` in mint / grain (the light welcome screen: `AnimatedWavyGradient` +
`NoiseOverlay` on white) / forest. Both of the page's sheets hang off its root: a sheet attached
inside the top bar never presented (the share button used to do nothing). See "Share card —
CHECK ON RELEASE".

## 99 Names (hamburger → 99 Names, 2026-09-25)

A small side app for getting to know Allah through His names. v1 (built):
`CursorSwift/NamesOfAllahData.swift` (Allah + the 99 Names in Tirmidhi order: transliteration,
Arabic, meaning, "also means", explanation) and `CursorSwift/NamesOfAllahView.swift`: a searchable
list (Uthmani font), a page per name (big Arabic, meanings, explanation, prev / next, mark as
known), and flashcards (`NameFlashcardsView`: deck "still learning" / all, optional meaning-first,
tap to flip, swipe right "knew it" / left "still learning" or the buttons, end-of-round ring).
The start page is a fanned preview of the deck (top card = a real name from the chosen deck,
follows "front shows") with deck / front tiles and "Begin · N cards"; ↺ top-right undoes the
last answer (restores that name's known state, the card flies back in from where it left).
Known names: `namesKnown` (standard defaults, comma-separated ids) → the ring at the top.

Source: the owner's repo **github.com/izhansari/99Duas** — `duas_99_names.jsx`, `D` array
(`[id, transliteration, meaning, category, explanation, personalDua, alsoMeans]`, 100 entries),
plus `My Dua Collection 99 Names.pdf` (the owner's revised, longer personal duas) and `HT`
("Heart Themes"). The Arabic isn't in the repo; it's the standard spelling, added here.
**Not included on purpose:** the owner's personal duas and their life-area categories
(Marriage & Family, Career & Building, …) — they're his; other users get their own:

**Next (v2, not built): personalised AI duas.** Give the user a prompt to copy into their own AI
(ChatGPT / Claude), which — knowing them — writes one dua per name, calling on Allah by it, in a
fixed format; the user pastes the output back and shukr parses it into a dua per name (show it on
the name's page and a "my duas" view, like 99Duas' Du'as tab: grouped, searchable, favourites).
The owner has the original prompt in an old Claude chat and will provide it — don't invent one.
Design the paste format to be parseable (e.g. numbered `n. Name — dua` lines or JSON), store the
duas locally (SwiftData model keyed by name id), and let the user edit / re-paste.

## Prayer day rollover (PrayerDay.swift)

**Since 2026-09-25 the day turns at Fajr** (owner's call; the Settings "Day Rollover" picker is
gone, `prayerDayRolloverHours` is no longer read). `PrayerDay.fajr(onCalendarDayOf:)` computes
Fajr from the app group's lastLatitude / lastLongitude / calculationMethod / school via
`PrayerUtils` (both targets, cached per day + location + method); before today's Fajr it's still
yesterday. No location → 3 AM (`fallbackHours`, owner's pick). `sessionDayStart()` = the prayer
day's Fajr, `rolloverInstant(after:)` = the next day's Fajr (time editor's latest time, daily
refresh timer). The summary circle's `showingYesterday` only triggers in the no-location case
now. Sim-checked: `next refresh scheduled for` the next day's Fajr. The rest of this section
is the hour-based history:

The prayer day can run past midnight (owner prays Isha at 1 AM sometimes; before this there was
nothing to mark it against after midnight). Since 2026-09-24 Isha's *window* still ends at 11:59
PM — see Prayer scoring. Settings → "Day Rollover" → "Isha end time"
Midnight / 1 / 2 / 3 AM, stored in the app group as `prayerDayRolloverHours` so the
widget agrees. `Models/PrayerDay.swift` (both targets) is the only place that knows about it:
`PrayerDay.date()` / `start()` = which calendar day is "today" (before the rollover hour it's
still yesterday's), `rowRange(forDayStarting:)` = the calendar-day bounds every "today's
prayers" fetch uses, `ishaEnd(on:ishaStart:nextFajr:)` = 11:59:59 PM (or Isha
start + 1 h), capped at the next Fajr — not the rollover, `rolloverInstant(after:)` = when the app's daily refresh timer fires. Prayer rows stay
keyed by the calendar day their Fajr falls on; `fetchPrayerTimes` rewrites an uncompleted
Isha's `endTime` when the setting changes, so the current day picks it up at once. Everything
that used `Calendar.startOfDay(for: Date())` for "today" in PrayerViewModel, the summary
circle's "yesterday", and the widget (`makeEntry`, `createWindowsFromTimes`,
`completedPrayerNamesToday`) goes through PrayerDay now. History views that take an explicit
date (`loadPrayerObjects(for:)`, PrayerScoreChartView, DayView) still mean the calendar day.
Sim-verified 2026-09-25: rollover 2 → `Isha : 8:05 PM - 1:59 AM` in the launch log.
Zikr sessions follow it too (2026-09-25): "today's sessions" for task progress (DailyTasksView,
MantraTaskRows, TopBar's stats) start at `PrayerDay.sessionDayStart()` = the prayer day's date +
the rollover hours, so a 1 AM session with a 3 AM rollover counts for yesterday. The circle's
day score is computed for `PrayerDay.date()` (it used `Date()` and read 0 % after midnight).

## Map (CursorSwift/LocationMapView2.swift, branch claude/map-rework)

Rewritten 2026-09-25. Two jobs: show the qibla so the user can line up with the buildings
around them, and show every prayer they've marked. UIKit `MKMapView` on purpose — SwiftUI's
`Map` has no clustering and the owner has ~800 pinned prayers. (Rotation is allowed since late
2026-09-25 — see the Handoff; the north-up reasoning below still explains the line.) **North-up on purpose**: phone
compasses are often off, so the map draws the computed direction — an `MKGeodesicPolyline`
from the user's dot to the Kaaba (green) — which is right regardless of the compass; the
ring **sits on the user's dot** (`MapAnchor`, the dot's screen point written by the coordinator
on every map frame via `mapViewDidChangeVisibleRegion`; `AnchoredQiblaRing` is the only view
that reads it) and repeats that bearing with its arrow while its chevron follows the compass
(`CompassState`) so the user knows which way to turn. It used to sit at the screen centre and
drift off the dot on any pan — the owner's biggest annoyance. **The ring is the gauge**: a green
arc runs along it from the chevron (where you point) to the triangle (the Kaaba) — the short way
round — and shrinks as you turn; the pill reads "← Turn left 47°" / "Turn right 47° →" /
"Facing Mecca 🕋" (`signedAngleDifference`, + = clockwise). Aligned: `AlignedEdgeGlow`, a
blurred green stroke hugging the whole screen edge. Zoomed out past `latitudeDelta 0.5` the
ring, arc and triangle fade (`MapAnchor.zoomedOut`); the chevron stays on the dot. The status pill says "Facing Mecca / Turn left / Turn
right". Prayer spots: all filtered prayers are added as annotations once per filter change and
MapKit clusters/culls them (the old version tore every pin down and rebuilt it on each pan —
that was the blink and the cost); pins are coloured by score like the app; the visible count
comes from `mapView.annotations(in: visibleMapRect)`. Tapping a pin or a cluster opens
`PrayerSpotSheet` (one view for both, via `PrayerSpotSelection`) as a half sheet
(`.medium`/`.large`, background interaction enabled so the map stays usable): headline,
per-prayer counts + average score for a cluster, then the prayers newest first by day — name,
"prayed 6:34 PM", the window and how far into it ("2h 22m in" / "after it ended"), score % with
the score-colour dot and the word (Optimal/Good/Poor/Kaza), with the spot's address
(reverse-geocoded once per rounded coordinate, cached on the view model). The tapped pin stays
selected — scaled 1.3×, green, on top — until the sheet goes (`didSelect`/`didDeselect`; the
view deselects when `selection` becomes nil). Tapping another pin while a sheet is up goes
through `LocationViewModel.present`: dismiss, then present the new one 0.4 s later, because
swapping `item` under a live sheet kept the old detent and sometimes came back full height.
Compact detent (`fraction(0.32)`) for one prayer, `.medium` for a cluster. The visible count is
our own pins inside `visibleMapRect` — `annotations(in:)` returns clusters *and* their members
and double-counted. Default filter range is all time (`defaultStartDate = .distantPast`; the
filter sheet's start picker shows the earliest pin instead of year 0001). A **filter bar** at
the bottom of the map (prayers mode) says what the pins are as a sentence — `filterSentence`:
"Showing all your prayers" / "Showing Fajr, Isha from the last 30 days" / "Showing prayers from
Jan 1, 26 – Mar 3, 26" — and opens the filter sheet (green when a filter is active; the side
filter button is gone). The sheet is a chip grid of `QuickRange`s (All time / This week / Last 30 days / This year /
Last 12 months / Custom, each with a symbol) and a row of five prayer icon chips
(`prayerSymbol(_:)` is the shared icon set); the date pickers only appear under Custom. The
tapped pin keeps its score colour and gets a green layer shadow + 1.35× scale (turning it
green read as "Optimal"); `swappingSelection` stops the sheet-dismissed cleanup from
deselecting the pin just tapped during a swap; `keepInView` always centres the tapped pin between the top pills and the sheet (2026-09-25; it used to move only pins near an edge or under the sheet); `.presentationContentInteraction(.scrolls)` so scrolling the list
doesn't drag the sheet up. The old full-screen sheets that re-drew a map of the pin are gone. Location comes from the app's
`EnvLocationManager` (no second CLLocationManager); nothing publishes per pan (bearing follows
the user's fix, count and Mecca-proximity publish only on change), no `asyncAfter` timers.
Reached from the circle's qibla arrow (`fullScreenCover`).

**Map controls (2026-09-25)**: Liquid Glass (`mapGlass`, material fallback < iOS 26; owner: the
white squares looked dated): a round ⌄ close (was "Close"), the status pill as a glass capsule
(green text + edge when facing Mecca), map style + locate grouped in one capsule (top right), and 🔍 **Explore**
in the bottom-right corner (moved there — owner; green-tinted while a layer is on). Explore = `MapExploreSheet`, a short sheet with layer tiles
(My prayer spots · Mosques · Halal food "soon") — tap to show, tap again for the qibla — and the
active layer's settings (prayer filter sentence → the filter sheet; mosques: Driving / Walking,
`mosqueTravelMode`). The old bottom filter pill is gone: in prayer-spots mode the top pill reads
"23 prayers in view" and, with a filter on, a green second line ("every Fajr, Maghrib, Isha");
tapping it opens the filters. Filter sheet chips are green tints now (were solid green).
DEBUG `-demoPrayerPins` seeds 26 pinned prayers around the sim's location when there are none. One sheet at a time: tapping a pin while Explore is up closes it first.

**Mosque finder** (`CursorSwift/MosqueFinder.swift`, 2026-09-25): a layer in Explore — no mosque SF Symbol exists, an emoji clashed with the pills and the moons are taken
(Isha `moon.stars.fill`, 99 Names `moon.stars`), so the owner is picking a `MosqueIconStyle`
(button + pin symbols: Finder = `sparkle.magnifyingglass` / `building.columns.fill` (default),
Columns, Lodge, Jamaat, House & flag) in Settings → My Dev Stuff —
is a third mode beside qibla / prayers (one at a time, `setMode`). MapKit has no mosque POI
category, so `MosqueSearch.find` runs "mosque", "masjid", "islamic center" `MKLocalSearch`es over
~30 km around you, keeps names that read like a place of prayer (mosque, masjid, musalla, jamia,
Islamic center / society / association…), drops shops / restaurants / schools / academies unless
the name says mosque or masjid outright, drops food / store / hotel / bank… POI categories, and
de-dupes (60 m, or same name within 500 m). First results zoom to you + the nearest six; panning
well away shows "Search this area". Green markers (the app's green — the sage read dull, owner),
clustered (a cluster zooms in). Tap →
`MosqueSheet`: drive time + distance (`MKDirections.calculateETA`), `LookAroundPreview` when
Apple has imagery, the travel time (tap to flip driving ↔ walking for this mosque; default
from Explore), Directions (primary, green tint; a `Menu` at the button: "Directions in" Apple
Maps / Google Maps / Waze by name only — no symbols, like most apps — via universal links, then
Share location = an Apple Maps link, for a friend or the Tesla app), Call (secondary, gray), website in `SFSafariViewController`,
and "Details & photos" = `mapItemDetailSheet` (Apple's place card; it calls the place "Mosque" —
so Apple does categorise them, just not publicly). Sim-verified in Manhattan: 27 mosques, Masjid
Manhattan 6 min / 0.5 mi with Look Around of its door. The place card showed no photos in the sim. `CursorSwift/LocationMapView.swift`
(an older copy, unreferenced) was deleted.

## Widget ↔ app

Widget buttons: compass → app main page + qibla map; tasbeeh → `horizontalPage = .zikr`; list /
text toggles are in-widget. These use one-shot flags in the app group read on `scenePhase ==
.active` in `PrayerTimesAndTracker`.

**One SwiftData store, shared.** `SharedStore` (`shukrWidget/SharedTargetForIntents.swift`,
compiled into both targets) owns the schema and the store URL: `<app group>/shukr.store`.
`Models/` is in both targets' `fileSystemSynchronizedGroups` (pbxproj) so the schema matches.
The app's `ModelContainer` comes from `SharedStore.makeContainer()`, immediately followed by
`importLegacyStoreIfNeeded(into:)` in `shukrApp`.

**Where the old data actually is.** With a default `ModelConfiguration()`, SwiftData puts
`default.store` in the **app group's** `Library/Application Support/` whenever the app has an
app-group entitlement (this app has had one since the widget's shared UserDefaults), *not* in
the app sandbox. That is why the owner's data went missing (2026-09-23, f9f7685..4e157f3):
both the file-copy migration and the first import looked at `URL.applicationSupportDirectory`
(the sandbox), found nothing, and the app started on an empty group store. Reproduced in the
sim: seed 46176a5 → install 4e157f3 → tasks gone, no `legacy import` line at all. The widget
process compounds it (its Application Support is the *extension's* sandbox), but the path was
wrong in the app too. `SharedStore.legacyURLs` now checks the group location first, then the
sandbox.

**Rule: the widget never creates and never migrates the store.** `SharedStore.widgetContainer`
opens the file only if it exists *and* its metadata already carries the current version
(`storeIsCurrentVersion`, read via `NSPersistentStoreCoordinator.metadataForPersistentStore`
without opening), and opens it without the migration plan. WidgetKit refreshes right after an
install: a widget-created store would be empty and pre-empt the import, and a widget-run
migration races the app's own — sim-reproduced 2026-09-23: the app's staged migration found the
file already at 2.0.0 mid-flight and died with "model incompatible" (134110). Until the app has
migrated, the widget renders its placeholder and the checkmark is inert; it retries on each
access. The app's `makeContainer()` and the legacy temp copy open with the plain current schema
and let SwiftData infer the lightweight migration (see Mantra model section).

**Legacy import** (`importLegacyStoreIfNeeded`, app only, gated by `legacyStoreImported.v2` in
the app-group defaults — v2 because the v1 key was set by builds that found nothing): copies the
legacy `default.store` (+wal/shm) to a temp dir, opens that copy as a second `ModelContainer`,
and *merges* rows into the shared store — tasks (by id, first, so sessions can relink),
sessions (by id), mantras (by text), duas (by id), prayers (by name+day; newer row wins unless
it's incomplete and the old one is complete, then the completion fields are copied over), daily
scores (by day). Ids are preserved. Flag is set only after a successful save; failure retries
next launch; if no legacy file exists the flag is left unset (two `fileExists` per launch, and a
false "done" is the failure mode we just had). Old files are never modified or deleted.
Logs `✅ legacy import: tasks=… sessions=… …`, `❌ legacy import failed …`, or
`ℹ️ legacy import: no legacy store found`.

**Completing a prayer from the widget does not open the app.** `MarkCompleteIntent` carries the
shown prayer's name/start/end, opens the shared store (`SharedStore.widgetContainer`, one per
widget process), fetches or creates the row, marks it complete, scores it at the tap, records
the app's last known location, cancels nudges, saves, sets `widgetWroteStore`, and reloads the
widget. The widget's timeline reads completion state straight from the store
(`completedPrayerNamesToday`) and skips done prayers when picking what to show. On activation
the app runs `PrayerViewModel.reconcileAfterWidgetWrites()`: if the flag is set it saves, calls
`context.rollback()` so cached rows refault, re-reads today's prayers, re-cancels nudges (in
case an extension can't reach the app's notification center — unverified), and recomputes
streak / day score. In-app completions call `pushCompletionsToWidget()` (save + reload).

Sim-tested 2026-09-23 @ 0058a41: widget tap completed Asr in place (score 0.52, location
recorded), widget advanced to Maghrib, app showed it complete on reopen.
Sim-tested 2026-09-23, legacy import: seeded 46176a5 with a task, a linked 4-count session and
a completed Asr; installed the fix over it (after a buggy build had already created an empty
`shukr.store` and completed Dhuhr in it). First launch: `✅ legacy import: tasks=1 sessions=1
mantras=0 duas=0 prayers=0 (merged 1) scores=0`; task/session back with original ids and link,
Asr completion carried onto the new row, Dhuhr kept, legacy files' mtimes unchanged; second
launch imported nothing. Still untested: tapping before a prayer starts; widget creating the
row when the app hasn't opened that day; the import on the owner's phone; whether the nudge
for a widget-completed prayer still fires on a real device.
To verify on device: complete from the widget, check the nudge for that prayer does not fire;
open the app and check the prayer shows complete with the right score. If the nudge still
fires, the extension can't cancel app notifications and we need another approach (e.g. the app
schedules nudges as fewer, later-verified notifications).

**Notification actions** (`NotificationDelegate` in shukrApp.swift). Every prayer notification
carries `Round1_Snooze`: "I already prayed" / "Nudge in 5 minutes" / "Nudge in 10 minutes";
the follow-ups carry the same three (plus the round-2 jokes). Two things that broke them
before 2026-09-25: (1) `completionHandler()` ran before the follow-up was added — an action
tapped with the app not running launches it in the background only until that handler, so
the "5 minutes later" nudge often never got scheduled; every branch now completes from inside
`UNUserNotificationCenter.add`'s callback. (2) Round-2 "Yes" re-nudged after 5 *seconds*.
"I already prayed" calls `SharedStore.markPrayerComplete(named:start:end:)` — the routine the
widget's checkmark uses (extracted from `MarkCompleteIntent`): own container, scored at the
tap, nudges cancelled, `widgetWroteStoreKey` set so the app reconciles on activation. It
needs the prayer's name/start/end in the notification's `userInfo`, which
`scheduleThisPrayerNotifAt` sets and the snooze follow-ups pass along; the Settings-page test
notifications have none, so the action is a no-op there. The "Test Start" button is only a
different trigger for the same category; the sim's notification list wouldn't expand on
long-press, so the action path is verified by reading, not by tapping.

**Qibla accuracy** (`qibla_sensitivity`): the compass reads it from the app-group suite
(`QiblaSettings`), and until 2026-09-25 the Settings stepper wrote it to the standard suite, so
it never did anything. Everything uses the group suite now; `QiblaSettings.migrateFromStandardDefaultsIfNeeded()`
(launch) carries an old value over once.

Compiler warnings worth a sweep (not blocking): `PrayerTimesAndTracker.swift` unused `context`
/ `completedTime`; `PrayerViewModel.swift` `@State` in a class (line ~101), `objectsToCheck`
should be `let`, unused `endOfDay`.

## Tasbeeh / zikr feature

Entry: `tasbeehView` is a `fullScreenCover` at `PrayerTimesAndTracker.swift:412` driven by
`showTasbeehPage`. Launchers preload `SharedStateClass` (`selectedMode` 0 freestyle /
1 timed / 2 count, `titleForSession`, `selectedMinutes`, `targetCount`) then flip the bool:
`ZikrCircleView` tap on the Zikr page (freestyle), task card tap (`DailyTasksView`
`tapOnTaskCardAction` via `selectedTask.didSet`), post-salah button (`FloatingChainZikrButton`
in Utils.swift, `isDoingPostNamazZikr` runs 33/33/34 sequence inside the view).
`mainCircle.swift`'s `handleTap` freestyle branch is dormant (needs `bottomTabPosition == .zikr`).

Session lifecycle in `tasbeehView`: `startTimer()` → tap/drag increments → `togglePause()`
accumulates `totalPauseInSession` so `secsPassed` excludes pauses → `stopTimer()` saves a
`SessionDataModel` (if count > 0) and shows `ResultsView` → `completeStopTimer()`.
Task progress: `SessionDataModel.task` links a session to the `TaskModel` it was launched
from (set in `saveSession()` only when mode != 0 and not post-salah). `DailyTasksView` holds a
`@Query` of today's sessions and computes `task.progress(in:)` live. Rules the owner set:
a task only counts its own linked sessions; no spill-over between tasks with the same mantra;
freestyle and post-salah sessions never affect tasks. The query's "today" is fixed when the
view mounts (it remounts on every nav change, so midnight staleness is minor).

Done:
- [x] Removed `WidgetCenter.reloadAllTimelines()` from every count (was for the retired count widget; burned refresh budget).
- [x] Screen stays awake while a session is active and not paused (`isIdleTimerDisabled`).
- [x] `inMinSecStyle2` dropped the seconds when under a minute ("you'll finish in ").
- [x] Two tasks with the same mantra completed together, and cards only refreshed on remount. Sessions now link to their task; progress is a live `@Query`. Minutes tasks now complete at `>=` goal.

**Pause screen** (`pauseScreen_StatsSettingsBG`, redesigned 2026-09-25 — owner: the bottom
buttons "didn't feel on brand", keep the bento, surface the mantra's full text and notes):
"paused · 33 count session", then a mantra card (name → `MantraPickerView`; the full mantra,
Arabic lines in the Uthmani face and the rest light rounded, 4 lines then tap to expand; notes;
the quick-add row; ✎ → `MantraEditorView`), then `ZikrBento` (end of tasbeehView.swift, shared
with the results screen): count / time / rate as glass tiles (same material and light rounded
type as the mantra card — the old white `tertiarySystemBackground` boxes glared in light mode
and went black in dark) plus, in a count goal, a full-width finish tile ("in 1m 20s" ⇄ "6:42
PM", a tile so it reads as tappable — owner), then labelled chips (stops at goal ↔ keeps going — hidden in freestyle —, sleep +
its dimmer, haptics, light / dark). The haptics chip is our own radio-waves icon (`iphone`
between `wave.3.left` / `wave.3.right`; the stock symbol has only two waves a side): variable
value 0.2 / 0.5 / 1 lights 1 / 2 / 3 waves for light / medium / strong, the waves ripple
(`variableColor.iterative`) and the phone bounces on each change. The mantra is locked (no
picker) in task sessions (mode ≠ 0 with `selectedTask`, "from your task") and post-salah ones. At the bottom, Finish (outlined) / Resume (sage). The red ✕ and
the top-right play button are hidden while paused; tapping the dimmed background still resumes.
`tasbeehView.sessionMantra` = `mantraForSession`, else `MantraModel.find(named:)` on the title.
**Mantra page** (`MantraEditorView`, from the Mantras list / history swipe): `MantraCardFields`
(shared with the pause ✎ editor) on a grouped card as the page's top — its name IS the title.
**Nothing may change the nav bar's height** (owner: the page shifted as Cancel / Save and the
title came and went): the trailing slot always holds a button — a pencil while viewing, `SaveButton`
while editing (green text only with something to save, gray otherwise; also on the ✎ sheet) —
Cancel appears only while editing, and the name in the bar is a principal item that fades in once
the card has scrolled past ~64 pt. The page opens read-only (`MantraCardFields(editable:)`: fields locked); the pencil unlocks
them in place — name, full mantra and notes each get a box with a sage edge, drawn behind padding
every field always has, so nothing moves. Count in sets works without the pencil (saves straight
to the row; not part of Save). Save / Cancel go back to viewing. A new mantra opens editing.
Task circles centre the focused one on the width. Then `ZikrBento(grouped: true)`
("Lifetime"), the mantra's tasks as scrollable circles (`MantraTaskCircles`; tap → edit goal,
long-press → edit / delete; header "N tasks"), then sessions by day like Zikr History. The bento's
count / time tiles no longer spin and buzz on tap (owner: did nothing; only rate flips).
Count in sets skips 1 (off → 2 → 3…; one per tap is the screen itself); subtitle one line:
"recite a set, tap once" / "a +5 button while you count".

**Count in sets** (was "quick add"; owner: the name didn't say what it's for — recite a set on
your own, on your fingers or in your head, then tap once): the "+N" button in a running session — a toggle since 2026-09-25: on, every tap / drag counts N (see Handoff).
Per mantra on the row, `MantraModel.quickAddStep` (**schema 2.1.0**, 2026-09-25 — a defaulted
Int, lightweight; the data pass's `QuickAddSteps.moveLegacySteps` carried the one-day
UserDefaults version `mantraQuickAddSteps` onto the rows and deleted the key). Sessions without a
mantra keep theirs in `quickAddStepNoMantra` (standard defaults, seeded from the old Settings
`tasbeehSecondaryStep`). UI: `QuickAddStepper` (binding) / `QuickAddStepRow` (live, saves) in
MantrasView.swift — mantra page section and the pause card. Migrated on the owner's 13 Pro Max
2026-09-25 (`quick add moved=1`, no errors); pre-migration backup on their Desktop
(`shukr-backup-2026-09-25-before-2.1.0`).
**Backup before any migration**: `SharedStore.makeContainer()` (app only) copies the store to
`<group>/Library/Backups/shukr.store.before-<version>` whenever it's about to open a store that
isn't at the current version — the group root isn't reachable with `devicectl`, Library is.
**Pause card ✎** opens `MantraCardEditor` (MantrasView.swift): the card itself, editable (name,
full mantra in the inset box, notes, count in sets) on the pause colour; Save gray until a change,
no swipe-dismiss with edits; a rename updates the session title on dismiss. The Mantras page still
uses the Form `MantraEditorView`.
**Results screen** (`ResultsView`, same style): a sage check that pops in, "saved to your
history", a mantra card (tap to move the saved session to another mantra; locked for a task's
session), `ZikrBento`, Done, and a quiet "View zikr history" (HistoryPageView in a sheet).
The bento's finish tile reads as one sentence: "you'll finish in 1m 20s" ⇄ "you'll finish
around 6:42 PM".
DEBUG `-demoPauseScreen` (add `-demoResults` to finish it) opens a paused 33-count Alhamdulillah session (and gives that mantra
sample text if it has none — simulator only).

**Zikr page** (`ZikrPageView` → `ZikrCircleWheel` + `ZikrCircleFace`, DailyTasksView.swift,
2026-09-25 — owner: keep the circle theme, the fixed freestyle circle wasted the page and the
tasks were squeezed into a 260 pt strip): a vertical `ScrollView` of 250 pt rows, `.viewAligned`
one at a time, `scrollPosition(id:)` on string ids ("freestyle", task uuid, "add"), content
margins that centre the current one; `scrollTransition` shrinks (×0.78) and fades (×0.45) the
others — the strip's effect on its side. Freestyle circle first, then tasks (user order, done
today moved to the end) with today's progress as the glowing ring and "12 of 33" / "done
today", then a dashed "New task". Tap = bring to centre, tap the centre one = start; long-press
a task → **arranging** (home-screen style, owner): the wheel fades out for a 3-column grid of
small jiggling circles (`phaseAnimator` wobble) with − badges (delete, alert); hold one 0.2 s and
drag — it lifts and follows the finger, the others move aside (a custom LongPress→Drag in the
grid's "arrange" coordinate space, slot = 3 columns × 134 pt rows; `onDrag`/`onDrop` was tried
first but simulated touches never start a system drag, so it couldn't be tested); order saved
as it changes; tap a circle → Edit goal; Done or a tap between circles leaves. While arranging
the pager is held (`PagerLiveState.holdForArranging`, separate from `pagerLocked`, which the
pager gesture clears on every lift); leaving the page (the bottom bar still works) ends
arranging — it used to leave the pager held and the Salah page frozen. The top-right chrome
slot is free again. The focused
circle sits at the screen's centre, not the page's (the whole wheel is offset up by the
difference, `screenCentreShift` — asymmetric content margins don't move scroll snapping). Dots down the **left** edge (owner), sage for done tasks, double as a scrubber: a
finger on them drags through the circles (14 pt per dot) with a pill naming the current one —
"like grabbing a page's scroll bar". "1 of 3 tasks done" / "all 3 tasks done today" under the
wheel, above the bottom bar. Circle size / fade follow distance from the middle in rows via
`visualEffect` (eased: 1 row ≈ 0.62×, 2 ≈ 0.45×, floor 0.38×; neighbours pulled in) — owner
wanted it more dramatic and not at its smallest the moment a circle leaves the middle. The
circles also ride a big arc bulging right and turn with it like a lazy Susan seen from above
(owner's sketch; `WheelFalloff`). The owner is choosing between `ZikrWheelStyle`s in Settings →
My Dev Stuff → Zikr wheel (DEBUG): Straight (original), Arc no tilt, Gentle arc half tilt, Lazy
Susan (default: 300 pt, 0.7 rad a row, full tilt), Tight wheel — keep the winner, delete the rest.
**Continue or start over**: tapping a task that's partly done today asks (centred alert):
"Continue from 4" starts the session with today's count on the ring (`SharedStateClass.resumeCount`
/ `resumeSeconds` → `tasbeehView.countOffset` / `timeOffset`; − can't go below it; only
`sessionCount` = tasbeeh − offset is saved, so nothing is counted twice), "Start over" counts a
fresh goal. The results card of a task session says "5 of 100 today". Sim-verified: 3 → continue
→ +2 saved 2, task showed 5. DEBUG `-demoZikrPage` (adds three tasks if there are none — simulator).

**Zikr History header** (`ZikrHistoryHeader`, HistoryPageView.swift, 2026-09-25 — owner: the
"All time" rows looked plain): the all-time count at 48 pt light, the last 14 days as bars (tap /
drag to read a day's count and time — a two-line label above the bars: "last 14 days" or the
day, rounded medium, over "N counted · time" in plain SF), and sessions · time tiles (per-count tile removed, owner).
DEBUG `-demoZikrHistory`.
**History & Mantras are one page** (`ZikrLibraryView`, MantrasView.swift): two pages side by side
in our own pager with a History | Mantras segmented switch in the nav bar that follows. A sideways
drag turns the page **only when it starts on the background** (owner): rows (sessions, mantras)
and the history chart register their global frames with `.noPageZone(_:)` (`NoPageZones`, read
only inside the pager's simultaneous DragGesture), so their own swipe actions / scrubbing keep
working — a system paged TabView took every sideways swipe, rows included. Rubber-bands past the
ends; settles on the projected translation (> ⅓ width). Both pages stay mounted, so the library
owns the chrome: one search field (sessions by mantra / title on History, mantras on Mantras —
`HistoryPageView(search:)`, `MantrasView(embedded: true, externalSearch:)`) and the + (Mantras
only — a hidden toolbar button still draws its glass circle, so it's added / removed). Sim-verified:
a row swipe shows Delete and doesn't page; a background swipe pages both ways. Mantras → History
(finger moving right) pages from anywhere, rows included — mantra rows only swipe left — and the
lists' vertical scrolling is off during a page swipe. **Tap a session** (History and the mantra
sheet) and it opens a strip under it: Mantra (History only) · Pace (plays the session's rhythm
until tapped again — the hold, hands-free) · Delete (confirmed); one open at a time. The mantra
sheet's sessions swipe to delete too.

**Post-salah prompt (2026-09-25, default "Pill at the bottom")**: once a prayer is marked (circle
hold or list) and the completion flourish ends, `PostSalahNudge` (PrayerCompletionFX.swift) shows at
the bottom of the Salah page where the sheet's chevron sits: the glass pill (bead icon — the hands
are the prayer-spot pins — and "Post-salah tasbih?") with a small ✕ badge on its corner. Tap → the
33 · 33 · 34; ✕, or a flick any way (it follows the finger in every direction — it used to move
only downward, so at the bottom it ran into the home bar and couldn't go up: owner) : it pulls
a resisting ~70 pt toward the finger and fades as it goes; let go past 60 pt (or flick) and it
finishes fading where it is, then is removed with no animation of its own (resetting its offset
during the removal made it pop back and fade twice — owner); otherwise it springs back; it also clears when the next prayer begins. With the
prayer list open it docks under the top bar (at the bottom it covered the last prayer; marking from
the list is the common path — owner saw no prompt at all while the list was up).
State: `PagerLiveState.postSalahNudge` (prayer name), set by MainCircleView; drawn by
`PagerChromeView` above the pager — as part of the page, dragging it to dismiss dragged the page
(owner); sim-verified a sideways flick dismisses it and the page stays. Owner tried a bottom arc
("drag up to open") and an in-circle prompt first and came back to the pill. The two earlier tries stay selectable (Settings → My Dev Stuff → Post-salah prompt):

**Post-salah offer in the main circle (alternative)**: once a prayer is marked (hold the
circle, or the list) and the completion flourish ends, the circle becomes `PostSalahCircleOffer`
(PrayerCompletionFX.swift), laid out like a prayer on the circle: the bead icon (`circle.hexagonpath`,
green — the hands are the prayer-spot pins) left of **"Tasbih Fatimah"** in the circle's big light
type, "after salah?" thin under it; the ring stays the circle's plain gray (a score-coloured ring —
red after a Late — read as demotivating, and all-green shouted: owner). "not now" is a small
capsule inside the circle, and the qibla arrow hides while the offer is up. A tap on the circle starts the 33 · 33 · 34 session
(owner: hold to mark, lift, tap — no reaching for a pill); "not now" under the circle dismisses it
(a swipe on the circle belongs to the pager / sheet); it also clears when the next prayer begins.
While it's up the circle's hold does nothing (it would mark / unmark the prayer behind it — found
in the sim). `MainCircleView.postSalahFor`. The pill below is the alternative, Settings → My Dev
Stuff → Post-salah prompt (`PostSalahPromptStyle`, `postSalahPromptStyle`).

The prompt that drops in after marking a prayer (`FloatingChainZikrButton`, Utils.swift) is a
glass capsule since 2026-09-25 — just the green hands icon and "Post-salah tasbih" (owner: less
text), 56 pt tall with a target ~24 pt past the pill. It **stays until tapped** (→ the session)
**or swiped away** (up or to either side; no more 5 s auto-hide) — was an outlined gray box, "post
salah zikr?"; same for Settings' light / dark / auto toast
(`floatingMessageView`: mode symbol + "Light mode" / "Dark mode" / "Auto · follows the sun").
Both use `mapGlass` (LocationMapView2.swift — the app's glass capsule helper; Liquid Glass on
iOS 26+). DEBUG `-demoChainButton` shows the prompt.

**Post-salah zikr** (`PostSalahTasbeeh` / `PostSalahPhaseStrip`, tasbeehView.swift, 2026-09-25):
one 100-count session (Subhanallah 33 · Alhamdulillah 33 · Allahu Akbar 34) saved once under a
"Tasbih Fatimah" mantra (created on first use with the phrases as full text and a note). Above
the circle: the phrase in Uthmani, "Alhamdulillah · 12 of 33", three segments; a success buzz
as each phrase ends; normal results screen at 100. Replaces three chained sessions
(`postNamazSequence`) that each reset the count, saved separately and closed with no results.
`isDoingPostNamazZikr` is cleared when the tasbeeh cover goes away. Its pause screen is its own
(owner: "a special one"): "paused · Tasbih Fatimah", `PostSalahPauseCard` — the three phrases as rows
(done ✓ / "12 of 33" highlighted / to come) instead of the mantra card — the bento, and only Finish /
Resume (no chips). The phrase strip hides while paused (it drew through the pause screen). Its results
card is locked ("33 · 33 · 34 after salah", no mantra switch); locked cards use
`.allowsHitTesting(false)`, not `.disabled` (which grayed them). Under the circle while
counting, `PostSalahReminder` — one of four, picked per session; each a motivating headline (the *why*)
over the narration (owner: "insight into why we should do it … the goal is to motivate"):
"Never let down" (never disappointed after every obligatory prayer — Muslim), "Keep pace with the
best" (the poor and the wealthy's charity — Bukhari & Muslim), "They fill the scales"
(Alhamdulillah fills the Scale… — Muslim), "Better than a servant" (Fatimah — Bukhari & Muslim;
it was taught for bedtime, so its text never claims "after salah" — owner dropped the on-screen
"taught for bedtime" tag). Paraphrased; no hadith numbers on purpose — add them only once checked. The reminder
and phrase strip fade with the pause screen instead of being removed (that popped); the top −/+N
buttons stay mounted, faded, for the same reason. **Finish takes two taps** in every tasbeeh
(owner: cleaner than an "are you sure?"): the first gives it a green edge and green text, "Tap to finish" (red read as a
warning — owner); it disarms after 3 s. DEBUG `-demoPostSalah`.

Backlog / known oddities:
- [ ] Infinity button (`tasbeehView.swift:302`, `simulateTasbeehClicks(100)`): owner wants this to become a user-set step size (e.g. +10) rather than a hidden +100.
- [ ] Mode 2 `progressFraction = tasbeeh / (Int(targetCount) ?? 0)` → `inf` on empty/zero target; ring fills and autostop fires on first tap. Mode 1 has the same hole if `selectedMinutes == 0`.
- [ ] `completeStopTimer()` forces `toggleInactivityTimer = false`, so the persisted sleep-mode preference never survives a session.
- [ ] `resetSharedState()` only runs on the empty-session path; `selectedMode`/`selectedMinutes` linger after a saved session.
- [ ] Estimated finish time on the pause screen is computed at pause time; stale by the pause length once resumed. `newAvrgTPC` includes ramp-up before the first tap.
- [ ] Dead code: empty `if selectedMode == 2 {}` in `estTimeLeft`, unused `resetTasbeeh()`, `NoteModalView`, `deleteMantra`, `timePassedAtPauseString`, `endTime` (written, never read). `secsPassed` returns 999 when `startTime` is nil.
- [ ] Count widget (`shukrWidget/shukrWidget.swift`) is commented out of the bundle; nothing writes its `count`/`paused` keys. Delete or revive.
- [x] After a task session the app now stays on the Zikr tab (the jump to `.main` in `tapOnTaskCardAction` was only a remount hack for refreshing cards).
- [x] Widget "complete prayer" works in place, no app launch (shared SwiftData store in the app group; widget writes it directly).
- [x] Zikr page moved to the left swipe (replacing Duas/"Notes"), Settings to the right swipe. Pager is a native paging ScrollView (first offset-based version was laggy on device).
- [x] Zikr History swipes (2026-09-25): left → Delete, confirmed with a centred `.alert` like
  unmarking a prayer (a bottom confirmation dialog felt out of place); right → the session's
  mantra page (`MantraEditorView` sheet), `text.quote` like the menu, tinted `Color.sage` (a
  muted green in Utils.swift for accents where system green is too stark).
- [x] Zikr History (hamburger → `HistoryPageView`, 2026-09-24): a List of every session newest
  first, grouped by day, under an all-time total; rows show mantra (live name, else the title
  snapshot), time, mode + target, count, duration and pace. The old paged-by-day version had a
  `scrollPosition(id:)` bound to an Int while the rows were keyed by Date, so it never tracked.
  `DayView` / `SessionCardView` / `DailyStatToggleView` in that file are now unused.
- [x] Mantra pace (2026-09-24): `MantraModel.totalCount` / `totalSeconds` / `secondsPerCount`
  are computed from its sessions (time-weighted: total seconds / total counts), nothing is
  stored, so no schema change and nothing to drift. Shown in the Mantras list row and in the
  editor, whose lower half (`MantraStatsBento` / `MantraTaskRows` / `TaskGoalEditorView` /
  `MantraSessionsSection` in MantrasView.swift) is: "Lifetime Stats" — count · time · rate as
  the pause screen's bento boxes (tap the rate box to flip per count ↔ per tasbeeh); the bento
  lives in the section *header* because a grouped section clips its rows to its own corner
  shape (26 pt on iOS 26+) and cut the boxes' corners — header text is secondary and inset, so
  the bento forces `Color(.label)` and `-20` horizontal padding; then this mantra's tasks as
  rows (mode + goal, today's progress; tap → `AddDailyTaskView(editing:isPresented:)`, the
  create-task sheet in edit mode: title "Edit Task", mantra locked, Save disabled until goal or
  units differ, confirmation dialog before saving; swipe → delete); then one "Sessions"
  section as one card, newest first, with a faintly tinted day-divider row before each day
  (`SessionRow` / `zikrDayLabel`, shared with Zikr History) so "when did I last do this" is
  the first row. Tried and rejected: a card strip for the tasks (wrong with one task), a plain
  Form editor (lifeless), day rows in the page colour (split the card into "empty" sections —
  and `tertiarySystemGroupedBackground` IS the page colour in light mode). `zikrDurationString` in AllModels.swift is the shared
  "1h 05m / 12m 03s / 45s" formatter.
- [x] Side menu → "Mantras" page (`CursorSwift/MantrasView.swift`): list built-ins read-only, add/rename/delete custom `MantraModel`s. Rename propagates to `TaskModel.mantra` strings; sessions keep their historical title. `MantraModel.builtIn` is now the single source for the four defaults (picker reads it too).

## Mantra model (schema V2)

Done 2026-09-23. A mantra is a row, not a string: `MantraModel { name, fullText, notes,
createdAt }` with inverse relationships `tasks` / `sessions`. `TaskModel.mantra: MantraModel?`;
the old string survives as `mantraName` (snapshot + fallback; the editor keeps it in step on
rename; `displayName` prefers the live name). `SessionDataModel.mantra: MantraModel?` alongside
`title`, which stays a history snapshot and is never rewritten. The four built-ins are ordinary
rows — seeded by the migration on upgrade and by `MantraModel.seedBuiltInsIfNeeded` on fresh
installs; `MantraModel.builtIn` is only the seed list. V2 also adds `TaskModel.sortOrder`: the
Zikr card strip's `@Query` sorts by it (completed-today cards still move to the end), the
migration numbers existing tasks in fetch order, new tasks get `TaskModel.nextSortOrder`, and
the strip header's arrows button opens `ReorderTasksView` (drag handles, writes `sortOrder`).
Before this the query was unsorted, which is why the cards looked arbitrary.

(2.1.0, 2026-09-25: `MantraModel.quickAddStep` — see Tasbeeh → Count in sets.)

**How the store is upgraded — no `SchemaMigrationPlan`.** `Models/SchemaVersions.swift` holds
`ShukrSchemaV2` (the live classes; opening a store with it stamps "2.0.0" in the metadata) and
`ShukrV2DataPass`. The store change is lightweight (`@Attribute(originalName:)` renames,
defaulted columns, optional relationships), so SwiftData migrates an old store by inference
when the app opens it — the mechanism that carried this store through every earlier model
change. A staged plan with hand-copied V1 models was tried first: it matched on the iOS 18.5
simulator and failed on the owner's iOS 27 phone with CoreData 134504 "Cannot use staged
migration with an unknown model version" (app dead at launch, store untouched). Inferred
migration has no hash dependency. The data work — seed built-ins, give every task a mantra row
(creating from its name if needed), link sessions by title, number tasks — is
`SharedStore.runV2DataPass` (app only, every launch; it fetches only rows that still need
linking, so a healthy store costs a couple of tiny fetches, and any store shape heals itself —
no flag to get out of sync). Logs `✅ schema V2 data pass: mantras=… tasks linked=… sessions
linked=…`. Sessions with an unmatched title stay unlinked on purpose. **Only the app migrates**
— see the widget rule under Widget ↔ app.

`TaskModel`'s relationship is stored as `mantraRef` with `mantra` a computed accessor: the
string snapshot `mantraName` has `originalName: "mantra"`, and inferred migration needs
renaming identifiers to be unique per entity — a relationship also named `mantra` failed on
iOS 27 with CoreData 134190. (The phone's store had already been given the V2 shape by the
staged attempt's automatic-migration options, so this was the second failure mode there.)
Next model change: keep it lightweight, never reuse a name that another property claims via
`originalName`, bump `ShukrSchemaV2.versionIdentifier` (the widget's `storeIsCurrentVersion`
compares against it), extend the data pass if rows need touching, and test on the newest iOS
you can — iOS 18/26 simulators accepted two things iOS 27 rejected.

**If the shared store won't open** (`makeContainer()` throws), `shukrApp` calls
`SharedStore.recoverFromUnopenableStore`: the file is set aside as
`shukr.store.unopenable-<timestamp>` (never deleted), the legacy-import flag is cleared, a
fresh store is opened, and the normal launch re-imports `default.store`. Then
`salvageSetAsideStoresIfNeeded` reads every set-aside file once with raw SQLite
(`SetAsideStoreSalvage`; the app links SQLite3 for the Quran DBs) and copies back what the
fresh store lacks: mantra fullText/notes into empty fields (by name), prayer completions onto
incomplete rows (by name + day), tasks and sessions missing by id. Flag per file name; a
failure leaves the flag unset so a fixed build retries. Don't assume a set-aside store has
every column (the owner's had no `ZSORTORDER`). This is what put the owner's phone back on
its feet on 2026-09-24 after the staged-plan attempt.

Selection plumbing: `MantraPickerView` hands back `selectedMantra` (name) *and*
`selectedMantraObject`; the object is set first so name-based `onChange`s can read it.
`SharedStateClass.mantraForSession` rides alongside `titleForSession`; `saveSession` links it,
falling back to `MantraModel.find(named:)` (the post-salah sequence only has names). The Mantras
page (hamburger → Mantras; `MantrasView` / `MantraEditorView`) edits name / full mantra / notes
and shows task + session counts; delete is `.nullify`.

Sim-tested 2026-09-23: V1 store (task + linked session + prayers) migrated with `mantras=4
tasks linked=1 sessions linked=1`, the legacy import then ran on top and merged 0, relaunch
clean; editor saves fullText/notes; a task created via the picker links by object; the task-card
strip scrolls inside the page without turning it. Not done (owner asked for minimal UI): pause /
results screens don't surface fullText or notes yet. Still to verify: the migration on the
owner's phone (real volume: 10 tasks, 492 sessions, 13 mantras).
