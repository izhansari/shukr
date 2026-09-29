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

## Team protocol (owner-approved 2026-09-29; read this first)

**Who:** Izhan (owner) decides and tests. Bradley plans and reviews: he keeps the backlog, the queue and the board,
and is Izhan's single inbox. Frank builds the phone app. Sami builds the watch and widgets, and takes phone items
Bradley splits off. Everyone signs messages with their name and a timing line ("now" only if urgent).

**What needs Izhan** (ask, with pictures for looks, and wait): design choices, new features, TestFlight uploads,
SwiftData schema changes, and anything destructive or shared in git (force push, deleting branches, touching `main`,
which stays frozen). **Everything else goes ahead without asking:** work that's exactly what he described, fixes that
restore agreed behaviour, review fix-ups that don't change what he sees, and internal tooling / notes.

**Flow of an item:**
1. His words (chat or the app) → Bradley makes an ask (a slug plus his words) and queues it.
2. Each engineer holds two briefed items: the current one and the next. Starting the next one needs no "go".
3. Build → a What's new entry (`whatsnew.py add … --ask <slug>`) → commit → push to the team line.
4. Install on his phone only right after pulling the team line, so every build has everyone's work.
5. Message Bradley only when done (the hash, what was and wasn't checked) or blocked.
6. Bradley reviews after it lands. Only a real bug (a crash, lost data, something wrong he'd notice) stops the next
   item; nits ride along with a later one.
7. Izhan gets one update per round (a round = a new build on his phone): what's on it, what to try, decisions batched.

**Git:** one team line, `claude/tasbeeh-zikr-updates`.
- Frank works in `shukrGit/shukr`, Sami in `shukrGit/shukr-watch` (his own branch name, pushing to the team line).
- Before every push: `git pull --rebase origin claude/tasbeeh-zikr-updates`. Push with `git push origin HEAD:claude/tasbeeh-zikr-updates`.
- WhatsNew.jsonl merges by itself (merge=union).
- Small, frequent commits; no hold messages (a message lands at the other session's next pause, too late to stop a
  push). Frank and Sami talk to each other directly about merges and installs, copying Bradley.

**Cost:** planning, review and design choices on the strongest model. Mechanical edits, conversions and bulk
plumbing go to a cheaper sub-agent (Sonnet), spec'd and then checked. Keep this file current and short: history
goes to `docs/`, not here.

**Context (sessions fill up; owner, 2026-09-29):**
- State lives in files (this file, the board, `shukr-ideas.md`, `WhatsNew.jsonl`, memory), so a fresh start loses nothing.
- **This file stays under ~35 KB**: current rules, traps and each feature's current state. When you change a feature,
  replace its lines here; don't append a dated story. History goes to `docs/history/` (the full pre-trim file is
  `docs/history/claude-md-2026-09-29.md`).
- Compact or start fresh **at an item boundary** (after commit + push), around 60–70 % full; never mid-item.
- First overwrite your handoff, `shukrGit/board/handoff-<name>.md`, in ≤ 20 lines: now, next, half-done, traps seen.
- Read by line range and grep with `head`; filter logs (`grep -E "error|BUILD"`), never dump them.
- Screenshots at small scale, and only to judge a look. Broad searches or big reads go to a sub-agent that returns
  only the answer.
- Messages between sessions: the hash, the facts and what's wanted, no narration. The reader's context pays for every
  word.


## What's new (v4, 2026-09-29) — every visible change gets an entry

The owner tests from **What's new** (tap the build line at the bottom of the ☰ menu or Settings). DEBUG builds always
show it; a TestFlight install only after he holds the build line for 3 s (testers never see it; App Store never).
v1–v3's rules and history: `docs/whats-new-history.md`.

**The page:** Your answers (a row at the top, ⌄ opens it: everything he's said until the team has read it, with Edit) ·
Your asks (things he asked for, built: picture, headline, "Look for", his words, **Works / Not yet**) · Every change
(the log by day, searchable; tap → the change: pictures, try it, his words and answer, comments, Open in shukr, the
feature's other changes). Notes carry words plus any number of photos (drawn on with PencilKit; the original is kept)
and videos (exported 960×540, ≤ 60 s).

**Areas (ask wn-areas):** every topic's `area` is one of `AREAS` in whatsnew.py = `WhatsNew.areaOrder` (Salah · Zikr ·
Apple Watch · Widgets · Map & Mosques · Insights · Daily Ayah · 99 Names · Reminders · Setup & Settings; `--area` only
takes these, `check` flags others, `areas-remap` moved the old ones once). Your asks is grouped by them (headers once
there are 2+ areas — sub-headings inside it, foldable, `whatsNew.foldedAreas`; a "By area ⇄ Newest first" toggle,
`whatsNew.asksByArea`, ask wn-asks-view); Every change has area chips (clipped ScrollView, never `scrollClipDisabled`) that combine with search.

**Ideas (ask wn-ideas):** `FeedbackItem.Kind.idea` (💡, "Idea"; an older build reads it as a comment) with an optional
`area`: on a change, "Comment or idea" → the composer's "About this change | New idea" (keeps `onEntry` = the card), or the
header's "New idea" (no card, an area picker). `Kind.isVerdict` (works / issue) is what counts as an answer — never an idea
or a comment. feedback.md: "## 💡 Idea — <area>" + "- From: `<change>` (<headline>)".

**Next build (ask wn-next-build):** `build` records in the change log (`whatsnew.py build --number N [--commit] [--time]`;
testflight.sh writes one after a confirmed upload; build 12 backfilled at 994ee5a). `WhatsNew.lastBuild` / `sinceLastBuild`
(live changes after its time — the same set as `whatsnew.py testflight --since last`). A "Next build · N changes" row
under Your answers → the list by area, "K of your asks in this build still need your answer" (tap → scrolls there), and
"I'm happy with this — ready for TestFlight" = a `.ship` note (commits = the change ids; "## 🚀 Ready for TestFlight" at
the top of feedback.md until picked up). Not a gate, nothing uploads: Frank still confirms with him before testflight.sh.

**The data:** `shukr/WhatsNew.jsonl`, JSON Lines, written only by `scripts/whatsnew.py` (never by hand):
topics (features), **asks** (his requests, verbatim), changes, chat verdicts. `.gitattributes` merges it with
`merge=union`, so branches appending lines don't conflict; `whatsnew.py check` flags a line a merge kept twice.
Screenshots: `shukr/WhatsNewShots/wn-*.jpg` (the folder is a synchronized group; ships in TestFlight builds,
left out of App Store ones by `SHUKR_APPSTORE=1`).

**Every commit that changes something he can see or feel adds a change in the same commit:**
1. Screenshot in the sim → `scripts/whatsnew.py shot <png> <name>` (≤ 600 px, 20–40 KB). One per change, fresh.
2. `scripts/whatsnew.py add --topic <id> --headline "<≤ 40 chars>" --title "<one line>" --try "…" [--try "…"]
   --shot wn-<name>.jpg [--ask <slug> [--ask-words "<his words>"] | --ask-note <feedback id>] [--notes "#17"]`
   - **--ask**: the ask this answers. Bradley's brief gives the slug and, for a new chat ask, his exact words
     (`--ask-words`, verbatim, typos kept). A fix for a note on the phone: `--ask-note <id>`. Several attempts at one
     ask use the same slug; only the newest waits for his answer (a new attempt reopens it).
   - A new feature: add `--area Zikr --topic-title "<≤ 60 chars>" [--topic-summary "…"] [--topic-link salah|zikr|…]`.
     Change a feature's title / summary / steps / link: `whatsnew.py topic --id …`.
   - Invisible changes (haptics, background): `--no-try`, no shot.
3. Commit. **No resolve step**: `add` stamps the time; ids get a random suffix, so branches can't clash.
- Not committed yet and wrong: `whatsnew.py edit --entry <id> …` / `drop --entry <id>`. Committed and undone later:
  `whatsnew.py status --entry <id> --set replaced|dropped` (greyed in history).
- He answers in chat instead of on the phone: Bradley queues it in `shukrGit/board/verdicts.jsonl`; the next `add`
  (or `whatsnew.py import-verdicts`) brings it in, and his phone closes the ask with the next install.

**The one rule** (`WhatsNew.status(of:)`): an ask is open until there's a Works / Not yet on its newest live change —
from the phone, from chat, or (once, at the first v4 launch) what v3 had already closed (`Migration`, keeps the old
keys; a fresh install starts with everything history). His answers live in the app group's `Library/Feedback/`
(feedback.json + feedback.md + photos/, videos included); `state.json` there lists each ask's state for Bradley.

**Feedback back:** `scripts/pull-feedback.sh` (dev installs only) mirrors each phone into `shukrGit/feedback/<phone>/`
(+ `<phone>.md`), copying only media it doesn't have, and writes received.json (`received` + `seen`) back so the app
shows "Bradley has it". Send on the page shares the .md and every file (TestFlight installs).

**Traps:** anything reading `FeedbackStore.shared` must not run inside `FeedbackStore.init` (its feedback.md write is
deferred a turn — a recursive dispatch_once crashed once). Never a horizontal ScrollView on the change page (BA0ECB7A).
Decode screenshots / thumbnails off the main thread. DEBUG args: `-demoWhatsNew`, `-demoWhatsNewChange <id>`,
`-demoWhatsNewTopic <id>`, `-demoWhatsNewPage said`, `-demoWhatsNewAnswers YES`, `-demoWhatsNewCompose <change id>`,
`-whatsNewDump` (each ask's state), `-whatsNewResetMigration`, `-demoWhatsNewAllOpen` (every ask open: screenshots), `-demoWhatsNewPage next` (Next build), `-demoWhatsNewIdea` / `-demoWhatsNewIdeaFrom <change id>`
(+ `-demoIdeaText`, `-demoIdeaArea`: menus / segmented controls don't take simulated taps).

**Other beta extras** (Your reminders' link, its Details and card previews) follow `WhatsNewAccess.beta`: DEBUG or any
TestFlight install. "Run setup again" and What's new follow `.available` (the owner only).

## Build, install, ship

- **ASC API key** (all signing / uploads; no Xcode sign-in): ID `6K2RUXRJ92`, issuer `60a885ac-0315-4323-974d-57783a7392a2`, file `~/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8`. Never read it out, print it or commit it; scripts only pass its path.
- **Device build:** add `-allowProvisioningUpdates -authenticationKeyPath <that file> -authenticationKeyID 6K2RUXRJ92 -authenticationKeyIssuerID <issuer>` and `SHUKR_BUILD_STAMP="$(git rev-parse --short HEAD)"` (add "+" if dirty; commit first so the hash is real; it feeds `BuildInfo.line`, the stamp at the bottom of ☰ / Settings).
- **Phones:** 13 Pro Max `00008110-001C041C2203801E`; 15 Pro `00008130-00027DDE0AE8001C` (often unavailable). Install: `xcrun devicectl device install app --device <udid> build/device/Build/Products/Debug-iphoneos/shukr.app`; retry on CoreDeviceError 4016. Install only right after pulling the team line.
- **Verify gesture fixes with a Release device install** (`-configuration Release` + devicectl): on iOS 26.6 dead Settings rows showed in Release only.
- **TestFlight** (only after Izhan says go; Frank confirms first): `scripts/testflight.sh` bumps `CURRENT_PROJECT_VERSION` (12 places), archives Release with the watch, uploads (system PATH: Homebrew rsync breaks export), checks the log for a real upload, records the build (`whatsnew.py build`); commit the bump. Notes: `whatsnew.py testflight --since last` → `TestFlightNotes-<ver>.<build>.md` with a "What to Test (paste this)" block, **≤ 4000 chars, no emoji** (Apple rejects non-BMP). `scripts/asc.py builds` → VALID (5–30 min); `scripts/asc.py release <build> <notes.txt>` sets What to Test, adds every external group ("test" = public link https://testflight.apple.com/join/GW5j85jk), submits for beta review (`IN_BETA_TESTING` = testers have it). `asc.py groups`, `asc.py GET /v1/...`. App id `6743040873`, team `7R387XZ2Y7`.
- **App Store archive:** `SHUKR_APPSTORE=1 scripts/testflight.sh` leaves out the What's new shots; check `ls build/shukr-*.xcarchive/Products/Applications/shukr.app | grep -c wn-` → 0.
- Latest: 2.0 (13) from 155615f, 2026-09-29; full list in docs/history.

## Architecture rules and traps

**UI wording.** Users read "zikr" / "Azkar", never "mantra"; code and SwiftData names keep `Mantra` (a model rename is a schema risk).

**Navigation / pager**
- `horizontalPage` = pager page; `navPosition` = the centre page's vertical state only (.main / .bottom); paging never changes it.
- Pager = native paging ScrollView. `scrollPage` is written only from `onChange(horizontalPage)` while idle; the geometry handler ignores reports while `contentSize.width < 2.5 × width`. Don't turn off bounce.
- **Never `minimumDistance: 0` on the pager's drag** (it cancelled Settings row taps on iOS 26). Vertical gesture starts at 5 pt, locks the axis at 6 pt (`live.pagerLocked`). The salah sheet pops on a swipe; the finger never drags it.
- Per-frame values live in `PagerLiveState` (@Observable); PrayerTimesView's body must read none.
- Anything presented over the Salah page that `somethingCovers` can't see registers as a `CircleCover`. Widget / control opens go through `clearCovers(then:)`; a tasbeeh session is never closed by one.
- Root holds `sharedState` as `@State`. `ZikrLibraryView` pages sit behind equatable `LibraryPage`, and no `@Query` with `#Predicate { builtInID == nil }` there (100 % CPU loop): fetch all, filter in memory.
- The zikr wheel must not be a LazyVStack. A nav bar must never change height (trailing slot always holds a button; the Azkar / History slot is 50 pt).

- Prayer list rows have ONE gesture (`PrayerButton.rowGesture`): don't go back to `onTapGesture` + a simultaneous long press, and the mark area stays the 22 pt circle round the dot (not the name or a full-height box).
- A task counts only its own linked sessions; freestyle and post-salah never touch tasks. Watch sessions retry by UUID, never double-counted.

**Re-render hygiene**
- Never create a publisher / Timer inline in `body` (froze the ring): `static let ticker`.
- Heading / qibla live in `CompassState`; `userLocation` isn't published. Every app-group write, even the same value, invalidates bound `@AppStorage`: write only on change.
- No `GeometryReader` in the welcome overlay (blank app). Decode images off the main thread, never in `body`.

**Shared store & widget**
- One store: `SharedStore` (SharedTargetForIntents.swift, both targets), `<group>/shukr.store`. **Only the app creates or migrates it**; `widgetContainer` opens it only if it exists at the current version.
- Widget / notification / watch marks: `SharedStore.markPrayerComplete` → `widgetWroteStore`; the app reconciles on activation (`reconcileAfterWidgetWrites`). Timelines use `entry.date`, never `Date()`; few entries; the app reloads on change.
- `shukrWidget/` isn't a synchronized group: add files to the pbxproj by hand. Long `Text(a + (b.map{…} ?? ""))` stalls the widget type checker: use helper functions. Don't re-add `NSWidgetWantsLocation`. Changing an intent parameter's type under the same name leaves stale saved values: rename it. Check the live ring on a placed widget (DEBUG shots draw a static arc).

**Schema & migrations**
- No `SchemaMigrationPlan` (a staged plan died on iOS 27): lightweight inferred migration. Next change: stay lightweight, never reuse a name another property claims via `originalName`, bump `ShukrSchemaV2.versionIdentifier` (the widget compares it), extend `runV2DataPass` if rows need touching, test on the newest iOS. Schema changes need Izhan's OK. Now 2.6.0.
- `makeContainer` backs the store up first (`Library/Backups/shukr.store.before-<v>`). An unopenable store is set aside, never deleted (`recoverFromUnopenableStore`).
- Built-ins: `isBuiltIn = builtInID != nil`, tagged by exact seeded names; compare zikr names with `BuiltInAzkar.key`; no delete.
- Delete zikr / task only via `MantraModel.delete(_:in:)` / `TaskModel.delete(_:in:)` (a task left behind makes the data pass recreate its zikr; dismiss the page first). Sessions: `SessionDeletion.delete`.
- Prayer rows: never `fetchLimit = 5`; one row per name via `onePerPrayer`, a completed row wins. Old rows store "Early": UI reads `gradeWord`.

**Notifications & location**
- Everything scheduled goes through `NotificationScheduler` (64 budget): diff, remove only owned ids, never `removeAllPending…`. Action handlers call `completionHandler` from inside `UNUserNotificationCenter.add`'s callback.
- No hard gate on notifications or location (App Review 4.5.4 / 5.1.1); Always is opt-in; `EnvLocationManager` doesn't ask before setup is done. CLMonitor names: letters only, one monitor per name per process.

**Map**
- UIKit `MKMapView` on purpose (clustering). The qibla is the computed geodesic line, right whatever the compass. `setMode` turns north first, locks rotation 0.6 s later. Sheet detents follow the mode ("up through .medium" silently disables without a .medium detent). Count our own pins in `visibleMapRect` (`annotations(in:)` double-counts).
- Mosque search: `regionPriority = .required`, ≥ 5 km; MKLocalSearch / MKDirections are rate-limited. No group filters by sect. Don't chase the map hang in the iOS 26.5 sim.

**Audio / media**
- Audio session and recorder / player setup run on the serial audio queue (`setActive(true)` froze the sim). One engine app-wide (`takeOver`); the card owns the one `ZikrAudio`; every recording end goes through `finishRecording()`; sheet close → `ZikrAudio.stopAll()`; temp .m4a removed on every exit path.
- Zikr card notes / memo / photo = ONE fixed-height box with `switch pane`, never stacked hidden layers; in Save / Cancel editors media wait in drafts.

**Simulator & testing**
- Simulated taps miss Menus and segmented controls (use DEBUG args or the app's own prefs; `simctl defaults write` leaves a plist the app can't clear). Any `-demo…` arg skips welcome / prompts / setup. Not testable in the sim: mic, camera, haptics, BGTask, significant-change.

## Features: current state

The archive `docs/history/claude-md-2026-09-29.md` holds the history and reasoning for every feature below.

**Salah circle & prayer list** (mainCircle.swift, PrayerCompletionFX.swift)
- The ring fills with the window, coloured by the score you'd get now; a tap flips "ends at" / time left. Not yet started: dashed `UpcomingTrack` + `NextTag`, solid at the start (`settleTrack`).
- Marking: haptic, `CompletionFlourish` (`heldPrayer`), done rows fold into "N done"; tap the dot's circle to mark, elsewhere flips the time, hold opens `PrayerTimeEditSheet` (local draft; recorded value kept, 2.3.0). `PostSalahNudge` (15 s ring) is the only post-salah prompt.
- DEBUG: `-demoPrayerStart [-demoPrayerStartThenMark]`, `-demoPrayerCompletion`.

**Scoring, streaks, prayer day** (Models/PrayerScoring.swift, PrayerDay.swift)
- One rule for app, widget, notification action and editor: Perfect (≤ 30 min) 100 · On time 99–80 · Late 79–60 · Qaza 40 · Missed 0; day = mean of five. Jumu'ah (Friday Dhuhr at a masjid) = 100, no grade word.
- Streaks: a day counts once; earlier days are recounted from rows (`refreshStreaksFromHistory`); "in-time days" = no Qaza (≥ 60); perfect day = five Perfect. The day turns at Fajr (`PrayerDay.fajr`; no location → 3 AM); Isha ends 11:59 PM; zikr sessions follow the day (`sessionDayStart()`).

**Notifications & reminders** (NotificationScheduler.swift, NotificationHealth.swift)
- ~7 days ahead: two full days (Start / Mid / End), then Start only; dated ids; defaults `NotificationDefaults`; a keep-alive slot; BGAppRefresh top-up. `ReminderHealthCard`. Actions: I already prayed, nudge 5 / 10.
- Your reminders (`YourRemindersView`, Settings → Notifications): 64-bead ring, week rings, three explainer tiles.

**First-run setup, location lost** (FirstRunSetup.swift)
- `SetupOpening` → location → method (Automatic = `AutoMethod`) → madhab → appearance → reminders → Fajr alarm → masjid → review (rows edit and return) → Bismillah hands off to `WelcomeOverlay`. Once per install (`firstRunSetup.v1`); Always location gives travel updates.
- `LostLocationView`: root overlay when location is revoked with no city; the comeback plays the welcome in reverse. DEBUG `-setupForce`, `-setupReset`, `-setupStep <step>`.

**Map & qibla** (LocationMapView2.swift, MapModes.swift)
- Opens qibla-up (`pointQiblaUp`), free rotation, the compass ring on the dot (`MapAnchor`), a heavy buzz each second while aligned, `MapNorthButton` home.
- Explore dock: Qibla · Prayers · Mosques; prayer pins cluster and open `PrayerSpotDetail` in the sheet (edit time, move spot with `PickPin`). DEBUG `-demoPrayerPins`.

**Mosques, My masajid, masjid-aware prayers** (MosqueFinder.swift, MasjidDetector.swift, PlaceMoments.swift)
- One persistent mosque sheet (`mosquePath`): nearest list, drive / walk, Look Around, Directions, Call, place card. `MosqueFavorites` (star pins), `MosqueHiding` (not recommended).
- `MasjidDetector` (75 m) sets `mosqueName` (2.2.0) → Jumu'ah; `MasjidArrival` duas (CLMonitor, opt-in); `HolyCityWelcome`.

**Widgets** (shukrWidget/, MoreWidgets.swift)
- Prayers (ring, mark check, times list, configurable corners), Lock Screen family, Zikr (rows open the task), Name of the Day, Daily Ayah (once revealed), Controls (Qibla, Tasbeeh). Kinds in `WidgetKinds`.

**Apple Watch** (shukrWatch/, shukrWatchShared/, WatchSync.swift, WatchZikrSync.swift)
- Pages Zikr ← Salah → Settings; the phone's ring; marking with Undo through an id'd outbox; qibla arrow (true north); zikr wheel and counter (Crown = one count per nudge, `WatchCrownGate`), two-page pause, `WatchHaptics`, Tasbih Fatimah; complications. No schema change; the watch never creates or edits tasks; `WatchScoring` mirrors `PrayerScoring`.
- Untried on a real watch: Double Tap, Crown, wrist-down runtime, outbox catch-up, compass, memo, complications. DEBUG `-demoWatch`.

**Fajr alarm** (FajrAlarmKit.swift; iOS 26.1+ AlarmKit, else the Shortcut)
- Same rule and keys (`alarmEnabled`, `alarmOffsetMinutes` 5-min steps, `alarmIsBefore`, `alarmIsFajr`). On 26.1+ the app sets
  one `.fixed` system alarm per day, up to 60 days ahead ("Fajr starts 5:37 AM", "I'm up — open Fajr" → `FajrAlarmOpenIntent`).
  `plan()` is a diff, run after every `NotificationScheduler` run, on Stop (`FajrAlarmStopIntent`) and "I'm up".
  `alarmKitActive` (app group) marks the mode; the old Shortcut's `SetFajrAlarmIntent` then throws `SetByShukrError`, so
  there's never a second alarm. iOS 18–26.0: the Shortcut path, unchanged.
- Unverified: whether AlarmKit alarms show in Clock's list; whether Stop's intent has time to re-plan on a real phone.

**Tasbeeh session** (tasbeehView.swift)
- Tap-anywhere counter; freestyle / time / count; count in sets (`quickAddStep`); pause screen (`ZikrBento`, silent-haptics chip, Resume big, Finish two taps); results; a task session links `SessionDataModel.task`, continue or start over (`resumeCount`). Tasbih Fatimah 33 · 33 · 34 is one session (`PostSalahTasbeeh`). DEBUG `-demoPauseScreen`.

**Zikr page, tasks, reminders** (DailyTasksView.swift, ZikrReminders.swift)
- `ZikrCircleWheel` (gentle arc, left dot scrubber); after a session the next task centres. Tasks: own name, count or minutes goal, estimates, a reminder per task (set in the task's edit screen). **Tasks** top right → `ZikrTasksSheet` (2026-09-29, ask zikr-tasks-sheet; replaced jiggle mode and the reminders page — both deleted, owner: "stop working on jiggle"): rows in the wheel's order (ring / ✓, "40 of 100" / "done" — no "today", the reminder line), hold-and-drag reorder (`.onMove`, no Edit mode; the ≡ is a hint), tap → `AddDailyTaskView(editing:)` pushed (its own ‹ is Back), swipe → confirm → `TaskModel.delete`; long-press a wheel task → the sheet on its editor (`startOn`). **Trap:** the swipe button must not be `role: .destructive` (the List expects the row gone and the confirm never shows) — `.tint(.red)`. DEBUG `-demoZikrPage`, `-demoZikrTasks`, `-demoZikrTasksSeed`, `-demoZikrTasksEdit N`, `-demoZikrTasksDelete N`.

**Azkar & zikr card** (MantrasView.swift, ZikrMedia.swift, BuiltInAzkar.swift)
- Azkar: yours first, built-ins below (locked name / text), sort button (Name A→Z default), read-only page until ✎. Card: notes / voice memo / photo.

**History** (MantrasView.swift `ZikrLibraryView`, HistoryPageView.swift)
- History | Azkar native pager; all-time header + 14-day bars; delete only via Edit → select; row popover (Open zikr, Feel the pace).

**Insights** (InsightsView.swift, InsightsProgress.swift)
- Three pages: scoring (hero + five rings at the usual moment), consistency (streaks, 14-day grid), getting better.

**Daily Ayah, 99 Names, welcome**
- Ayah: tap to reveal once a day, share card in three looks, widget payload. 99 Names: list (All / Learning / Known), page, flashcards, `namesKnown`.
- Welcome (WelcomeAnimation.swift): cold launch only; the ring grows into the circle (`WelcomeTarget`).

## Open items

**Needs a real device:** Fajr rollover (yesterday's prayers up until Fajr) and the 15 Pro's first V2 launch (`✅ schema V2 data pass`, no ❌); the Always upgrade prompt (once); travel updates and background relaunch; the Shortcut alarm description; a real Jumu'ah at a masjid and the arrival dua with the app killed; nudge cancel from the widget extension; mic / camera; paging lag re-measure (Release); the watch list under Apple Watch; real Summary / Time Sensitive / Background App Refresh settings.

**Start here, still pending:** horizontal paging and the b4071db items on the phone; `SharedStateClass` → `@Observable`; compass arrow freezes while moving (leads: `handleLocationChange`, `storeLastCoordinate`, the 0.5° guard); three `.ips` UIKit `NSAssertionHandler` aborts on backgrounding (2026-09-24). Backlog: Infinity button → user step; `progressFraction` divides by a zero target; `toggleInactivityTimer` reset; stale finish estimate; dead code (`CommentedOutHistoryPageView.swift`); "How scoring works" card; Umrah companion and personalised 99 Names duas (plan first; the owner has the prompt, don't invent one); post-salah "points" (a separate layer, never in the prayer score).

**Ask the owner (never answered):** how to turn a map layer off (✕ on the top pill?); mosque icon style; should any jama'ah at a masjid score full or only Jumu'ah; post-salah points (+N vs 3/5, own streak, must 33 · 33 · 34 be complete); keep rotating all four Tasbih Fatimah reminders; at exactly 33 show "0 of 33" or hold "33 of 33"; the watch ring's dark track; a `.watchface` (#24) needs him to build one.

**Share card, on release:** `AyahShareCard.footer` says "join the beta on TestFlight" (link https://testflight.apple.com/join/GW5j85jk); when live on the App Store change it to "download on the App Store" and ask whether to add the link.

**App Store:** `fatalError` on `ModelContainer` failure (`shukrApp.swift`) still to replace. In App Store Connect: privacy policy URL, support URL, App Privacy label (precise location, on-device), screenshots 6.9" / 6.5", description / keywords / category / age rating, content-rights docs for `quran.sqlite`, `english_hilali.sqlite` (KFGQPC) and `KFGQPCUthmanTahaNaskh.ttf`.

**⚠️ The hadith sources and the four Tasbih Fatimah reminders were written from memory** (built-in azkar notes too); they need a knowledgeable check before release.

## Feature list (for the App Store listing)

What shukr does, meatiest first — keep this current; it's the source for the description,
keywords, "What's New" and screenshot captions.

**Prayer**
- Accurate daily prayer times for where you are (GPS, or a city you pick), with the
  calculation method and madhab (Hanafi / Shafi'i) of your choice.
- The main circle: the current or next prayer with a live ring of how much of its window is
  left, coloured by the score you'd get right now; tap to flip between "ends at" and time left.
- Prayer tracker: mark each prayer as prayed; it's scored by *when* — Perfect (first 30 min) ·
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
  where you left off or start over; a Tasks list to reorder, edit and delete them.
- Azkar: your own library of zikr with the full Arabic / transliteration and notes (who
  taught you, why), shown right on the pause screen; lifetime count, time and pace per zikr.
- Each zikr can keep a voice memo (how it's said — you, a teacher; slow 0.75× and loop) and a
  photo (a written dua, calligraphy), both a tap away on the pause screen.
- Count in sets: switch on a per-zikr "+N" and every tap counts N — for when you recite a set
  on your fingers and tap once.
- Post-salah tasbih (Tasbih Fatimah): 33 · 33 · 34 in one flowing session, the phrase
  changing as you go, with the hadith on why it matters.
- Zikr history: all-time total, a 14-day chart you can scrub, every session with its pace;
  swipe to delete or jump to the zikr.

**Quran & more**
- Daily Ayah: a verse a day (Arabic in the Uthmani script + translation) to reveal, with a
  beautiful 9:16 share card for Stories.
- 99 Names of Allah: each name with its meaning and explanation, and flashcards to learn
  them (with a "known" progress ring).

**First run**
- A short setup in the opening's look: where you pray (location, a calculation method picked
  automatically for your country, the madhab explained with both Asr times), light / dark / auto,
  reminders tuned per prayer, the Fajr alarm, your masjid and its duas — then "bismillah" into the app.
- Prayer times that follow you when you travel (with Always location), even when the app is closed.

**Privacy & feel**
- Nothing leaves the device: no accounts, no tracking; location is used only on-device.
- Light / dark / automatic appearance; a calm, rounded, circle-based design throughout.
- A short welcome — "shukr" writes itself inside a ring that settles onto the prayer circle, with
  a soft heartbeat haptic — when the app starts fresh.
