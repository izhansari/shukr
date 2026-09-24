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

## Start here: outstanding work, in priority order

Branch: `claude/app-store-publish-requirements-7vrmcg` (not merged to `main`). Everything below
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
6. Then the App Store blockers below.

## Immediate goal: App Store submission

Audit done 2026-09. Nothing below is fixed yet unless marked.

Hard blockers (rejection or upload failure):
- [ ] Location denied → infinite `GradientAnimationLoad()`; `if true` hardcoded at `shukrApp.swift:79`. Reviewers test denial. Needs the real "Location Access Required" UI and ideally manual city entry.
- [ ] Widget config placeholder strings ("the title wip...") in `shukrWidget/AppIntent.swift:18-22`, visible in Edit Widget.
- [ ] Template Live Activity ("Hello 😀", `http://www.apple.com`) registered in `shukrWidgetBundle.swift:15`. Delete.
- [ ] Dev UI reachable by users: "My Dev Stuff" settings section toggled by tapping the "Calculation Method" header (`SettingsView.swift`, `showDevStuff`). Wrap in `#if DEBUG`. (The "Dev's WIP" menu entries are already `#if DEBUG` in the new hamburger `Menu`; the old `sideMenu` in Utils.swift still has them but is unreachable.)
- [ ] Dead buttons: "Suggest Feature" (`SettingsView.swift:312`), "Cancel for X" (`:351`).
- [ ] "Muslim Brand Explorer" links use expired signed CDN image URLs (`SettingsView.swift:77-83`) + third-party photos/marks. Remove or bundle own assets.
- [ ] No `PrivacyInfo.xcprivacy` in app or widget. UserDefaults is a required-reason API (`NSPrivacyAccessedAPICategoryUserDefaults`, `CA92.1`). Declare location collection.
- [ ] `TARGETED_DEVICE_FAMILY = "1,2"` but UI is phone-only and icon set lacks 76x76@2x iPad slot. Set to `"1"`.
- [ ] Portal: App IDs need Time Sensitive Notifications + app group `group.betternorms.shukr.shukrWidget` enabled or archive signing fails.

App Store Connect (outside repo): privacy policy URL, support URL, App Privacy label (precise
location, on-device), screenshots 6.9"/6.5", description/keywords/category/age rating,
`ITSAppUsesNonExemptEncryption = false` in Info.plist, content-rights docs for `quran.sqlite`,
`english_hilali.sqlite` (KFGQPC copyright) and `KFGQPCUthmanTahaNaskh.ttf`.

Quality (fix before launch):
- [ ] Arabic font never loads: `DailyAyah.swift:420` passes the filename to `.custom()`, and the app target's `Info.plist` has no `UIAppFonts` (only the widget's does).
- [ ] `fatalError` on `ModelContainer` failure (`shukrApp.swift:45`) — first schema migration failure hard-crashes existing users.
- [ ] 187 `print()` calls, some logging coordinates. Gate with `#if DEBUG`.
- [ ] `NSMotionUsageDescription` declared but `PrayerTracker.swift` (only CMMotion user) is unreferenced. Drop both.
- [ ] Dead files: `shukr/LocationMapView.swift`, `shukr/PrayerTimeAndTracker.swift` (0 bytes), `CommentedOutHistoryPageView.swift`.
- [x] Deployment target is 18.0 on every target now (was 17.5 app / 18.0 widget). Needed for `onScrollPhaseChange`.
- [x] Removed stale `DEVELOPMENT_ASSET_PATHS = "shukr/Preview Content"` (folder deleted in 789632f; Xcode 27 errors on it).
- [ ] 1024 icon has an (all-opaque) alpha channel; strip to be safe.

## Navigation (PrayerTimesAndTracker.swift)

Two independent pieces of nav state on `SharedStateClass`:
- `horizontalPage: HorizontalPage` (.zikr / .main / .settings) — which pager page is showing.
- `navPosition: ViewPosition` — the **center page's vertical state only** (.main = circle,
  .bottom = salah sheet open). Paging away never changes it, so the center page comes back
  exactly as it was left. `.left / .right / .top` and `cameFromNavPosition` are legacy, unused.

Horizontal is a **native paging `ScrollView`** with three full-width pages in a plain `HStack`
(all stay mounted), each `.clipped()`. `@State scrollPage` is bound with `.scrollPosition(id:)`
and is written only from `onChange(of: horizontalPage)`; user swipes flow the other way via
`.onScrollPhaseChange` (iOS 18) **only when the phase hits `.idle`**, using
`visibleRect.midX / containerSize.width`. `.defaultScrollAnchor(.center)` starts on Main.

**The salah sheet pops; the finger never drags it.** `SalahPageContent` is the old
Spacer layout: `if showBottom` inserts the sheet (`.move(edge: .bottom)` + opacity) and two
extra Spacers above the circle; all of it animates from the `withAnimation(.spring(response:
0.35, dampingFraction: 0.85))` around the `navPosition` change. A vertical swipe past 30 pt on
the pager (`abstractedDragGesture`, `.simultaneousGesture` on the pager itself, axis decided
on the first move, ignored unless `horizontalPage == .main`) flips it: up opens, down closes,
down-while-closed refreshes. While the finger is down only `live.pull` moves (resisted ×0.5,
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

**Top bar and bottom bar are fixed chrome** (`PagerChromeView`, a sibling of the pager in the
root ZStack): hamburger `Menu` + `TopBar` on Salah / "Zikr" title on Zikr; chevron hint on Salah
with the sheet closed; `CustomBottomBar` on Salah with the sheet up and always on Zikr. Opacities
come from `navPosition` (animated by the same `withAnimation`) and `live.scrollProgress`
(`zikrness`); the whole thing fades with `settingsness` so Settings slides in over nothing and
keeps its own header. Owner's call: no chrome on Settings. Settings must not set
`.navigationTitle`: it's inside the root NavigationStack, so its title became the back-button
label on every pushed page.

**The Zikr page's task strip holds the pager while touched.** Nested same-axis scroll views
chain in UIKit (a drag on the strip at its last card turned the page, 2026-09-24). The strip
sets `live.pagerLocked` on touch-down (`DragGesture(minimumDistance: 0)`, simultaneous) and the
pager is `.scrollDisabled` while it's set; release or the strip settling clears it. `live`
reaches `DailyTasksView` through `.environment(live)` on the pager (optional `@Environment`, nil
outside it). Centering a card is local state only: it used to write `sharedState.selectedTask`,
whose `didSet` writes four more `@Published` properties — five home-screen re-renders per card
passed, which is what made the strip stutter. The tap action sets `selectedTask`.

`onScrollPhaseChange` ignores idle reports while `contentSize.width < 2.5 × width`: the first
one arrives before the three pages exist (midX/width = 0.5 → "Zikr") and left
`horizontalPage = .zikr` on the Salah page at launch, which also disabled the vertical drag
until the user paged away and back.

Hamburger = native `Menu` (Map, Daily Ayah, Mantras, Zikr History, Settings, `#if DEBUG` Dev's
WIP) driving
`.navigationDestination(isPresented:)` pushes on the root NavigationStack. The old drawer
(`sideMenu` in Utils.swift, `showSideMenu`) is parked: toggling it published shared state and
re-rendered the whole home screen to animate, which is why it felt laggy.

Settings page has its own header row (back chevron → `horizontalPage = .main`, title,
`ColorModeToggleButton` for light/dark/auto). Zikr page = `ZikrPageView`: `ZikrCircleView`
("Zikr / click to freestyle") above the `DailyTasksView` card frame. The bottom bar mirrors the
pager (Zikr | Salah | Settings).

Known: the pager ignores the bottom safe area (to keep the bottom bar flush), so the Settings
`Form`'s last row sits under the home indicator.

Broader lag lever not yet pulled: `SharedStateClass` is an `ObservableObject`, so *any*
`@Published` change re-renders every view holding `@EnvironmentObject sharedState` (nearly all
of them). Migrating it to `@Observable` (per-property tracking) would cut most of that. Mechanical
but wide: `@EnvironmentObject` → `@Environment(SharedStateClass.self)`, `$sharedState.x` needs
`@Bindable`. Do it with a builder in the loop.

Parked, not deleted: `DuaPageView` ("Notes") used to be the `.left` page; the block is
commented out in the body and there's no route to it now. `bottomTabPosition == .zikr` is
never set anymore; the branches in `BottomSharedView`, `mainCircle.swift`, and `TopBar` that
check it are dormant. `settingsViewNavBool` / its `.navigationDestination` push is unused.

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
- [x] Zikr History (hamburger → `HistoryPageView`, 2026-09-24): a List of every session newest
  first, grouped by day, under an all-time total; rows show mantra (live name, else the title
  snapshot), time, mode + target, count, duration and pace. The old paged-by-day version had a
  `scrollPosition(id:)` bound to an Int while the rows were keyed by Date, so it never tracked.
  `DayView` / `SessionCardView` / `DailyStatToggleView` in that file are now unused.
- [x] Mantra pace (2026-09-24): `MantraModel.totalCount` / `totalSeconds` / `secondsPerCount`
  are computed from its sessions (time-weighted: total seconds / total counts), nothing is
  stored, so no schema change and nothing to drift. Shown in the Mantras list row and the
  editor's Stats section (pace per count + per 100). `zikrDurationString` in AllModels.swift
  is the shared "1h 05m / 12m 03s / 45s" formatter.
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
