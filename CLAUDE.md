# shukr — working notes

iOS SwiftUI app (iOS 17.5+, SwiftData, WidgetKit extension, adhan-swift). Prayer times +
tracker, qibla, tasbeeh/zikr counter, daily zikr tasks, duas, daily ayah. No CI, no tests
beyond Xcode templates. Build/run happens in Xcode on the owner's machine; this repo has no
scripts to run.

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
- [ ] Widget deployment target 18.0 vs app 17.5.
- [ ] 1024 icon has an (all-opaque) alpha channel; strip to be safe.

## Navigation (PrayerTimesAndTracker.swift)

`sharedState.navPosition` is the single nav state. Horizontal is a three-page pager that tracks
the finger 1:1 (`pageDrag`) and springs on release: **Zikr (.left) | Main (.main / .bottom) |
Settings (.right)**. `pagerX = basePageX + pageDrag`; every page and the top bar overlay are
offset by it. Commit to a neighbour on 1/3 screen or a flick (predicted end > 1/2 screen);
rubber-band past the ends. Vertical on the center page is unchanged: swipe up → `.bottom`
(salah sheet), swipe down → refresh, with the old resistance/clamp (`dragOffset.height`).
`cameFromNavPosition` remembers whether you left from `.main` or `.bottom` so swiping back
returns there. The bottom bar mirrors the pager (Zikr | Salah | Settings).

Parked, not deleted: `DuaPageView` ("Notes") used to be the `.left` page; the block is
commented out in the body and there's no route to it now. `bottomTabPosition == .zikr` is
never set anymore (the sheet's zikr tab moved to the left page); the branches in
`BottomSharedView`, `mainCircle.swift`, and `TopBar` that check it are dormant.
`settingsViewNavBool` / the `.navigationDestination` push to Settings is also unused.
Freestyle tasbeeh is the ∞ button in `DailyTasksView`'s header (was the main circle on the
zikr tab).

## Widget ↔ app

Widget buttons: compass → app `.main` + qibla map; tasbeeh → app `.left` (Zikr page); list /
text toggles are in-widget. These use one-shot flags in the app group read on `scenePhase ==
.active` in `PrayerTimesAndTracker`.

**Completing a prayer from the widget does not open the app.** The widget can't reach the
app's SwiftData store (it lives in the app container, and the widget target doesn't compile
the models), so `MarkCompleteIntent` queues a `WidgetPrayerCompletion` {name, start, end,
tappedAt} in the app group via `WidgetCompletionStore` (`SharedTargetForIntents.swift`,
compiled into both targets). The widget treats queued + app-synced prayers as done
(`entry.completedToday`), so its circle advances to the next prayer immediately. The app
drains the queue in `PrayerViewModel.applyPendingWidgetCompletions()` on activation: scores
at the tap time, cancels nudges (may already have fired), creates the prayer row if the app
was never opened that day, then recomputes streak/day score. The app pushes its own
completions back with `syncCompletionsToWidget` so the widget doesn't offer a prayer you
already ticked in-app. Known gaps: no location recorded for widget completions; nudge
notifications can still fire between the widget tap and the next app open.

Bigger alternative if that gap matters: move the SwiftData store into the app group
container (file-copy migration on first launch) and add `Models/` to the widget target's
`fileSystemSynchronizedGroups` so the intent writes the store directly.

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
- [x] Widget "complete prayer" works in place, no app launch (queue in app group, applied on next open).
- [x] Zikr page moved to the left swipe (replacing Duas/"Notes"), Settings to the right swipe, pages follow the finger.
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
