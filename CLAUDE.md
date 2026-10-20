# shukr — working notes

iOS SwiftUI app (iOS 18.0+, SwiftData, WidgetKit extension, adhan-swift). Prayer times +
tracker, qibla, tasbeeh/zikr counter, daily zikr tasks, duas, daily ayah. No CI, no tests
beyond Xcode templates. Build/run happens in Xcode on the owner's machine. scripts/: install.sh (his phones), testflight.sh,
asc.py, whatsnew.py, pull-feedback.sh, circle-check.sh, sim-sign.sh (team-signed sim build, for App Shortcuts),
perf-paging.sh + perf-frames.py (swipe hitches on his phone); the team's board scripts live in shukrGit/board/. A local agent can build with
`xcodebuild -project shukr.xcodeproj -scheme shukr -destination 'id=<your own sim's udid>'`.

Layout: `shukr/` app target (most UI in `CursorSwift/` — `PrayerTimesAndTracker.swift` is the Salah page + pager —
plus `tasbeehView.swift`; `Utils.swift` holds what's left of the shared pieces after the 2026-10-18 cleanup),
`shukr/Models/AllModels.swift` (SwiftData models + `SharedStateClass`), `shukrWidget/`
(PrayersWidget + the code compiled into BOTH targets — split out of `SharedTargetForIntents.swift` 2026-10-20: SharedStore,
PrayerUtils, WidgetMarks, ShortcutIntents, ShortcutCardIntents, LiveActivityIntents, LiveActivityCard, ExcusedRecord;
the old file keeps the "open shukr to …" intents).
Widget and app share `UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")`.

## Team (owner 2026-10-15: lean, fast, accurate)

**Who:** Izhan (owner) decides and tests. He gives the builders — Frank (organizer), Sami, Zoe (design; builds
when he says) — one task each and they work in parallel, any area; Bradley takes his dumps (/dump), Fable reviews and
builds patches that Frank checks and pushes. Frank works in `shukrGit/shukr`, Sami in `shukrGit/shukr-watch`, Bradley in `shukrGit/shukr-bradley`, Zoe (design)
in `shukrGit/shukr-zoe`, Fable in `shukrGit/shukr-fable`: one top-level folder each, never a worktree inside another's
(owner, 2026-10-19).

**Ask him first** (one line + the options, pictures for looks, your pick): design choices, new features, TestFlight
uploads, SwiftData schema changes, anything destructive or shared in git (force push, deleting branches, `main` — frozen).
Everything else goes ahead without asking: work that's exactly what he described, fixes that restore agreed behaviour,
internal tooling and notes.

**Git:** one team line, `claude/tasbeeh-zikr-updates`. Before every push `git pull --rebase origin
claude/tasbeeh-zikr-updates`; push with `git push origin HEAD:claude/tasbeeh-zikr-updates`. Small, frequent commits.
**Every commit message starts with your name** ("Frank: …") and says what changed, his words when they define the
behaviour, and "tried X, dropped because Y" when something goes — with `git log`, that's the record of who did what.
WhatsNew.jsonl merges by itself (merge=union).

**Install** when an item is ready for him to test, or when he asks — not after every push (owner, 2026-10-17: "I don't
necessarily need it every time … that way it saves time"). `zsh scripts/install.sh both` builds from origin (everyone's
work is in it); run it in the background so the chat stays free. A phone that can't be reached (CoreDeviceError 4016) is
normal — they're often out of the house: one line saying so, no retry loop; the next install catches it up.

**The Plan page** (https://shukr-board.vercel.app — the only part of the board he uses; the Stop hook publishes it):
an item he names → whoever takes it runs `board/idea.sh add` (if it isn't there) and `board/queue.sh start <id>`, then
`queue.sh done <id> <hash>` after the push. An idea he parks for later: `idea.sh dump` with his words. No decide.sh,
verdict.sh, review rounds or health digests.

**Checks sized to the change.** The builder checks the logic. Copy and small looks: the build + one small screenshot.
Data, flows, gestures: test by real taps in every state, not only demo flags. A second look from another engineer on a
risky data / flow change is a request, not a round. Only a real bug (a crash, lost data, something wrong he'd notice)
stops the next item.

**Design: the guide first** (owner 2026-10-15). Before any mockup or new view, read `docs/design-language.md` (findings +
vocabulary, screenshots in `shukrGit/board/mocks/design-library/`) and describe the design in its words ("one hero in a
ring, a flat list, sage only on what you tap"). Mockups: a change to an existing page goes in the real views (never a hand-made copy); artifacts for storyboards — the guide's "How we mock up". When he approves a design that adds a pattern, whoever built it adds a
line + a screenshot to the guide in the same commit, so it never goes stale.

**Between sessions:** the hash, the facts, what's wanted — short. Engineers talk to each other directly about merges and
installs.

**Chapters and the status block** (owner, 2026-10-17: so he can tell where a chat stands; "I don't want this to bog
down the system … I don't want it in every single reply"). Mark a chapter (`mark_chapter`) only when the main task changes,
titled "Feature: task" ("Prayer scores: flying title"). Only when an item is pushed or ready for him to test — or when he
asks for "status" — the reply ends, under the write-up, with this block **as a table** (plain text gets missed — owner,
2026-10-17; it replaces a separate "To check" list). One row per line, nothing stacked in a cell:
```
### Status <n>.<m> · <Area> › <Page>
| | |
|---|---|
| **Ask** | <the main ask, summed up in one short, clear line> |
| | *ctrl-F: "<the opening words of our reply he answered>" → "<his words, if they're searchable>"* |
| ✓ | ~~<a small edit he added along the way, done>~~ |
| ◻︎ | <a small edit not done yet> |
| **Still open** | <agreed in the spec, not built yet> (one row each; "Nothing" when done) |
| **To check** | <his 13 Pro Max or the sim> — <what to do>: <what should happen> |
| | <the next check> |
```
`<n>` = the main task's number in this chat, `<m>` = this block's count on it (2.1, 2.2 …; a new main task → a new
chapter and 3.1). The heading is there so he can Ctrl+F it; so is the Ask's second row (owner, 2026-10-18: "a summarized
and clearer concise main ask with a ctrlf reference for myself to go find it"): the first words of our reply he was
answering, copied exactly, then a distinctive stretch of his own words, unchanged — left out when they'd find nothing
(a lone "A", "yes", a button). No timestamp: agents can't see when he sent it (owner, 2026-10-19: "make it the beginning
text of your message, so I can find it from that at least, along with my response, if my response is acc good").

**Context:** state lives in files (this file, `docs/features/`, the board, memory), so a fresh start loses nothing.
Compact or start fresh at an item boundary (after commit + push); first overwrite `shukrGit/board/handoff-<name>.md`
(≤ 20 lines: now, next, half-done, traps). Your role's own rules live in `shukrGit/board/roles/<name>.md` (only ever
edited line by line, never overwritten; shared memory holds only rules for every agent — owner, 2026-10-19). A hook
(`board/role-hook.py`) shows you your role file at every start and after a compaction — by your folder, or in
`shukrGit/shukr` by the name you register (`zsh board/agent.sh register <name>`, so register first). On every start and
after a compaction, re-read this file and your handoff from disk, and open your next reply with "Compacted — picked up from <handoff>" (owner, 2026-10-17: he couldn't tell it had happened).
A hook (`board/context-hook.py`, in ~/.claude/settings.json) measures the chat's real context and tells you once at
60, 70, 80 and 90 % of 1M (it compacts itself at ~967k): at the next item boundary offer him close-out + a compact, once
— never stop mid-item for it (owner, 2026-10-19: "if context is getting high the agents suggest to close out and compact").

**This file stays ≤ ~35 KB:** rules, traps and an index. Feature detail lives in `docs/features/<area>.md` — read only
the area you're working in. When you change a feature, replace its lines there: current behaviour only, ≤ ~15 lines a
feature; the story goes in the commit message, the why in a code comment. Full pre-trim file:
`docs/history/claude-md-2026-10-15.md`.

**Cost:** the strongest model writes app code; cheaper sub-agents only for read-only searches and board tooling. Read by
line range, grep with `head`; screenshots small, only to judge a look.

## What's new — the team's picture record

He doesn't use the page; it's for us: what changed and why, with pictures, so anyone can look up another's change without
rebuilding it in the sim. DEBUG builds only (`testflight.sh` leaves the log and `shukr/WhatsNewShots/` out of every
upload). Written only by `scripts/whatsnew.py`; the page and tool in full: `docs/features/whats-new.md`.
- **One entry per thing he'd recognise** — a feature sprint or a one-off fix; never for a state he threw away; none for
  invisible changes. During a sprint: commits only.
- Written when the first build of it goes to his phone (or at the sprint's end if none did). Each later install round
  replaces it: `add` a fresh one with the same `--ask`, then `status --entry <old> --set replaced` (committed entries
  can't be edited); the new one carries the old one's "Tried and dropped:" line and any words he added since.
- Lean (owner, 2026-10-17: "we can keep it lean"): skip it when another session's entry already covers the item; a shot only
  if one was taken while testing (`whatsnew.py shot <png> <name>`) — never relaunch a sim just for the picture. It holds: how it works in 2–3 lines (`--title`); a
  `--try`; `--ask <slug> --ask-words "<his words, verbatim>"`; "Tried and dropped: …" and what was / wasn't checked in
  `--notes`. A new feature adds `--area <one of AREAS> --topic-title …`.
- Wrapping up an item = the entry matches what's on his phone → commit → push → `queue.sh done`.

## Build, install, ship

- **ASC API key** (all signing / uploads; no Xcode sign-in): ID `6K2RUXRJ92`, issuer `60a885ac-0315-4323-974d-57783a7392a2`, file `~/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8`. Never read it out, print it or commit it; scripts only pass its path.
- **Device build:** `zsh scripts/install.sh` does it all for his phones (from origin, with the key and the stamp). A
  build by hand (the watch, a one-off) adds `-allowProvisioningUpdates -authenticationKeyPath <that file> -authenticationKeyID 6K2RUXRJ92 -authenticationKeyIssuerID <issuer>` and `SHUKR_BUILD_STAMP="$(git rev-parse --short HEAD)"` (add "+" if dirty; commit first so the hash is real; it feeds `BuildInfo.line`, the stamp at the bottom of ☰ / Settings, and the watch's `WatchBuildInfo.line` at the bottom of its Settings — shukrWatchInfo.plist has the same `ShukrBuildStamp` key).
- **Phones:** 13 Pro Max `00008110-001C041C2203801E`; 15 Pro `00008130-00027DDE0AE8001C` (often unavailable). A hand install: `xcrun devicectl device install app --device <udid> <path>.app`. CoreDeviceError 4016 = the phone is away or locked: say so, move on.
- **His phones get Debug (dev) builds, always `install.sh`** (owner, 2026-10-19: "dev builds are easier so that when we're testing features, we have all the different tests in there. And the agents can tap into my phone easier"): My Dev Stuff, What's new and the logs we pull stay on. **Release only when he asks** ("I'll ask for it if I want release build"; `CONFIG=Release zsh scripts/install.sh me`). A bug that may be Release-only (on iOS 26.6 dead Settings rows were): say so and let him choose.
- **TestFlight** (only after Izhan says go; Frank confirms first): `scripts/testflight.sh` bumps `CURRENT_PROJECT_VERSION` (12 places), archives Release with the watch, uploads (system PATH: Homebrew rsync breaks export), records the build (`whatsnew.py build`); commit the bump. Notes: `whatsnew.py testflight --since last` → `TestFlightNotes-<ver>.<build>.md` with a "What to Test (paste this)" block, **≤ 4000 chars, no emoji** (Apple rejects non-BMP). `scripts/asc.py builds` → VALID; `scripts/asc.py release <build> <notes.txt>` sets What to Test, adds every external group ("test" = public link https://testflight.apple.com/join/GW5j85jk), submits for beta review (`IN_BETA_TESTING` = testers have it). App id `6743040873`, team `7R387XZ2Y7`.
- **App Store archive:** `SHUKR_APPSTORE=1 scripts/testflight.sh` leaves out the What's new shots; check `ls build/shukr-*.xcarchive/Products/Applications/shukr.app | grep -c wn-` → 0.
- **"Push to TestFlight" = share by link (owner, 2026-10-17):** "i just mean i want it so i can share the newest version of our stuff to more people with a link … external group and internal group is fine … As long as it doesnt bog down." Upload, then `asc.py release <n> <notes>` (every group; the public links stay the same). No internal-only stop: both phones and her watch run dev builds. One lean run; Apple's beta review is the only wait.
- Latest: 2.0 (23) from be7d924, 2026-10-10, to everyone (after Sami's onboarding go): groups "test" (https://testflight.apple.com/join/GW5j85jk) and "Everyone" (https://testflight.apple.com/join/ws2MUvWN; `asc.py newgroup`), notes TestFlightNotes-2.0.23.md.

## Architecture rules and traps

**Design language — read before designing any new view:** (no sage on the Salah page — owner 2026-10-15) `docs/design-language.md` (12 findings + vocabulary, from the
24 pages in `shukrGit/board/mocks/design-library/`). In short: one hero per screen, often in a ring; the soft look raises
heroes and block cards only (lists stay flat); light type with a grey line; sage = tap; one soft pill + one quiet line;
frost, don't scold; show the real thing; "streak", never "run". Data-heavy pages: its "The gap" section.

**UI wording.** Every look picker (app, Live Activity card, Prayers widget, setup, the ⓘ, the watch) says System · Light · Dark · **Sun** in that order (System only in Settings; the watch has iPhone), and Sun is explained in one sentence: "Light after Fajr, dark at Maghrib." (owner, 2026-10-12). Users read "zikr" / "Azkar", never "mantra"; code and SwiftData names keep `Mantra` (a model rename is a schema risk).

**Navigation / pager**
- `horizontalPage` = pager page: Zikr · Salah · **Settings** (owner 2026-10-19: Journey was the right page 2026-10-17 → 19, "I'm not a fan of having Journey there"; Journey is pushed from ☰ only, `JourneyPresenter.open`); the bottom bar is Zikr · Salah · Settings; `SettingsPresenter.show(jump:)` pages there (a jump once it rests). `navPosition` = the centre page's vertical state only (.main / .bottom); paging never changes it.
- Pager = native paging ScrollView. `scrollPage` is written only from `onChange(horizontalPage)` while idle; the geometry handler ignores reports while `contentSize.width < 2.5 × width`. Don't turn off bounce. The feel (owner 2026-10-19): the Salah page anchored — `SalahPageAnchor` moves it 30 % of the drag and fades it out by 45 %, the side page comes in over nothing (a solid side page over it cut a hard edge through the ring); toward Settings the chrome fades in place (`ChromeLeaves`), as toward Zikr; past either end heavy resistance (`PagerStretch.extra` −0.7 — 1.8× was "woah woah"). All three are visual effects: no body reads them.
- **Never `minimumDistance: 0` on the pager's drag** (it cancelled Settings row taps on iOS 26). Vertical gesture starts at 5 pt, locks the axis at 6 pt (`live.pagerLocked`). The salah sheet pops on a swipe; the finger never drags it. A pull down on the closed Salah page opens ☰ (`SalahSheetDrag.openMenu`; it
  used to refresh the location — that's in Settings now, owner).
- Per-frame values live in `PagerLiveState` (@Observable); PrayerTimesView's body must read none. The top bar's two titles (TopBar, `ZikrPageTitle`) are both mounted and pushed by `zikrness` offsets (`titlePush`), never rebuilt per frame.
- Anything presented over the Salah page that `somethingCovers` can't see registers as a `CircleCover`. Widget / control opens go through `clearCovers(then:)`; a tasbeeh session is never closed by one.
- Root holds `sharedState` as `@State` and injects it with `.environment(sharedState)`; `SharedStateClass` is `@Observable` (2026-10-04): read it with `@Environment(SharedStateClass.self)`, a binding needs `@Bindable`, and a view re-renders only for the properties its body reads (one-shot flags like `quietPageChange` / `resumeCount` are `@ObservationIgnored`). No `@Query` with `#Predicate { builtInID == nil }` on the Azkar / History pages (100 % CPU loop): fetch all, filter in memory.
- The zikr wheel must not be a LazyVStack. A nav bar must never change height (trailing slot always holds a button; Azkar's sort button is a fixed `AzkarSortButton.width`).

- Prayer list rows have ONE gesture (`PrayerButton.rowGesture`): don't go back to `onTapGesture` + a simultaneous long press, and the mark area stays the 22 pt circle round the dot (not the name or a full-height box).
- A task counts only its own linked sessions; freestyle and post-salah never touch tasks. Watch sessions retry by UUID, never double-counted.

**Excused days (counted days).** Anything that counts prayers (streaks, scores, Insights, day history, task streaks,
a new stat) reads its days through `Excused.counts(day:)` / skips `Excused.excludesDay`, and anything that marks or plans
a prayer checks `Excused.covers(start:end:)` (Excused.swift). Read `Excused.ranges` once per loop.

**Re-render hygiene**
- Never create a publisher / Timer inline in `body` (froze the ring): `static let ticker`.
- `PrayerViewModel` is `@Observable` (2026-10-19, cleanup step 8): read it with `@Environment(PrayerViewModel.self)`, bind with `Bindable(viewModel)`. Its saved settings are computed over UserDefaults (same keys; no `@AppStorage` in it). A view redraws only for what its body reads, so every holder reads `viewModel.revision`; after changing data that isn't observable on its own (rows rescored, statics like DayHistory), call `contentChanged()`, never a bare mutation and hope.
- Heading / qibla live in `CompassState` (never on `EnvLocationManager`, which the root holds — 4789a97, the picker flicker),
  published only on change; the circle's arrow is its own view (`QiblaArrow`). The heading (LocMans.swift, compass audit
  2026-09-30): Core Motion's fused heading (true north with location, magnetic without), Core Location's as the fallback;
  restarted on every didBecomeActive and by a 1 s watchdog when quiet; smoothed; `qibla.heading` −180…180; aligned with
  hysteresis, never without a place or with an untrustworthy heading (`CompassStatus`; the arrow is dashed then).
  Calibration (CompassCalibration.swift): iOS's own screen is OFF (apps can't open it — owner); after ~3 s untrustworthy
  `CompassHealth.needsCalibration` (publishes only on flips) shows "Compass needs calibration · tap" under the circle (laid out
  at zero size: the ring never moves), a red dot on ☰ + a "Calibrate compass" row → `CompassCalibrationSheet` (a full page: it's the
  iPhone's compass, not shukr; figure 8, magnets, live status, closes itself when good). DEBUG `-demoCompassUnreliable [-demoCompassRecover s]`,
  `-demoCalibrationSheet`, `-demoMenuOpen`; the phone keeps Library/Caches/compass.log (DEBUG builds). DEBUG Settings → My Dev Stuff →
  Compass debug, `-demoCompassJiggle [-demoCompassSweep]`. `userLocation` isn't published. Every app-group write, even the same value, invalidates bound `@AppStorage`: write only on change.
- No `GeometryReader` in the welcome overlay (blank app). Decode images off the main thread, never in `body`.
- A hole cut with `.contentShape(path, eoFill: true)` must be a plain rect: SwiftUI's hit test reads a small curved hole
  (a 26 pt rounded rect, an ellipse) as solid (`TourInputGuard`'s openings; the tour's undo dot was dead at 402 pt).

**Shared store & widget**
- One store: `SharedStore` (SharedStore.swift, both targets), `<group>/shukr.store`. **Only the app creates or migrates it**; `widgetContainer` opens it only if it exists at the current version.
- Widget / notification / watch marks: `SharedStore.markPrayerComplete` → `widgetWroteStore`; the app reconciles on activation (`reconcileAfterWidgetWrites`). Timelines use `entry.date`, never `Date()`; few entries; the app reloads on change.
- **Mark rules** (mark audit, 2026-10-18; `shukrGit/board/mark-invariants.md`): a NEW write path sets `widgetWroteStore` (+ `markedDayKey` = the prayer day's start) or the app never sees it; the reconcile rescores yesterday + today and clears `DayHistory`. A mark needs the ROW's start passed; an unmark never checks the start. An unmark resets every completed row of that name on that prayer day. After a mark / unmark from anywhere: `PrayerLiveActivities.plan`; an unmark also `NotificationScheduler.topUp`. Salvage / import / restore pair rows by `name|dayKey`.
- `shukrWidget/` isn't a synchronized group: add files to the pbxproj by hand — a file the app uses too goes in BOTH Sources (the app's and shukrWidgetExtension's), and build both schemes: a name clash breaks only the widget. PrayersWidget.swift, MoreWidgets.swift and AppIntent.swift are in the APP target too (Explore's real widgets, `RealPrayersWidget` / `RealZikrWidget`): no name may clash with the app's (the widget's TaskRow became `ZikrWidgetTaskRow`), and any intent added there needs `isDiscoverable = false` or it shows in Shortcuts. Outside a real widget the views get no family / container background: give them a frame + background, and `.allowsHitTesting(false)` (their buttons would really run). Long `Text(a + (b.map{…} ?? ""))` stalls the widget type checker: use helper functions. Don't re-add `NSWidgetWantsLocation`. Changing an intent parameter's type under the same name leaves stale saved values: rename it. Check the live ring on a placed widget (DEBUG shots draw a static arc). **Live Activity size:** iOS kills a card whose archive passes ~2 MB (island phones count the island too); after any change to the card's views, measure a card at its window's start on an island sim (reminders.md, "The card's size").

**Schema & migrations**
- No `SchemaMigrationPlan` (a staged plan died on iOS 27): lightweight inferred migration. Next change: stay lightweight, never reuse a name another property claims via `originalName`, bump `ShukrSchemaV2.versionIdentifier` (the widget compares it), extend `runV2DataPass` if rows need touching, test on the newest iOS. Schema changes need Izhan's OK. Now 2.8.0 (`PrayerModel.prayerDayKey`, the prayer day as "YYYY-MM-DD"; every day lookup goes through `PrayerDay.rowsPredicate` / `row.dayKey`, never the calendar day of `startTime`).
- `makeContainer` backs the store up first (`Library/Backups/shukr.store.before-<v>`). An unopenable store is set aside, never deleted (`recoverFromUnopenableStore`).
- Built-ins: `isBuiltIn = builtInID != nil`, tagged by exact seeded names; compare zikr names with `BuiltInAzkar.key`; no delete.
- Delete zikr / task only via `MantraModel.delete(_:in:)` / `TaskModel.delete(_:in:)` (a task left behind makes the data pass recreate its zikr; dismiss the page first). Sessions: `SessionDeletion.delete`.
- Day scores and anything keyed by a day take the PRAYER day: `row.dayStart` / `PrayerDay.start(forRow:startingAt:)`, never `startOfDay(startTime)` (an Isha after midnight is the day before's); `calculateDayScore(for:)` takes a time on that day's date. `DailyPrayerScore` (bare-Date keys, shift with the zone) is read only by Your Data's export: new readers read rows.
- Prayer rows: never `fetchLimit = 5`; one row per name via `onePerPrayer`, a completed row wins. Old rows store "Early" / "On time" / "Late": UI reads `gradeWord`; the grade words live only in `PrayerScoring.Grade` (+ the watch's `WatchScoring.word`).

**Notifications & location**
- Everything scheduled goes through `NotificationScheduler` (64 budget): diff, remove only owned ids, never `removeAllPending…`. Action handlers call `completionHandler` from inside `UNUserNotificationCenter.add`'s callback.
- The chain (audit B, 2026-10-04): a fetch reloads `todaysPrayers` when rows changed or the day turned and re-plans the rollover timer; a still phone geocodes / re-plans at most every 10 min (500 m at once) and keeps its city on a failed lookup; the scheduler adds before it removes, under a background-task assertion; a time / zone change re-fetches (`resetSystemTimeZone` first). Every outside mark sets `markedDayKey` (the app rescores that day); a banner mark with the app in front posts `SharedStore.markedElsewhere`.
- No hard gate on notifications or location (App Review 4.5.4 / 5.1.1); Always is opt-in; `EnvLocationManager` doesn't ask before setup is done. CLMonitor names: letters only, one monitor per name per process.

**Map**
- UIKit `MKMapView` on purpose (clustering). The qibla is the computed geodesic line, right whatever the compass. `setMode` turns north first, locks rotation 0.6 s later. Sheet detents follow the mode ("up through .medium" silently disables without a .medium detent). Count our own pins in `visibleMapRect` (`annotations(in:)` double-counts).
- Mosque search: `regionPriority = .required`, ≥ 5 km; MKLocalSearch / MKDirections are rate-limited. No group filters by sect. Don't chase the map hang in the iOS 26.5 sim.

**Audio / media**
- Audio session and recorder / player setup run on the serial audio queue (`setActive(true)` froze the sim). One engine app-wide (`takeOver`); the card owns the one `ZikrAudio`; every recording end goes through `finishRecording()`; sheet close → `ZikrAudio.stopAll()`; temp .m4a removed on every exit path.
- Zikr card notes / memo / photo = ONE fixed-height box with `switch pane`, never stacked hidden layers; in Save / Cancel editors media wait in drafts.

**Simulator & testing**
- **Start every sim test with `zsh scripts/sim-ready.sh <YourName> [--app <…/Debug-iphonesimulator/shukr.app>] [--page salah|zikr|journey|settings] [--data latest] [--fresh] [-- <more args>]`** (owner, 2026-10-20: agents "get stuck on very silly simulator issues … he couldnt get past the notification screen"). It finds or makes "<Name> – iPhone 17 Pro" (newest iOS), boots it, installs, allows + sets location, can load his data (`~/Library/Application Support/shukr-team/izhan-data-copies/`, README there — copy, never edit), launches with `-demoLand` (twice when the first launch may miss the args) and takes a screenshot. **Look at that screenshot before anything else.** A system alert keeps the app inactive, so code that runs on becoming active silently never runs — it looks exactly like a code bug: `--fresh` (erase) clears a stuck one. Name the udid it prints in every later sim command, never "booted" (five or six sessions share this Mac; a stray tap once landed on another engineer's sim). Use a build from today: an old one has old bugs.
- `-demoLand` (owner, 2026-10-18: "skip this whole intro and opening animation so we can land straight to the salah tab"): no welcome, opening, setup, permission prompts, tour or zikr lock (`-zikrLocked` keeps it); the real app on its own data, fully usable, for that one launch only (from the Home Screen it's the plain app). Not `-demoMarkAll` / `-demoMarkMixed` (they seed marks). A plain launch (no `-demo…`) of a set-up install asks for
notifications; while iOS's alert is up the app stays inactive (a reopen runs no reload) and simulated taps can't answer
it — launch with a `-demo…` arg (they never ask), or erase your sim. On his phone too, demo args miss on the first launch after an install (devicectl: LaunchServicesDataMismatch): a plain launch first. A simulated tap right after a launch or a screen change is often dropped: retry once before debugging. A simulated tap doesn't flip a Toggle: drag its knob. SF Symbol names: check they exist in `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (`symbols`) — a made-up name draws nothing.
- **The circle system** (decision circle-system A, 2026-10-02; rules and owners: `shukrGit/board/circle-system.md`): MainCircleView owns every moment (CircleMoments.swift — morning, lost and the opening are circle states); the look is one value, `@Environment(\.circleTheme)` (CircleTheme.swift; `CircleTheme.standard` = everyone's default, `.today`) — never the SalahLook keys; timings only from CircleMotion.swift; out, then in (fades eased out; a ring faded over another gets `.compositingGroup()`). Only a change to a circle moment or its motion (CircleMoments.swift, CircleMotion.swift, mainCircle.swift's moment runner — run / playMarking / the swaps — or a new animation on the Salah circle) runs `scripts/circle-check.sh`: `shots <parent>` (4 states: the public look, dark + light, Salah + list, against the .app you built; ~2–3 min warm) and `strip <moment>` (one-frame jumps); copy, colors and small looks get the build + one screenshot ("Checks sized to the change"; owner 2026-10-17: "I think it was a little bit OD"). The app's clock runs from `--clock` (fakeclock.c); simulators only.
- **My Dev Stuff** (Settings → tap "Sneak Peek…"; owner 2026-10-15): recent rows on top by area (Salah page · Setup, Zikr & Explore · Live Activities & notifications), the rest folded under Dev · Older; every existing row sage (`.tint` + `.accentColor`) — add a NEW row with no tint so it shows blue; move it into an area once it's settled.
- Simulated taps miss Menus and segmented controls (use DEBUG args or the app's own prefs; `simctl defaults write` leaves a plist the app can't clear). Any `-demo…` arg skips welcome / prompts / setup. Not testable in the sim: mic, camera, haptics, BGTask, significant-change.

## Features — index (detail: `docs/features/<area>.md`; read the area you're working in)

- **salah.md** — Salah circle & prayer list (mainCircle.swift, PrayerListLooks.swift: the ring fills with the window in
  the score's colour; marking, the raised list = the public look, the marked row's buttons; the day's page — DayRing,
  DayInsight; the list's drag and motion rules). Scoring, streaks, prayer day (PrayerScoring.swift, PrayerDay.swift:
  Perfect 100 · Middle 99–80 · Closing 79–60 · Qaza 40 · Missed 0; the day turns at Fajr). Excused Mode (Excused.swift).
- **memories-journey.md** — Prayer photos (PrayerPhotos.swift: front + back after a mark, files only, developing, an
  unmark deletes the photo), Memories (PrayerMemories.swift: levels, the deck's zoom, day strip, search), Journey
  (Journey*.swift).
- **reminders.md** — Notifications (NotificationScheduler.swift: the 64-slot plan, wording, AutoTopUp + topups.log, the
  three "Your …" pages), Prayer Live Activities (iOS 26+: the card, LATuning, the island), Fajr alarm (AlarmKit on
  26.1+, else the Shortcut).
- **setup-tour.md** — First-run setup (FirstRunSetup.swift: hadith → steps → review → bismillah → opening; Skip = the
  next step; the permission pages' frost), lost location, the App tour (Tour.swift).
- **map-mosques.md** — Map & qibla (UIKit MKMapView, one sheet, the Explore dock), mosques, My masajid, masjid-aware
  prayers (MasjidDetector, Jumu'ah, arrival duas).
- **widgets-shortcuts.md** — Widgets (Prayers, Lock Screen, Zikr, Name, Ayah, Control Center), Shortcuts & Siri (ten
  tiles in sections, iOS 26 cards, place shortcuts, Zikr Tasks).
- **watch.md** — Apple Watch (pages, the ring, the marking outbox, tap & pinch / Crown counting, qibla map, look).
- **zikr.md** — Tasbeeh session (tasbeehView.swift: goals, the pause screen, sleep mode + the morning card, Tasbih
  Fatimah), the Zikr tab (Your azkar, a zikr's page, History; pause; the new-goal flow), task streaks, the zikr card.
- **more.md** — Explore shukr (real widgets and cards on one preset day), Give to Causes (Sadaqah.swift), Your Data +
  iCloud Backup, Daily Ayah, 99 Names, the welcome.
- **whats-new.md** — the What's new page and `whatsnew.py` in full.

## Open items

**Needs a real device:** Fajr rollover (yesterday's prayers up until Fajr) and the 15 Pro's first V2 launch (`✅ schema V2 data pass`, no ❌); the Always upgrade prompt (once); travel updates and background relaunch; the Shortcut alarm description; a real Jumu'ah at a masjid and the arrival dua with the app killed; nudge cancel from the widget extension; mic / camera; paging lag re-measure (Release); the watch list under Apple Watch; real Summary / Time Sensitive / Background App Refresh settings.

**Backlog:** Infinity button → user step; dead code Part 2 (`shukrGit/board/cleanup-map.md`: Part 1 done 2026-10-18 — what's left needs PrayerTimesAndTracker.swift or a call from Izhan); "How scoring works" card; Umrah companion and personalised 99 Names duas (plan first; the owner has the prompt, don't invent one); post-salah "points" (a separate layer, never in the prayer score).

**Share card:** `AyahShareCard.footer` says "download on the App Store" (owner 2026-10-15, no link).

**Privacy manifests** (shukr/ and shukrWatch/ PrivacyInfo.xcprivacy; the widget's has UserDefaults only): UserDefaults, FileTimestamp (C617.1), SystemBootTime (35F9.1). A new required-reason API (disk space, keyboards, …) gets its reason there first.

**App Store:** No live `fatalError` left in app / widget / watch (0e28574). In App Store Connect: privacy policy URL, support URL, App Privacy label (precise location, on-device), screenshots 6.9" / 6.5", description / keywords / category / age rating, content-rights docs for `quran.sqlite`, `english_hilali.sqlite` (KFGQPC) and `KFGQPCUthmanTahaNaskh.ttf`.

**⚠️ The hadith sources and the four Tasbih Fatimah reminders were written from memory** (built-in azkar notes too), and so was Give to Causes' "Kinds of giving" (`GivingGuideSheet`); they need a knowledgeable check before release.

## Feature list (for the App Store listing)

`docs/app-store-features.md`: what shukr does, meatiest first — the source for the description, keywords, "What's New"
and screenshot captions. Keep it current when a feature ships or changes.
