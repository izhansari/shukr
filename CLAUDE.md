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

## Immediate goal: App Store submission

Audit done 2026-09. Nothing below is fixed yet unless marked.

Hard blockers (rejection or upload failure):
- [ ] Location denied → infinite `GradientAnimationLoad()`; `if true` hardcoded at `shukrApp.swift:79`. Reviewers test denial. Needs the real "Location Access Required" UI and ideally manual city entry.
- [ ] Widget config placeholder strings ("the title wip...") in `shukrWidget/AppIntent.swift:18-22`, visible in Edit Widget.
- [ ] Template Live Activity ("Hello 😀", `http://www.apple.com`) registered in `shukrWidgetBundle.swift:15`. Delete.
- [ ] Dev UI reachable by users: "Dev's WIP" side-menu button (`Utils.swift:2847`); "My Dev Stuff" settings section toggled by tapping the "Calculation Method" header (`SettingsView.swift:236`, `:319`). Wrap in `#if DEBUG`.
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

**The vertical drag gesture is attached to the ScrollView itself, not to views inside it**
(`.simultaneousGesture(abstractedDragGesture)` on the pager). The scroll view's pan gets first
claim on every touch: horizontal → paging, vertical → our gesture. Nothing inside a page can
block paging. The gesture only acts when `horizontalPage == .main` (so scrolling the Settings
Form or vertical drags on Zikr do nothing). Do not re-add drag gestures inside pages.

Hamburger = native `Menu` (Map, Daily Ayah, Mantras, Settings, `#if DEBUG` Dev's WIP) driving
`.navigationDestination(isPresented:)` pushes on the root NavigationStack. The old drawer
(`sideMenu` in Utils.swift, `showSideMenu`) is parked: toggling it published shared state and
re-rendered the whole home screen to animate, which is why it felt laggy.

Settings page has its own header row (back chevron → `horizontalPage = .main`, title,
`ColorModeToggleButton` for light/dark/auto). Zikr page = `ZikrPageView`: `ZikrCircleView`
("Zikr / click to freestyle") above the `DailyTasksView` card frame. The bottom bar mirrors the
pager (Zikr | Salah | Settings).

Known: the pager ignores the bottom safe area (to keep the bottom bar flush), so the Settings
`Form`'s last row sits under the home indicator. Vertical on the center page is unchanged
(swipe up → `.bottom` sheet, swipe down → refresh, `dragOffset.height` with resistance).

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

Widget buttons: compass → app `.main` + qibla map; tasbeeh → app `.left` (Zikr page); list /
text toggles are in-widget. These use one-shot flags in the app group read on `scenePhase ==
.active` in `PrayerTimesAndTracker`.

**One SwiftData store, shared.** `SharedStore` (`shukrWidget/SharedTargetForIntents.swift`,
compiled into both targets) owns the schema and the store URL: `<app group>/shukr.store`.
`Models/` is in both targets' `fileSystemSynchronizedGroups` (pbxproj) so the schema matches.
On first launch after this change `migrateLegacyStoreIfNeeded()` copies the old
`Application Support/default.store` (+ -wal/-shm) into the group; the old files are left in
place and never read again. The app's `ModelContainer` comes from `SharedStore.makeContainer()`.

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
recorded), widget advanced to Maghrib, app showed it complete on reopen. Still untested:
tapping before a prayer starts; widget creating the row when the app hasn't opened that day;
upgrading an install that has a legacy `default.store` (migration path); whether the nudge
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
main circle tap on Zikr tab (`mainCircle.swift:225`), task card tap (`DailyTasksView.swift:255`
via `selectedTask.didSet`), post-salah button (`Utils.swift:3340`, `isDoingPostNamazZikr`
runs 33/33/34 sequence inside the view).

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
- [x] Side menu → "Mantras" page (`CursorSwift/MantrasView.swift`): list built-ins read-only, add/rename/delete custom `MantraModel`s. Rename propagates to `TaskModel.mantra` strings; sessions keep their historical title. `MantraModel.builtIn` is now the single source for the four defaults (picker reads it too).

## Planned: richer mantra model

Owner wants a mantra to carry more than a string: a short **title** (what shows on cards and
in the picker), the **full text** (Arabic, to refresh memory mid-session), and **notes**
("sheikh said read this every morning for business success"). Design agreed:

1. `MantraModel` gains `title`, `fullText`, `notes`, `createdAt`. Existing `text` becomes
   `title` via a `VersionedSchema` + `SchemaMigrationPlan` (rename is not lightweight).
2. `TaskModel.mantra: String` → `@Relationship var mantra: MantraModel?`;
   `SessionDataModel` gets `mantra: MantraModel?` and keeps `title` as a history snapshot.
3. Seed the four built-ins into the store on first launch so they become editable like the rest,
   then drop `MantraModel.builtIn`.
4. `MantraEditorView` (already the single edit surface) grows the two extra fields.
   Pause screen / results card: tapping the mantra name shows the full text.
5. `MantraPickerView` selects a `MantraModel`, not a string; `SharedStateClass.titleForSession`
   becomes `mantraForSession`.

Do this as its own branch/commit; it's a real migration and needs testing on a device with data.
