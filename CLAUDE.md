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
   "on time" meant there (the on-time streak: consecutive days with all five Early / On time;
   started counting 2026-09-25, so it read 0). Ask the owner what they want to learn from it
   before building a third version.
9. Then the App Store blockers below.

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
- [ ] 187 `print()` calls, some logging coordinates. Gate with `#if DEBUG`.
- [ ] `NSMotionUsageDescription` declared but `PrayerTracker.swift` (only CMMotion user) is unreferenced. Drop both.
- [ ] Dead files: `shukr/PrayerTimeAndTracker.swift` (0 bytes), `CommentedOutHistoryPageView.swift`. (Both LocationMapView.swift copies deleted 2026-09-25.)
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

**Top bar and bottom bar are fixed chrome** (`PagerChromeView`, a sibling of the pager in the
root ZStack): hamburger `Menu` + `TopBar` on Salah / "Zikr" title on Zikr; chevron hint on Salah
with the sheet closed; `CustomBottomBar` on Salah with the sheet up and always on Zikr. Opacities
come from `navPosition` (animated by the same `withAnimation`) and `live.scrollProgress`
(`zikrness`); the whole thing fades with `settingsness` so Settings slides in over nothing and
keeps its own header. Owner's call: no chrome on Settings. Settings must not set
`.navigationTitle`: it's inside the root NavigationStack, so its title became the back-button
label on every pushed page.

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

Hamburger = a `.popover` (`presentationCompactAdaptation(.popover)`) with the "shukr" wordmark
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
press per step) and a "Tasbeeh → Secondary button step" number field (`tasbeehSecondaryStep`,
standard suite) that `tasbeehView` reads: > 0 shows a "+N" `TopOfSessionButton` (text variant)
between − and ∞ that calls `simulateTasbeehClicks(times:)`. Owner plans to move that control
onto the tasbeeh pause screen later.

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
- **On-time streak** (`onTimeStreak`, `maxOnTimeStreak`, `lastOnTimeStreakDate`): consecutive days
  with all five Early / On time (≥ 80). **Perfect day** (`lastPerfectDay`): all five **Early**.
  Both in `updateDayMilestones`, once a day, posting `.onTimeStreakContinued` / `.perfectDay`.
- **Top bar** (`TopBar` + `StreakLabel` in Utils.swift): tap the city → the streak for 5 s; tap
  the streak → on time → max. Once the day's done (the circle's summary condition) the streak
  stays up instead of the city (owner: keep the city otherwise). Celebrations: heart goes green,
  number rolls up, hearts float; the on-time beat follows ~2.4 s later with sparkles.
- **Completing a prayer** (`CursorSwift/PrayerCompletionFX.swift`): haptic, `.prayerCompleted`,
  the circle's `CompletionFlourish` (arc sweeps closed in the score colour, glow, "✓ Asr ·
  On time · 88"), the row's `CompletionDotPop`. The list folds done prayers into a "✓ N done"
  line (tap to show them); all five come back when the day's complete; perfect day pops the
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
  Invalid times are grayed and *not* corrected; Save is disabled and a line says why (before the
  start / not yet / after the rollover). A picked clock time lands on the prayer's day or the
  next, whichever is in range; after midnight a line spells out the day and time. The window bar
  (Early / On time / Late) is a scrubber; a Qaza time parks the marker at the end, gray.
- DEBUG-only: hamburger "Test Streak Celebration" / "Test Perfect Day" / "Old Insights"; launch
  args `-demoStreakCelebration`, `-demoDayMilestones`, `-demoPrayerCompletion` (switches to the
  dev test prayer times and marks prayers), `-demoInsights`, `-demoShareCard` (writes every share
  look to `<app data>/tmp/share-card-*.png`); any `-demo…` arg skips the notification prompt.

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
(a page `TabView`), each a question — "am I getting better?" (`PrayerProgressList`: verdict +
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

## Prayer day rollover (PrayerDay.swift)

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
`Map` has no clustering and the owner has ~800 pinned prayers. **North-up on purpose**: phone
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
Reached from the circle's qibla arrow (`fullScreenCover`). `CursorSwift/LocationMapView.swift`
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
