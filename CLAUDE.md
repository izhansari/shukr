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

## Standing rule: a "What's new" entry with every visible change

**Every commit that changes anything a user could see or feel adds a What's new entry in the same
commit** — with a **topic**, the **notes item #** (from shukr-ideas.md, when there is one), **try-it
steps**, **its own screenshot** and **the feedback ids it fixes**.
- **Hard rule — a screenshot per change, not per topic:** every new entry whose change can be seen
  gets its own fresh simulator screenshot (`whatsnew.py shot`, small JPEG) — never rely on an older
  entry's picture on the same topic. The card shows the newest; the detail's timeline shows each
  change with its own pictures. Skip only for changes that can't be seen (haptics, background).
- **Hard rule — close the feedback loop:** whenever a change fixes something from pulled feedback
  (`shukrGit/feedback/…/feedback.json`, or a note the owner pasted), put the feedback id(s) in that
  entry: `whatsnew.py add … --addresses <id>` (or `whatsnew.py address --entry <id> --feedback <id>`
  for one already committed). The app then shows the note under "To check" as "Addressed in
  <build>: <entry title>" with Looks good ✓ / Still off. Internal-only changes (refactors, logging,
scripts, notes) don't need one. The owner reads these in the app (tap the build line at the bottom
of the ☰ menu or Settings, DEBUG / TestFlight builds only), tests from them and sends feedback back.
- **Never hand-edit the entries** — use `scripts/whatsnew.py` (it keeps `shukr/WhatsNew.json`'s layout):
  1. `scripts/whatsnew.py resolve` (fills in earlier "next" hashes and every commit's time).
  2. Screenshot in the sim, then `scripts/whatsnew.py shot <png> <name>` → `shukr/WhatsNewShots/wn-<name>.jpg`
     (≤ 600 px, ~20–40 KB; keep the folder modest — it ships in TestFlight builds). The folder is a
     synchronized group in the app target, so nothing else to add.
  3. `scripts/whatsnew.py add --topic <id> --notes "#17" --title "<this change, one line>" --try "…"
     --try "…" --shot wn-<name>.jpg`. A new feature: also `--area Zikr --topic-title "…"`.
- **Topics are features, not commits** (one card each). Reuse the topic when a change touches an
  existing feature, and update `--topic-title` so it always describes the feature **as it is now**
  ("The map's globe toggles Standard ⇄ Satellite…"), plus `--topic-try` when the steps changed. A
  change that undoes / replaces an earlier one: `--status dropped|replaced` on the old entry (edit
  that one field in the JSON) so it shows greyed ("Map Modes sheet: dropped").
- `area`: Salah / Zikr / Map / Mosques / Widget / Notifications / Settings / 99 Names / Daily Ayah /
  …; `checked`: sim | phone | no. Plain, short language; 1–3 concrete steps ("☰ → 99 Names → Known").
- **Feedback comes back**: the owner marks 👍 / 👎 / 💬 with a note / photo per topic and either
  shares a Markdown summary into the chat, or `scripts/pull-feedback.sh` pulls it from the phones
  to `shukrGit/feedback/<date>.md` (+ photos). Read it when asked "check my feedback". The pull also
  writes `received.json` (id → first pulled time) back into the phone's `Library/Feedback` with
  `devicectl device copy to` (dev installs only; a TestFlight install refuses — logged, fine), so
  the app greys each note as "Received by Claude · <time>" with a fresh box under it.
- **v3 page (2026-09-27, notes #23):** "To check" (notes an entry `addresses`: Looks good closes,
  Still off reopens and opens a follow-up note linked by `followUpOf`; a cancelled Still off is
  undone), "To test" (untested, not hidden), "Unsent notes", then a collapsed searchable "Archive"
  (tested, closed, hidden). Long-press a card → Hide (`whatsNew.hidden`: topic → latest entry id, so
  a newer change brings it back; an addressed note shows under To check anyway). 👍 Works closes
  itself once sent / received. Note states: `FeedbackStore.state` (draft / toCheck / received /
  sent / closed / reopened). "Open in shukr": History / Azkar / 99 Names / Daily Ayah / Insights
  push inside the sheet (`WhatsNew.pushable`, ‹ Back = the card); Salah / Zikr / Settings / the map
  close it and leave the "‹ What's new" pill (`WhatsNewReturnPill` on PrayerTimesView and the map;
  `WhatsNewReturn.card`) that reopens it on that card; opening the page any other way clears the pill, and a
  "map" link does nothing when the map is already up.
  Follow-ups (2026-09-27): a note an entry `addresses` is never a draft (not in unsent / Send feedback, never loaded
  into the box); "Still off" always saves a new note (its own id — a later fix lists **that** id in `addresses`);
  `addressing()` skips dropped / replaced entries; feedback.md lists every note with its state (received, to check,
  closed, reopened); the card thumbnail skips superseded entries; Archive search covers note text.
  Later the same day: one draft lookup, `FeedbackStore.draft(for:followUpOf:)`, used by save() AND the composer (the
  composer used `unsent(for:)` — any draft — so a "Still off" loaded the plain draft and duplicated it, and the card's box
  could overwrite a follow-up). `unsent(for:)` stays for badges / the Unsent section. feedback.md is also rewritten at
  launch and after received.json loads. `WhatsNew.addressing` is cached per id. A hidden card's draft still lists under
  Unsent notes (on purpose: an unsent note shouldn't vanish). Azkar: sort ties fall back to the section order (built-ins'
  curated order, yours A–Z); the filter resets on appear when you have no own zikr; the library trims its search. DEBUG `-demoWhatsNewArchive YES` opens the
  Archive. `whatsnew.py status --entry <id> --set replaced` greys an undone change.
- The page: `CursorSwift/WhatsNew.swift` (cards, detail, timeline; tested per topic — a new change
  on a topic unticks it) and `CursorSwift/WhatsNewFeedback.swift` (store in the app group's
  `Library/Feedback/`: feedback.json, feedback.md, photos/). Gated by `WhatsNewAccess` (DEBUG, or
  `AppTransaction.environment != .production`). DEBUG `-demoWhatsNew [-demoWhatsNewTopic <id>]`.
- TestFlight notes: `scripts/whatsnew.py testflight --since <last uploaded build's commit> --out
  notes.txt` (one line per topic as it is now, ≤ 4000 chars, no emoji), then `scripts/asc.py release`.
- Topics can carry a `link` (`--topic-link salah|zikr|settings|history|azkar|map|names|ayah|insights`):
  the card's ↗ and the detail's "Open in shukr" close What's new and post `WhatsNew.go`; PrayerTimesView
  navigates 0.9 s later through `clearCovers` (pushing sooner, while the sheet was still closing,
  left a second search field in the library's bottom bar). Give new topics a link when they have a page.
- Entries have a stable `id` ("<topic>-<n>"); `resolve` finds an entry's commit by it (titles can
  be edited). The app decodes topics / entries one by one (a bad one is skipped and logged) and
  gives an entry with no topic a stand-in card. Tested ticks are keyed by topic + the latest
  entry's id (older topic@commit / commit|title keys still count).
- Feedback: every field decodes optionally; an unreadable feedback.json is moved to
  `feedback.json.bad-<stamp>`, never overwritten. Send feedback shares FILES (the .md + each photo
  under the name the .md uses). Only a real share marks items sent; Copy asks "Mark as sent?".
  `pull-feedback.sh` never overwrites (<date>-<phone>, then -HHMM, then -2…).
- App Store build: `SHUKR_APPSTORE=1 scripts/testflight.sh` leaves the screenshots out
  (`EXCLUDED_SOURCE_FILE_NAMES='wn-*.jpg'`; TestFlight and the App Store otherwise get the same
  binary). The page itself never shows there.

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
  where you left off or start over; arrange them home-screen style.
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

**Privacy & feel**
- Nothing leaves the device: no accounts, no tracking; location is used only on-device.
- Light / dark / automatic appearance; a calm, rounded, circle-based design throughout.
- A short welcome — "shukr" writes itself inside a ring that settles onto the prayer circle, with
  a soft heartbeat haptic — when the app starts fresh.

## Wording: "zikr" / "Azkar", never "mantra" in the UI (owner, 2026-09-27)

Everything a user reads says **zikr** (one) / **Azkar** (the library, the History | Azkar switch);
tasks stay "tasks". **Code and SwiftData names keep "Mantra"** (`MantraModel`, `MantrasView`,
`mantraName`…) — renaming a model is a schema risk. So in these notes "mantra" means the model /
code; in UI strings write "zikr". New UI text must follow this.

## Zikr card: notes / voice memo / photo — schema 2.5.0 (2026-09-27, notes #17)

- `MantraModel.imageData` / `audioData` (`Data?`, `@Attribute(.externalStorage)`). Backup
  `…before-2.5.0` is made by `makeContainer` as usual.
- `MantraCardFields` (MantrasView.swift): the notes row is three tab buttons (doc.text / waveform /
  photo, sage when selected, a sage dot when that tab has something) beside ONE box of fixed
  height (`paneHeight` 132). The box's content is a `switch pane` with `.transition(.opacity)` —
  nothing on the card moves. **Trap:** the first version stacked all three layers in a ZStack and
  hid two with `.opacity(0)`; a hidden memo / photo layer covered the top ~30 pt of the notes text
  (it rendered, just unseen). Don't go back to stacked hidden layers.
- `CursorSwift/ZikrMedia.swift`: `ZikrAudio` (AVAudioRecorder AAC, 2 min max, metering; AVAudioPlayer
  with 0.75× and loop; the session (`.playAndRecord` / `.playback` `.spokenAudio`) is ended with
  `.notifyOthersOnDeactivation`, so the user's music resumes), `VoiceMemoPanel`, `ZikrPhotoPanel`
  (PhotosPicker + camera, `downscaledJPEG` 1200 px, tap → `ZikrPhotoViewer` zoom), `ZikrMediaStrip`
  (pause card: ▶︎ + 0.75× / loop + a 56 pt thumbnail).
- **Audio rules (2026-09-27 review):** the card owns the one `ZikrAudio` (VoiceMemoPanel borrows
  it) so tab switches / List recycling can't drop a take; every end of a recording (Stop, the 2-min
  cap via `AVAudioRecorderDelegate`, interruptions, background, leaving the memo tab, the sheet
  closing → `ZikrAudio.stopAll()` from the sheet root's `onDisappear`) goes through
  `finishRecording()` → `onRecorded`. One engine is active app-wide (`takeOver`). Pause deactivates
  the session (`.notifyOthersOnDeactivation`, music resumes); interruption / route-change
  (headphones out) pause. Resume / Finish in a session call `stopAll()`; the strip also stops on
  `paused` → false (the pause screen only fades). **All session activation, deactivation and
  recorder / player setup run on a serial audio queue** — `setActive(true)` for recording froze the
  simulator's main thread (and never returns there, so recording can't be tested in the sim). A
  start that resolves after a stop is dropped (`generation`, bumped by every start and stop;
  playback has a `.loading` state — taps ignored, a stop cancels it — and recording re-checks
  after the mic prompt). The temp .m4a is removed on every exit path (and in `deinit`). Memo
  length is computed off the main thread; `.task(id:)` uses `blobKey` (size + ends), never the blob.
  `onRecorded` is re-wired on every render of the card (current binding). Ticker in `.common` mode; 64 kbps AAC;
  the temp file is deleted after reading.
- **Photos:** `downscaledJPEG` is async (ImageIO thumbnail in a detached task); the camera hands a
  UIImage straight in; views decode with `decodedImage` in `.task(id:)`, never in `body`.
- **Media are part of an edit (2026-09-27, quick fix — owner: "the flow looks broken"):** in any editor
  with Save / Cancel (the pause ✎ `MantraCardEditor`, the zikr page in ✎ mode, a new zikr) the photo /
  memo wait in drafts (`draftImage` / `draftAudio`, `mediaEdited`) and a take in progress counts as an
  edit; Save lights up, calls `ZikrAudio.stopAll()` first (the take lands in the draft synchronously)
  and writes them; Cancel with edits asks "Discard changes?" and drops them (`discarding` keeps a
  take from landing). The zikr page in read mode (no ✎) still saves them straight away. Sim ✓ on the
  zikr page (remove photo → Save green; Cancel → Discard → back; Save keeps it); the pause card has
  the same code, not tapped in the sim.
- A zikr's sessions: `MantraSessionsSection` is several Sections, so its toolbar / alert were attached
  per Section (duplicate Delete). The edit state, bottom-bar Delete and alert live on
  `MantraEditorView` (bindings in); edit-mode rows are `SessionRow(tappable: false)` (a tap opened
  Feel the pace). Sim ✓.
- Info.plist: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`.
- DEBUG: `-demoZikrMedia` (Alhamdulillah gets a rendered calligraphy image and a 3 s tone; its page
  opens; add `-demoPauseScreen` for the pause card), `-demoZikrPane notes|memo|photo`,
  `-demoZikrEmpty` (Astaghfirullah, empty tabs).
- Sim ✓: all three tabs filled and empty, the pause strip. Recording on a real mic and the camera
  are untested (no mic / camera in the sim).
- In view mode long notes scroll inside the box (`.scrollBounceBehavior(.basedOnSize)`).
- **Built-in azkar** (`Models/BuiltInAzkar.swift`, once per install, flag `builtInAzkar.v1` in
  standard defaults, run after the V2 data pass): the four old built-ins get their Arabic
  (`fullText`) and a meaning + source note, **only into empty fields**; four new ones are added
  (La ilaha illallahu wahdahu · SubhanAllahi wa bihamdihi · Allahumma salli 'ala Muhammad ·
  Hasbunallahu wa ni'mal-wakil), matched by name ignoring case / spaces / punctuation so nothing
  is doubled. It never runs again, so a deleted one stays deleted (the old four are still
  re-seeded bare by the data pass, as before). Log `✅ built-in azkar: added=… filled=…`.
  **⚠️ The hadith sources were written from memory — they need a knowledgeable check before
  release** (with the Tasbih Fatimah reminders).
- DEBUG `-demoZikrName <name>` with `-demoZikrEmpty` opens that zikr's page.
- **Built-ins are locked** (owner, 2026-09-27): `MantraModel.isBuiltIn` = `builtInID != nil`
  (**schema 2.6.0**, set by the seeders, Tasbih Fatimah's creation and `BuiltInAzkar.tagRows` —
  every launch, EXACT seeded names only, one row per id; a user's "Subhan Allah" is never tagged).
  Every zikr-name comparison (duplicates, seeding, the data pass's linking, `find(named:)` after an
  exact match) uses `BuiltInAzkar.key` (letters and digits, any script; falls back to the name). `MantraCardFields(identityLocked:)` keeps
  name and full text read-only (a lock overlay in the name field, no layout change); notes, memo,
  photo, sets stay editable. They can't be deleted (Azkar list `deleteDisabled`, no Delete button).
  The Azkar list has "Built-in" (BuiltInAzkar order) and "Your azkar" sections. Since 2026-09-27 (feedback 6B1CFEB8; the folding
  header was dropped): "Your azkar" first, "Built-in" below; `AzkarFilterButton` (the library's
  bottom bar left of the search on iOS 26, top right on iOS 18 / the standalone page;
  `@AppStorage(AzkarFilter.key)` "azkar.hideBuiltIns", filled green while on) hides the built-ins,
  with a "9 built-in azkar hidden · Show" footer — never while searching or with none of your own.
  **Current (2026-09-27, feedback D505E0DE):** the sort button sits top right on the Azkar tab, in Edit's old spot (one
  toolbar item, `libraryTrailing`: History's Edit or Azkar's sort). **Azkar has no bulk Edit / Delete** (owner: too quick a
  destructive choice) — a zikr is deleted from its own page. Icon: plain arrow.up.arrow.down on Name A→Z; otherwise the
  field's symbol + a small ↑ / ↓ in green on a soft green capsule (`Color.green.opacity(0.16)`, the app's tinted look;
  sim ✓ light + dark). A solid `.glassProminent` fill with white icons was too stark (owner). Trap if a fill comes back: a
  toolbar Menu only takes a button style with `.menuStyle(.button)`. To screenshot dark mode, launch with
  `-modeToggleNew 1` (the app's own setting overrides the system's; editing its prefs plist hit the prefs cache). iOS 26's bottom bar is just search + ＋. Simulated taps
  don't reach the Menu or the segmented switch — set `azkar.sortField` in the app's own prefs plist to screenshot. Sim ✓.
  **Current (2026-09-27, feedback F5FDC4C1):** no "Default" — the default is Name, A to Z, for both sections (built-ins
  alphabetical too); `AzkarSort.migrateStoredDefault()` turns a stored "standard" into Name ↑. Direction rows are just the
  result with the arrow icon: A to Z / Z to A · Most / Fewest first · Fastest / Slowest first · Recent / Oldest first. The
  plain arrow.up.arrow.down icon means Name A→Z; anything else shows ↑ / ↓. The first version follows:
  **Current (2026-09-27, feedback ADD5836A):** `AzkarSortButton` — sort by ONE field (`AzkarSort`: Default · Times recited ·
  Pace · Last used · Name, AppStorage "azkar.sortField") plus a direction (↑ / ↓, "azkar.sortAscending"; picking a field
  sets its natural direction: Name / Pace ascending, the others descending; the menu spells each out — "Most first",
  "Fastest first" = fewest seconds per count, "Longest untouched first"…). Missing data sorts last either way; ties keep
  the section order. The built-ins filter is gone (built-ins always show, below yours; the old key is cleared on appear).
  Icon: arrow.up.arrow.down on Default, arrow.up / arrow.down while sorted. History of the earlier versions follows.
  Since 2026-09-27 (feedback E164092C) the button is a native Menu (`AzkarFilterButton`): Sort (`AzkarSort`, AppStorage
  "azkar.sort": Default · Most / Least recited · Recently used · Slowest / Fastest pace (never-counted last) · A–Z,
  applied within each section, stats computed once per list render) and "Show built-ins" (only with azkar of your
  own; disabled while searching). The icon fills (primary, not green) while a non-default sort or the filter is in
  effect; deleting your last own zikr turns the filter off. The zikr picker lists yours first too. Rows are
  Buttons, and a List row fires its Button on a tap even with `allowsHitTesting(false)`: the action
  itself returns in Edit mode (a greyed built-in opened its sheet — owner, 2026-09-27).
- **The original four are seeded once** (`BuiltInAzkar.originalsSeededKey`; the V2 data pass
  re-seeded a missing one every launch), matched letters-and-digits like the new four.
  `recoverFromUnopenableStore` clears both seed flags so a fresh store gets them again.
- **Deleting**: `MantraModel.delete` / `TaskModel.delete` post `TaskModel.didDelete` (persistent
  ids) → PrayerTimesView clears `selectedTask`; `ZikrFocus.forget`. The zikr page dismisses first,
  then deletes (0.35 s later) so no view reads the gone row; alerts capture their text up front.
  Sessions: `SessionDeletion.delete` (save, widget reload, reschedule) from History and from a
  zikr page's own "Sessions · Edit" (custom checkmarks; no swipes, no strip Delete anywhere).
  History clears its selection when the search changes and deletes only selected ∩ visible;
  the library doesn't page while History is editing; Edit hides with no sessions.
- **Deleting a zikr**: `MantraModel.delete(_:in:)` only (the zikr page's "Delete zikr" while editing,
  the Azkar list swipe — both confirm with `deleteMessage`). Its tasks are deleted too: a task left
  with only its name snapshot made the data pass re-create the zikr next launch. Sessions stay.
- **New zikr card**: can't be swiped away once anything's in it (text, sets, photo, memo, or a take
  in progress via `MemoRecordingKey`); Cancel asks "Discard this zikr?". The picker selects a new
  zikr in the card sheet's `onDismiss` (`pendingNew`), so the two sheets close one after the other.
- Task sheet: goal focus = `.defaultFocus` + set in onAppear and again next run-loop turn (no fixed
  delay); from a zikr's page `createTask` doesn't touch `selectedTask`; the fields aren't cleared
  before the cover closes.
- **New task flow:** `AddDailyTaskView` focuses the goal field 0.35 s after it appears (a new task
  only). `AddDailyTaskView(for: mantra, …)` = a new task with that zikr locked (`lockedMantra`,
  also true in edit mode). **Creating a zikr always opens the whole card**: `MantraPickerView`'s ＋
  (top right, beside search) and its "no results" button open `MantraEditorView(mantra: nil,
  initialName:onCreate:)`; Save calls `onCreate`, which selects it and closes the picker. The old
  name-only "Add this to list?" alert and `saveToMantraList` are gone. A zikr's page: a glass ＋ at
  the end of the Tasks header (always) and, with no tasks, the Zikr page's dashed "New task" circle
  (`MantraTaskCircles(onNewTask:)`); both open the locked task sheet. Sim ✓ both paths.
- **The zikr picker looks like the Azkar page** (owner, 2026-09-27): `MantraPickerView` is a
  `NavigationStack` ("Choose a zikr", ✕ / ＋ in the bar) over the Azkar rows — `ZikrListRow`
  (MantrasView.swift), shared with `MantrasView`, a green check on the current pick instead of the
  chevron — and the system `.searchable` at the bottom (name, text or notes).

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
- **Post-salah prompt:** the bottom pill is the only prompt (the in-circle offer, the top pill and
  their dev picker were deleted 2026-09-27). It uses `FlickAway` (PrayerCompletionFX.swift): a
  resisted pull of ~70 pt in any direction that fades as it goes; past 60 pt (or on a flick) it
  finishes fading in place and is removed without animation. No edge wall.
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
  Felt, too (2026-09-26): with sets on, each tap is a quick triple tick (the usual haptic, then
  two light ones 70 ms apart). The owner resumed a paused session still counting in sets and
  didn't notice.
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
  - Plays only on a cold launch (the process starting fresh). It used to replay after more than
    5 min in the background; the owner found that too often (2026-09-27), so `awayThreshold` /
    `willShow` are gone.
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
    - The green arrow also brings you home (2026-09-27, quick fix): `LocationViewModel.homeQiblaUp(on:)`
      = one camera move to your dot, qibla-up, and back to `qiblaSpan` zoom when the screen is more
      than 1.5× wider (in metres, measured across the view, so a turned map doesn't skew it). The
      red north needle (prayer spots / mosques) still only turns the map. Sim ✓.
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
      - The list opens by itself when Mosques is picked (`wantsMosqueList` → `openPendingMosqueList`
        once results land, Explore has closed and the first-time mosque guide has been seen /
        dismissed; the guide never stacks on the list). Redesigned 2026-09-26 (owner: "kind of
        boring"):
        - a "Mosques · 29 near you" header with a drive / walk switch;
        - a green-tinted NEAREST card with a big icon, name, address, travel time, distance and
          "Show ›";
        - "MORE NEARBY" rows in one rounded group: tinted icon, name, address, distance and the
          travel time.
        MKDirections ETAs are fetched for the closest six only, because it is rate-limited.
        Sim ✓.
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

**2026-09-26 — Daily Ayah page + widget mint** (owner: the page was plain once revealed, the
Arabic lines too far apart, and the widgets' mint too subtle in light mode):
- **Reveal:** tap anywhere on the unrevealed page, with a pulsing "tap to reveal today's ayah"
  hint. The verse waits small (0.6×, anchored at the top so a long one isn't pushed down behind
  the hint) and blurred. The reveal brings it to full size as the blur lifts, a sage light
  blooms out behind it, with two soft haptics. Chrome fades in after.
- **Revealed:**
  - the surah's Arabic name in sage over a tracked "an-nisaa · 4:46";
  - the Arabic through `ArabicVerseText` (a UILabel with `lineHeightMultiple` 0.82 — SwiftUI Text
    can only add line spacing, and the Uthmani font's own line height is tall);
  - an eight-pointed star `AyahMarker` with the number in Arabic digits (٤٦) between hairlines;
  - the English in light rounded type; the translator (tap → translation picker);
  - "Continue reading on Quran.com" as a green capsule at the end of the text (floating at the
    bottom it sat on long verses).
  - A faint sage glow breathes behind it all. It is a blurred `Ellipse`: the first version was a
    `RadialGradient` whose radius ran past the view's own frame, so it was cut off in a visible
    rectangle (owner).
  - Tap the surah caption to flip between its name and its meaning ("an-nisaa" ⇄ "the women").
    The old `SurahHeaderView` did this and the redesign had dropped it.
  - `.scrollBounceBehavior(.basedOnSize)`: a verse that fits doesn't scroll or bounce.
  - The page scrolls for long verses. The timer and share stay at the top.
- DEBUG `-demoAyahUnrevealed` shows the page unrevealed even if today's was revealed.
- **Widgets:** `BrandBackground` light mode is a stronger mint (0.86/0.945/0.875 → 0.66/0.84/0.71)
  with a soft white light in the top-left corner.
- Sim ✓: unrevealed → tap in empty space → revealed; long verse (4:46) scrolls; the Name widget
  is visibly mint.

**2026-09-26 — pause screen bottom:** Resume is the only big button now: a centred 210 pt capsule
with a sage edge and sage text on a faint tint. The first try was a full-width filled bar, and the
owner didn't like it. Under
it, "Finish early" in small secondary text, still two taps: the first turns it green, "Tap again to
finish", and it disarms after 3 s. Owner: with two big buttons side by side, the coloured one felt
like "end" and he was scared to press it. The Tasbih Fatimah reminder under the count is quieter
(title primary 0.5, text 0.36, source sage 0.75); it read bright white in dark mode. The count-in-sets
subtitle is now "on, each tap counts 3" (it truncated). Sim ✓ (light mode).

**2026-09-26 — widgets over the map, and the welcome becoming the circle.**
- **Widgets / controls opening pages behind the map:** they opened behind the map / a pushed page.
  `clearCovers(then:)` in PrayerTimesView closes the map, every pushed page and the mantra sheet
  (`dismissCovers`), waits 0.55 s if anything was up, then navigates. A tasbeeh session is never
  closed (`showTasbeehPage` → do nothing). The compass flag does nothing if the map is already up.
- **Welcome → circle:**
  - The main circle's track reports its global frame (`onGeometryChange` →
    `WelcomeTarget.circleFrame`, mainCircle.swift).
  - The welcome waits up to 0.4 s for it, then draws its ring exactly there (an `.offset` from the
    screen centre) and glides onto it if it moved.
  - After the hold, the ring (`WelcomeRing`, an annulus `Shape` so its thickness animates) grows
    from 1.2 to 12 pt and fades from sage to `secondarySystemFill` while the word blurs away and
    the background fades (0.8 s). What's left is the real circle in the same place.
  - Returning after 5 min posts `WelcomeGate.willShow`: PrayerTimesView closes covers and sets
    `.main` page + `navPosition .main` (no animation). It skips all that and sets
    `WelcomeTarget.canLand = false` over a tasbeeh session, so the welcome falls back to the
    screen centre.
  - **Trap:** a `GeometryReader` inside the welcome overlay left the entire app laid out off screen
    (blank white page, the circle's frame at (-100, -117)) once the welcome ended. Don't put one
    back.
- Sim ✓: cold launch morph frames (ring on the circle, word → "Dhuhr"). The widget-over-map fix is
  not tried in the sim.

**2026-09-26 — welcome grows into the circle; the "next prayer" look.**
- **Welcome:** the ring now starts snug round the word (150 pt). After the hold it grows to 200 pt
  (a frame change, so the line keeps its own width) while thickening into the gray track (spring,
  0.75 s) as the word fades. Once it's there, the overlay fades (0.45 s) and the page appears
  round the ring. The owner asked for "the circle grows into the other one". Sim ✓ frame by frame.
- **Next prayer** (the circle showing a prayer that hasn't started, e.g. Asr after Dhuhr is
  marked): the owner found it read like a prayer that's on with no progress. It now has a tracked
  "NEXT" above the name, the name / icon at 55 % opacity, and (since 2026-09-27) the track itself
  drawn dashed — see "Main circle next → now" below (`NextPrayerRing`, an inner dashed ring, is gone).
- **Welcome onto a page with no circle:** a widget opening Daily Ayah / 99 Names / the map.
  PrayerTimesView keeps `WelcomeTarget.canLand = !(somethingCovers || showTasbeehPage)`. When it
  can't land, the ring opens out past the screen edges like a doorway (`portal`: grows to 1.4× the
  screen's long side, fading) while the word and background fade onto that page. On the Zikr page
  (circle off screen) it still grows into a centred ring, which the owner likes. Sim ✓ onto
  Insights.
- **Not recommended mosques** (`MosqueHiding`, MosqueFinder.swift; owner: the nearest suggestion
  was an Ahmadiyya mosque):
  - How to hide: long-press a mosque in the list, or "Don't recommend this mosque" at the bottom of
    its sheet. (A filter menu with "Hide Ahmadiyya mosques" was removed 2026-09-26 — owner: some
    people may be offended; one at a time is enough. Don't bring back group filters by sect.)
  - What hiding does: the mosque is never the nearest card, sits greyed under "NOT RECOMMENDED" at
    the bottom (long-press → recommend again), isn't counted in "N mosques", and its pin is grey
    with a lower display priority and its own cluster.
  - Storage: ids = lowercased name + lat/lon to 4 decimals, in standard defaults `hiddenMosques`. Changes post `MosqueHiding.changed`, and the map republishes its pins.
  - No "best rated" sort: MapKit exposes no ratings.
  - Sim ✓ (hid one: grey pin, 29 → 28).

**2026-09-26, later still — accurate picking pin, one-spring transitions, "Back to …".**
- **Picking pin was off** (owner: "shows the pin on a location different than my address"): the
  SwiftUI overlay pin was drawn in screen space while the spot was read from the map view's own
  coordinates (~35 pt apart). The pin is now `PickPinView`, a UIView added to the MKMapView at
  exactly `pick.pinPoint` (head + needle, lifts while the map moves). Sim ✓: a prayer marked at the
  user's dot → the needle's tip lands on the dot.
- **Transitions** (owner, again: "still not smooth"): the two-step timers are gone. The prayer page
  is one self-sizing column (`fixedSize` + `onGeometryChange` → `setPageHeight`); the sheet's
  detent is always `pageDetent` = that height, animated with `LocationViewModel.sheetSpring`
  (`.smooth` 0.42 s), and the height being left stays allowed for 0.7 s (`leavingDetent`) so it
  animates instead of snapping. So Edit / Change location / Cancel / Save just change `spotMode`;
  the content swaps (`AnyTransition.sheetContent`: out in 0.1 s, in after 0.12 s) and the sheet
  follows the new height in the same motion. No fixed edit / pick detents any more (`.large`
  only while typing an address). Verified from simulator recordings.
- **"Back to Dhuhr"**: panning the open prayer's pin > 90 pt away from its place
  (`checkFocusDrift`, on region change, browsing only) shows a glass capsule just above the sheet;
  tap → `centreFocus()`. After picking, the prayer's own pin returns and re-centres.

**2026-09-26, later — prayer page polish.** Owner: Edit far too loud, no window end shown, empty
space, and the edit states snapped instead of animating.
- Edit is a small gray "✎ Edit" text button under the location. The second line under "Prayed
  4:39 PM" says when the window ended: "29 min after the window ended at 4:10 PM" / "1h 14m into
  the window · 12:49 – 4:10 PM" (`whenLine`).
- The page measures its header + reading part (`onGeometryChange`) and the sheet is exactly that
  tall: `LocationViewModel.setPageHeight` / `pageDetent` (replaces the fixed 350 pt
  `compactDetent`; `pageFraction` for `focus`).
- Mode changes are two steps (`setSpotMode`): `detentMode` (which sizes are allowed) changes
  first; growing → the sheet resizes (`.smooth` 0.38 s), then 0.2 s later `spotMode` swaps the
  content; shrinking → the content swaps first, then the sheet follows 0.16 s later. The size being
  left stays in the allowed set for 0.9 s (`leavingDetent`) so the sheet animates from it instead
  of snapping. Content swaps use `AnyTransition.pageSwap` (old leaves in 0.1 s, new arrives after a
  0.1 s delay — a plain crossfade overlapped the two). Header stays put. Edit detent is now a fixed
  540 pt. Verified frame by frame from simulator screen recordings (`simctl io recordVideo` +
  ffmpeg tile).

**2026-09-26 late night — the mosque sheet is the bubble; the prayer page reads, then edits in place.**
- **Mosques** (owner: the bottom bar "feels out of place", and picking Mosques showed the bar,
  then the list 1.5 s later): `MosqueLayerBar` is deleted. Picking Mosques opens the mosque sheet
  at once ("finding mosques…" with a spinner until results land). It stays up for as long as
  Mosques is the layer: `interactiveDismissDisabled`, detents `mosqueCollapsed` (96 pt — just the
  "Mosques · 29 near you" header) / medium / large on `LocationViewModel.mosqueDetent`, so swiping
  down shrinks it to a bar at the bottom (Apple Maps style) instead of closing. ✕ in the header →
  back to the qibla (`setMode`). A pin tap raises it to medium on that mosque. The explore dock
  hides in mosque mode (the sheet covers it); "Search this area" moved up under the top pill. (2026-09-27 fix: it had
  drifted mid-map — it sat under the whole top row, whose right column grew with the ? button; now an overlay on the
  pill row, 56 pt down. The collapsed 96 pt sheet scrolled its list: `MosqueListSheet(collapsed:)` → `.scrollDisabled`
  + back to the top. Not sim-checked: see the map hang below.) The
  map guide (? / first time) presents over the mosque sheet while it's up (two bindings on `guide`,
  one per presenter). `wantsMosqueList` / `openPendingMosqueList` are gone.
- **Prayer page** (`PrayerSpotDetail`; owner: rows looked tappable and weren't, the blue ···
  squeezed the header, "feels sad"):
  - Reading: header (back, icon, name, "Fri, Sep 25, 2026" on one line, score + grade), the
    time editor's coloured window bar (read-only, marker at the prayed time), "Prayed 4:39 PM ·
    after the window ended", a divider, where (masjid / address), "✎ edited · you marked it…"
    notes with a green **Undo**, and one gray **Edit** capsule at the bottom. Sheet height is a
    fixed 350 pt (`compactHeight`) so it all fits.
  - Edit (same sheet, `spotMode = .editTime`, detent 0.64, map dimmed): the bar scrubs, the wheel
    appears (`PrayerTimeEditor`, extracted from the time editor sheet, `showsScore: false` — the
    header score updates live), a location row (a real button now), Cancel / Save.
  - Change location (`.pickSpot`, detent 200 pt): the sheet holds `SpotPickerCard(embedded:
    true, setTitle: "Done")`; the map above becomes the picker (`MapPickOverlay`: the question +
    `CenterPin` at `pick.pinPoint`, the middle of the map above the sheet — the coordinator reads
    `pickedCoordinate` there, `jumpPick` flies a spot under it with bottom edge padding, minus the
    view's safe area, which MapKit adds). Typing an address grows the sheet to large. Done → back
    to the editor with "moved · Save to keep it"; Save writes time + spot (both keep the recorded
    values).
  - Detents and background interaction follow the mode (`spotDetents`, `spotBackground`): "up
    through .medium" silently disables when .medium isn't among the detents — the map froze.
  - Sim ✓: cluster → Dhuhr's page → Edit (wheel) → Change → drag → "340 ft…" → Done → Save →
    page shows the new address + edited note → Undo → back at 43 Park Row (recorded cleared).
- Shared pieces now: `PrayerTimeEditor`, `SaveCancelButtons`, `PrayerWindowBar` (no longer
  private) in PrayerTimeEditSheet.swift.

**2026-09-26 night — recorded vs edited; mosques in one sheet.**
- **Schema 2.3.0:** `PrayerModel.recordedTimeAtComplete / recordedLat / recordedLon` (optional,
  lightweight; `makeContainer` backs up to `…before-2.3.0` first — sim ✓). Owner: once edited,
  there was no way to know what the app actually recorded, or to put it back.
  - The first user edit keeps the recorded value: `PrayerModel.editTime(to:)` (via
    `PrayerViewModel.editPrayerTime`, both time editors) and `movePrayer`. `timeEdited` /
    `spotEdited` compare live vs recorded (30 s / 3 m). `revertPrayerTime` /
    `revertPrayerLocation` put it back and clear the recorded field. `resetPrayer` (unmark)
    clears them. `setPrayerScore(atDate:)` itself doesn't touch them (marking, rescoring, the
    masjid check use it).
  - Where it shows: the time editor — "↩ You marked it at 5:26 PM · use that" under the score
    (sets the wheel back; Save keeps it) and "· edited" on the location chip; the map's prayer page
    — "✎ edited · you marked it at 9:05 PM" / "✎ edited · you marked it 590 ft away" under the
    rows, and ··· → "Back to 9:05 PM" / "Back to where you marked it"; the picker card measures the
    distance from the recorded spot and has "↩ Back" to fly there; the time editor's own picker
    draws the recorded spot as a green ring ("Marked here").
  - Sim ✓: Asr edited 5:26 → 4:17 PM (row: time 16:17, recorded 17:26), the editor then showed
    the note. The revert menu items are not tapped in the sim yet.
- **Mosques are one sheet** (owner: a mosque closed the list and opened another sheet; getting
  back meant closing it and pressing List): the list sheet is a `NavigationStack` on
  `LocationViewModel.mosquePath`. A row pushes `MosqueSheet(showsBack: true)` (nav bar hidden — it left an empty row above the name, owner; the back chevron sits in the header row beside the name) and flies the map
  to the pin (selected, above the sheet); a pin tap opens the same sheet on that mosque (or swaps
  the page if it's up). Back → the list where you left it, the pin deselects. The old
  `mosqueSelection` sheet is gone. `.presentationContentInteraction(.scrolls)`: the list scrolls
  at half height; the grabber resizes. Sim ✓ (row → page, back, pin → page, scroll at medium).

**2026-09-26 night — prayer pages on the map, typed addresses, the time editor's location chip.**
Owner: the time editor's location row sat oddly; wants to type an address and see the distance;
on the map, no swipe-to-reveal — tap a prayer → its page in the sheet, ··· → edit; worried about
too many sheets.
- **Map, no sheet-on-sheet:** the prayer-spot sheet has its own `NavigationStack`. A single pin
  opens straight on `PrayerSpotDetail`; a cluster's list rows are `NavigationLink`s that push it
  (the sheet shrinks to compact on the page and grows back for the list). The page: icon, name,
  date, score + grade word, "Prayed 9:17 PM · 1h 14m into the window · 8:03–11:59 PM", where
  (masjid or address). While it's open that prayer's own pin is drawn over any cluster
  (`FocusPrayerAnnotation`, score colour, glow, not tappable). ··· menu:
  - **Change time** → `PrayerTimeEditSheet(showsLocation: false)`, a short sheet over the spot
    sheet; saving rescores, recomputes the day / streak, widget, and redraws the pins.
  - **Change location** → `LocationViewModel.beginMove`: the sheet goes away and the map itself
    becomes the picker (`MapPickOverlay`: the question on top, `CenterPin` in the middle of the
    screen, `SpotPickerCard` at the bottom; the map's own controls fade out). The pin follows the
    map through `SpotPickState` (@Observable, written by the coordinator's region callbacks; only
    the overlay reads it). Set → `movePrayer` + back on the prayer's page at the new spot;
    Cancel → back on its page, the cluster's list behind it (`PrayerSpotSelection.focus`).
- **`SpotPickerCard`** (PrayerLocationPicker.swift, shared by both pickers): the address (or your
  masajid by name) — tap it to type an address (`AddressSearch`, MKLocalSearchCompleter biased to
  60 km around the prayer, up to 5 suggestions; picking one flies the map there and names it) —
  and "590 ft from where you marked it" (`Measurement` with `.road` usage, so miles / feet here).
- **Time editor:** the location is a quiet chip under "when did you pray?" ("📍 49 Chambers St ›",
  green edge + "· moved" after a pick) instead of a full row above the buttons. Sheet 572 pt (540
  without the chip).
- Sim ✓: cluster → Isha's page (its pin lifted out), ··· → Change location → typed "Woolworth
  Building" → flew there, "590 ft…" → Set → back on Isha's page at 233 Broadway; ··· → Change time
  opened on the saved time; Change location → Cancel → back on Dhuhr's page with the list behind;
  the time editor's chip. Not tried: the typed address in the time editor's own picker (same card).

**2026-09-26 late — move a prayer's pin; build stamp.**
- **Where you prayed can be changed** (owner: "right now there is no way… ideally drag the map").
  `PrayerLocationPicker` (CursorSwift/PrayerLocationPicker.swift): a SwiftUI `Map` with a green pin
  fixed in the middle — drag the map under it; the pin lifts while moving and drops when it stops,
  the card shows the address (or your masajid by name; your ⭐ masajid are on the map), Set location
  lights up once it moved. The old spot is a small gray dot.
  - **Time editor:** a row under the score ("43 Park Row, New York · Change", or the masjid, or
    "Add where you prayed") opens it. The picked spot waits in the sheet ("moved · Save to keep
    it") and saves with Save (`onSave(date, spot)`).
  - **Map prayer-spot sheet:** one prayer → a green "Change location" under the address; a
    cluster → swipe a prayer right ("Move") or long-press it. After Set, the sheet closes, the
    pins redraw (`LocationViewModel.prayerMoved` re-publishes `prayers` — the @Query doesn't see a
    coordinate change) and the map centres on the new spot.
  - `PrayerViewModel.movePrayer` writes the spot, re-asks the masjid question (your masajid at
    once, else `MasjidDetector.check` after), rescores (a Friday Dhuhr can become / stop being
    Jumu'ah), recomputes the day, streak and widget.
  - Sim ✓: Asr moved in the time editor (coords + `mosqueName` "" after the re-check), a Maghrib
    in a cluster moved from the map (sheet closed, pin at the new spot).
- **Build stamp** (owner: "know which code push this is"): `BuildInfo.line` — "2.0 (8) · Sep 26
  at 5:33 PM · ba98814" — small at the bottom of the hamburger menu and under Settings' last
  section. The time is the executable's file date (any build); the hash comes from the
  `ShukrBuildStamp` Info.plist key = the `SHUKR_BUILD_STAMP` build setting. **Pass it on every
  device build:** `SHUKR_BUILD_STAMP="$(git rev-parse --short HEAD)"` (add "+" if the tree is
  dirty); scripts/testflight.sh does it. Commit before building so the hash is the real one.

**2026-09-26 late — "Perfect", Jumu'ah wording, widget "next", time wheel.**
- **Early → Perfect** (owner: "i dont love early"). `PrayerScoring.Grade.perfect` (rawValue
  "Perfect") and Insights' grade enum. Old rows still have "Early" stored in `englishScore`, so UI
  reads `PrayerModel.gradeWord` (computed from `numberScore`) instead — the map sheet does now.
  "Perfect day" (all five Perfect) keeps its name.
- **Jumu'ah never shows a grade** (owner: "it shouldn't say early for jummah, just say Jummah").
  `PrayerModel.scoreSummary` = "Jumu'ah at <masjid>" (or "Jumu'ah") instead of "Perfect · 100":
  the completion moment (`PrayerCompletionEvent.summary`), the list row's tap text, Insights'
  day detail. `gradeWord` = "Jumu'ah" (map sheet, stored `englishScore`). The time editor shows
  100 · "Jumu'ah" and the title "Jumu'ah" for one, so it agrees with Save. Not seen on screen (no
  real Friday masjid row in the sim); the logic is small.
- **Prayers widget "next"**: when the circle shows a prayer that hasn't started (the current one
  is prayed), it has the app's look — tracked "NEXT", name / icon at 55 %, a thin dashed ring
  (80 pt inside the 90 pt track). Sim ✓ (Asr marked → "NEXT Maghrib", check filled).
- **Time editor opens on the saved time.** The sheet opened on the device's time (the parent's
  `selectedEditTimeDate`, set in the same long-press that presents the sheet, arrived too late).
  `PrayerTimeEditSheet.init` now seeds `draft` from `prayer.timeAtComplete` itself, clamped to the
  range. Sim ✓: Dhuhr saved 2:24 PM opened at 2:24 (was 5:24 = now); saved 12:56 → reopened 12:56.

**2026-09-26 — Explore dock, My masajid, fine ring.**
- **Explore dock:** the map's explore button (`ExploreDock`, LocationMapView2.swift) opens in place:
  the glass circle springs out leftwards into Qibla · Prayers · Mosques (icon + label, the active
  one green) and a ✕. Items fan in; tapping the map folds it. It replaced the `MapExploreSheet`
  chooser, which is unused now. Picking Mosques still opens the list. Sim ✓.
- **My masajid** (`MosqueFavorites`, MosqueFinder.swift; standard defaults `favoriteMosques`, JSON
  name + lat / lon):
  - Add with the ☆ on a mosque's sheet, or long-press → "Add to My masajid" in the list.
  - They get a green-edged "MY MASAJID" section at the top of the list and star pins that never
    cluster. They're merged into search results even when a search misses them
    (`MosqueFavorites.merged`).
  - A favourite can't also be "don't recommend". Used by `MasjidDetector` first.
  - Sim ✓.
- **Tasbeeh ring default is "fine"** (was "alive").

**2026-09-26 — Apple Watch app + complications (built, not yet signed for devices).**
- **Targets** (added to the pbxproj by hand):
  - `shukrWatch`: a watchOS 11 single-target app, bundle `com.betternorms.shukr.watchkitapp`,
    embedded in the iPhone app via "Embed Watch Content".
  - `shukrWatchWidgets`: the complications, bundle `…watchkitapp.widgets`, embedded in the watch
    app; Info.plist is `shukrWatchWidgetsInfo.plist` at the repo root.
  - Synced folders: `shukrWatch/` (app + icon), `shukrWatchWidgets/`, and `shukrWatchShared/`,
    compiled into both watch targets.
  - Entitlements `shukrWatch.entitlements` / `shukrWatchWidgets.entitlements` both carry the app
    group `group.betternorms.shukr.shukrWidget`, so the watch app and its complications share
    defaults. It is a separate container from the phone's.
  - Both link Adhan.
- **Data:** `WatchPrayerCore.swift` computes the prayer day on the watch (same method mapping as
  `PrayerUtils`, Fajr-to-Fajr day, Isha to 11:59 PM, capped at the next Fajr). The iPhone's
  `WatchSync` (CursorSwift/WatchSync.swift, started in `shukrApp.init`) sends the WatchConnectivity
  application context: lat, lon, method, school, city, today's completed names, completedDay. It
  sends on scene active / background and in `pushCompletionsToWidget`, and never resends unchanged
  context. The watch's `WatchSession` saves it (`WatchStore.save`) and reloads the complications;
  `.backgroundTask(.watchConnectivity)` lets it land while the watch app isn't open.
- **Watch ring = the phone's circle (2026-09-27, quick fix):** `WatchPrayerRing` fills with time elapsed, 2.5 pt butt-cap
  arc on a 7 pt pale band, coloured by `WatchScoring.color` (a copy of `PrayerScoring`'s rule in
  shukrWatchShared/WatchPrayerCore.swift — PrayerScoring.swift also holds SwiftData code, so the watch can't compile it;
  keep the two in step). Upcoming: empty arc, dashed 1 pt track, NEXT, dimmed name. Tap → "ends 6:45 PM" ⇄ "54m left" +
  `WKInterfaceDevice.play(.click)`. Complications: `countsDown: false`, `.tint(entry.tint)` (score colour at the entry's
  date), timeline entries at every start / end **and** each grade change (`WatchScoring.gradeChanges`: +30 min, and the
  On time → Late point); circular upcoming = dashed ring + tiny NEXT. The watchOS 27 simulator runtime is installed now
  (Apple Watch Series 12 46mm, AEDA90A5…); DEBUG `-demoWatch` seeds New York / ISNA / Shafi'i so a standalone watch sim
  shows prayers. Sim ✓ the app's ring (red, filling, at 5:50 during Asr) and the tap; complications not seen (a fresh
  install didn't show in the watch's widget list).
- **Watch app:** the prayer ring (like the main circle), today's five times with ✓ for marked ones,
  the city. "Open shukr on your iPhone…" until a location arrives. Read-only: marking prayers and a
  wrist tasbeeh are next (they need WatchConnectivity messages back to the phone).
- **Complications (`PrayerComplication`):** circular (the ring drains live), corner (symbol + a
  curved gauge with the time), rectangular (name, ends / at, bar or countdown), inline. One
  timeline entry per prayer start / end.
- **Signing: done 2026-09-26.** After the owner signed in to Xcode again, a command-line
  `-allowProvisioningUpdates` device build registered both watch App IDs; the "No Accounts" error
  was the expired Xcode token. Full builds (with the watch) work now. Old note: the command-line tools can't
  register the new App IDs ("No Accounts"). Open `shukr.xcodeproj` in Xcode and build / run once
  (or visit Signing & Capabilities for shukrWatch and shukrWatchWidgets) so Xcode registers them
  with the app group. After that, command-line device builds use the downloaded profiles.
- Until then, to put a build on the phones: copy the pbxproj aside, remove the iOS target's
  "Embed Watch Content" phase and its shukrWatch `PBXTargetDependency` line, build and install, then
  restore the copy. Done 2026-09-26 for both phones. Never commit the stripped file.
- There is no watchOS simulator runtime on this Mac. Sim ✓ = the iPhone simulator build compiles
  and embeds `Watch/shukrWatch.app` with `PlugIns/shukrWatchWidgets.appex`. Never run on a watch.

**2026-09-26 — Zikr widget → task, and time estimates.**
- **Tap a task in the widget:** each row of the Zikr widget is its own button
  (`OpenZikrTaskIntent(taskID:)` → app-group `widgetZikrTask` + `widgetTasbeeh`). The app opens
  the Zikr page and `ZikrFocus.request(id)` scrolls that task's circle to the middle, ready to tap.
  The request is held in `ZikrFocus.pending` in case the wheel mounts later (cold launch). The rest
  of the widget still opens the Zikr page. DEBUG `-demoZikrFocus` does the same for the last task.
- **Estimates:** `TaskModel.secondsLeft(_:)` = counts left × your pace (the mantra's time-weighted
  `secondsPerCount`, else the task's own sessions), or the minutes left for a timed task. Nil for a
  count task with no history. `zikrEstimateString` → "~4 min" / "~1h 10m" / "<1 min".
  - Shown on each task circle ("~2 min" under "0 of 100"), in the page summary ("0 of 3 tasks done
    · about 12 min to go"), on the widget (rows "5/100 · ~4 min", the header "3 left today ·
    ~14 min"), and on the Lock Screen card.
  - Tasks with no history are left out of the total.
  - Timed tasks show counts instead (owner: "~1 min" under "0 of 1 min" was redundant):
    `TaskModel.countsAtGoal` = today's counts + minutes left ÷ pace → "~780 counts".
    `estimateNote(_:)` picks time for count goals and counts for timed ones (circle note and widget
    rows). The page and widget totals stay in time.
- **Compile-time trap:** long `Text(a + (b.map { … } ?? ""))` string expressions stalled the
  widget's type checker for 10+ minutes. Keep them in small helper functions (`rowTrailing`,
  `lockHeadline`, `summaryText`).
- Sim ✓ (app side via `-demoZikrFocus`, estimates on the page). The widget tap itself is untested
  in the sim.

**2026-09-26 — Lock Screen widgets + Controls.**
- **Prayers** (`PrayerLockScreenView` in PrayersWidget.swift; same prayer as the home circle):
  - circular: the time left drains round the ring live (`ProgressView(timerInterval:)`), with the
    symbol and name inside; before a prayer starts, symbol, name and "5:32";
  - rectangular: name, "ends 6:48 PM" / "at 5:32 AM", and a live bar or "in 2 hr 30 min";
  - inline (above the clock): "Asr · ends 6:48 PM".
- The Prayers timeline has an extra entry at the shown prayer's start and end (2–3 entries), so
  the Lock Screen switches dashed → live on time; the views use `entry.date`, never `Date()`
  (WidgetKit can render future entries ahead of time).
- **Home-screen Prayers widget v2 (2026-09-27, notes #1):** five display-only `PrayerDot`s along
  the bottom between the corners (done = score colour, started = outlined, later = dim; prayer
  day = `completedPrayerScoresToday`); the bottom corners come from Edit Widget
  (`ConfigurationAppIntent.bottomLeft / bottomRight`, `WidgetCornerAction`: Qibla / Tasbeeh / Daily
  Ayah / 99 Names / None; defaults Qibla / Tasbeeh; "Bottom right" leaves out the left's choice via
  `BottomRightOptions` — two-way dependencies are a circular type reference — and `corners` shows
  the next unused one if both still match). The times list (`TimesListView`, app look) doesn't
  stick: `WidgetListState` stores when it opened, the timeline adds one ring entry 30 s later, a
  tap while it's up closes it. The gallery / Edit preview always shows the ring. The Lock Screen
  families share the intent, so their Edit Widget also lists the two (unused) corner settings.
  DEBUG `-demoWidget "Fajr=1.0,Dhuhr=0.72" [-demoWidgetCorners dailyAyah,names] [-demoWidgetList]`
  (`off` clears) feeds the widget fixed scores for screenshots.
- **Score colours + centring (2026-09-27, notes #40):** Edit Widget has "Score colours" (`scoreColors`,
  default on); off, a prayed dot is `Brand.sage` whatever the score (`PrayerDot(colored:)`, list and
  row). DEBUG `-demoWidgetPlain` with `-demoWidget`. The ring is lifted 24 pt (`ringLift`) so it sits
  evenly between the top edge and the dots (the full 36 pt row put it too high). Follow-ups the same day
  (owner): with Score colours off a prayed dot is plain grey (`Color.gray`, not sage); the dashed
  "next" ring is secondary 0.6 at 1 pt (was 0.35 / 0.75 pt — hard to see in dark mode); the times
  list's rows share the space (`.frame(maxHeight: 22)`, tighter header / padding) so Isha fits a
  ~158 pt widget; `corners` shows a doubled button as picked (it used to swap one silently). **Corner pickers
  stay two enums** (right leaves out the left; the owner is fine with a doubled button): a sized
  `AppEntity` list ("Bottom buttons", add up to two) was tried — its picks never reached the widget
  (the timeline got `[]`, even for the default; `entities(for:)` never ran) — and a picker of pairs
  was rejected. Changing a parameter's type under the same name leaves stale saved values: rename it.
- **Since 2026-09-27 (quick fix):** the live ring and bar fill forward (`countsDown: false`, still
  the stock timer-driven ProgressView — custom drawing goes stale on a widget); not started → a
  thin dashed ring (circular; NEXT removed there in c404e44). The circular's prayer icon is 9.5 pt medium in both states
  (was 12; owner, 2026-09-27: room for the name and time). Keep What's new topic titles describing the current state.
- **Zikr** (MoreWidgets.swift): circular = the overall ring (`accessoryCircularCapacity`) with
  beads or ✓ inside; rectangular = "Zikr · N left", the next task "Subhanallah · 0/10 min", and a
  bar.
- **Name of the Day:** rectangular = the Arabic beside the name and meaning; inline =
  "As-Samad · The Self-Sufficient".
- **Controls (iOS 18):** `QiblaControl` / `TasbeehControl`, buttons for Control Center, the Lock
  Screen's bottom corners or the Action button. They run `OpenCompassIntent` / `OpenTasbeehIntent`
  (open the app to the qibla map / the Zikr page).
- Sim ✓: all three widgets show in the Lock Screen widget gallery with real data. The controls are
  not tried in the sim.
- **Apple Watch (not built):** Apple doesn't allow third-party watch faces, only complications on
  any face. That needs a watchOS app target, and the watch can't read the phone's app group.
  Prayer times are pure maths (adhan-swift) from a location and a method, so the watch would
  compute them itself; marking prayers / zikr would need WatchConnectivity. Plan it with the
  owner first.

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

**Release / TestFlight:** see "Shipping a TestFlight build" below. 2.0 (8) is live on the public
link (2026-09-26, without the watch app).

## Shipping a TestFlight build (no Xcode sign-in needed)

Everything goes through the team's **App Store Connect API key**, so nobody has to sign in to Xcode.
Before this, Xcode's account token kept expiring ("missing Xcode-Token" → "Failed to Use
Accounts"). That line still prints in logs and is harmless now.
- Key: ID `6K2RUXRJ92`, issuer `60a885ac-0315-4323-974d-57783a7392a2`, Admin role.
- The file is at `~/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8` on the owner's Mac. Never
  read it out, print it or commit it; the scripts only pass its path.

Steps, when the owner says "push a new build":
0. **App Store submission checklist:** archive with `SHUKR_APPSTORE=1 scripts/testflight.sh` so the
   What's new screenshots (~230 KB, `wn-*.jpg`) are left out — or accept them (the page never shows
   in production) — and check the archive really drops them:
   `ls build/shukr-*.xcarchive/Products/Applications/shukr.app | grep -c wn-` → 0.
1. **`scripts/testflight.sh`** (for the App Store release itself: `SHUKR_APPSTORE=1 scripts/testflight.sh`, which leaves out the What's new screenshots) bumps `CURRENT_PROJECT_VERSION` everywhere (12 occurrences, the
   watch targets included), archives Release (iPhone app + embedded watch app), and uploads. The
   export runs with the system PATH, since Homebrew's rsync breaks it. Commit the bump afterwards.
2. **Write tester notes**: start from `scripts/whatsnew.py testflight --since <previous build's
   commit>` (the WhatsNew.json entries), then `TestFlightNotes-<version>.<build>.md` with a "What
   to Test (paste this)" block (≤ 4000 chars, **no emoji** — Apple rejects characters outside the BMP) and a
   by-build record. See `TestFlightNotes-2.0.8.md`.
3. Wait for processing: `scripts/asc.py builds` shows VALID, usually 5–30 min after upload.
4. **`scripts/asc.py release <build> <notes.txt>`**:
   - sets What to Test (en-US);
   - adds the build to every external group — "test" is the one behind the public link
     https://testflight.apple.com/join/GW5j85jk; the internal group gets builds automatically;
   - submits for beta review and prints the external state. `IN_BETA_TESTING` = testers have it;
     `WAITING_FOR_BETA_REVIEW` = Apple is reviewing.

   To pull the notes block out of the .md, see the python one-liner in this session's history, or
   just copy it into a .txt.

`scripts/asc.py` is a stdlib + openssl App Store Connect client. `groups` lists the beta groups, and
`scripts/asc.py GET /v1/...` makes any raw call. App id `6743040873`, team `7R387XZ2Y7`.

For device builds with the key (plus `SHUKR_BUILD_STAMP="$(git rev-parse --short HEAD)"` for the build stamp), add these to the xcodebuild line:
`-allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8
-authenticationKeyID 6K2RUXRJ92 -authenticationKeyIssuerID 60a885ac-0315-4323-974d-57783a7392a2`.
Phones:
- 13 Pro Max `00008110-001C041C2203801E`
- 15 Pro `00008130-00027DDE0AE8001C` (often "unavailable" when it's away)

Install with `xcrun devicectl device install app --device <udid> build/device/Build/Products/Debug-iphoneos/shukr.app`.

Uploaded: 2.0 (3) 09-24, (6) 09-25, (7) and (8) 09-26, (9) 09-27 (first with the Apple Watch app).
(11) 09-27: watch ring / Azkar sort menu / What's new follow-ups, on the public link the same day (IN_BETA_TESTING).
(10) 09-27: the iOS 26 Settings-rows fix (pager drag `minimumDistance: 0` → 5), on the public link the same day (IN_BETA_TESTING).
Note: on a real iOS 26.6 phone the dead rows showed in Release / TestFlight builds and not in Debug installs; in
the iOS 26.5 simulator Debug was dead too. Verify gesture fixes with a **Release** device install
(`-configuration Release` + devicectl), not only Debug.
2.0 (8) went to the public link 09-26. 2.0 (9) went to the public link 09-27 (IN_BETA_TESTING right away).
When a build goes to external testers, remind the owner about the share card's "download on the
App Store" wording (see Share card).

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

## First-run setup (notes #18 + #6) — mockups only (2026-09-28)

DEBUG-only `CursorSwift/OnboardingMockups.swift`, not wired into the launch; reads the saved location / method for real
times, writes nothing, asks for nothing. `-demoOnboarding location|method|madhab|review` (Continue walks through them),
`-demoOnboardingBismillah ring|sweep`. The look follows the everyday opening: plain background, the sage `SetupRing` at the
top as progress (a quarter per step, the step's symbol inside), light rounded type, a calm sage-tint primary button, Skip
top right. Steps mocked: location (the why, then "Allow location" / "Enter a city instead"), method (Automatic first —
"follows where you are · ISNA here" — then ISNA / MWL / Umm al-Qura / Egyptian / Karachi, today's times live), madhab
(Shafi'i vs Hanafi cards with a shadow sketch and both Asr times, "only Asr changes"), review (tappable rows with the sell
lines, orange nudges for While Using / notifications off, Bismillah in two looks: the circle drawing round بِسْمِ اللَّهِ
and breathing, or a capsule with the welcome's light sweep). Waiting for the owner's pick before building the real flow.

## Masjid-aware prayers (owner idea 2026-09-25 — parts 1, 2 and most of 4 built 2026-09-26)

**Built:**
- **Schema 2.2.0:** `PrayerModel.mosqueName` (nil = not checked, "" = not at a masjid), with
  `atMasjid`, `isJumuah` and `displayName` ("Jumu'ah"). `setPrayerScore` gives a Jumu'ah 1.0, so
  the time editor agrees.
- **`MasjidDetector`** (CursorSwift/MasjidDetector.swift):
  - The spot is checked against your own masajid (`MosqueFavorites`, < 100 m, no network) first,
    then `MosqueSearch.find` around it; the nearest mosque within 75 m wins. "Don't recommend"
    mosques never count.
  - Cached per ~100 m cell; 2 s between searches, since MKLocalSearch is rate-limited.
  - Runs after every in-app mark (`togglePrayerCompletion`, which then rescores the day). On
    activation, `catchUpMasjidChecks` checks rows marked by the widget / notification, and history
    at up to 12 new spots per launch, Friday Dhuhrs first, then newest.
- **Where it shows:** the list row reads "Jumu'ah" plus a small sage mosque mark; prayer-spot pins
  prayed at a masjid use the mosque glyph; `PrayerSpotSheet` rows show "Jumu'ah" and the masjid's
  name.
- DEBUG `-demoMasjidCheck` creates a late Friday Dhuhr at your first favourite masjid plus a prayer
  400 m away, then logs `MASJIDCHECK`. Sim ✓: Dhuhr 0.68 → Jumu'ah 1.0 at Assafa; the away prayer
  → "".

**Loose ends closed the same day (owner: "finish it … no loose ends"):**
- **Offline:** `MosqueSearch.lastSearchFailed` is set when every query failed for a reason other
  than "no results". The detector then leaves `mosqueName` nil, so the row is retried later instead
  of being marked "not at a masjid" for good.
- **Instant at your own masajid:** `togglePrayerCompletion` records the location first and checks
  `MasjidDetector.favoriteMasjid(near:)` (no network) before scoring, so the completion moment
  already says "✓ Jumu'ah / Jumu'ah at <masjid>" (no grade word; see 2026-09-26 late). Anywhere else the search runs after the mark. If that turns
  a prayer into Jumu'ah, `.prayerCompleted` is posted again, so the moment replays with the right
  name and score.
- **Widget / notification marks** (extension, no favourites, no search) are checked on the next
  activation by `catchUpMasjidChecks`, and the day is rescored then.
- **Map filter:** the prayer bar's range menu has "Only at a masjid"
  (`LocationViewModel.onlyAtMasjid`, in the filter sentence and `filtersActive`).
- **Duas at my masajid (part 3)** — `MasjidArrival` in CursorSwift/PlaceMoments.swift:
  - Opt-in: Settings → Masjid → "Duas at my masajid", plus a "Preview the notification" row.
    Turning it on asks for Always location.
  - `CLMonitor("shukrMasajid")` watches 100 m circles round up to 20 of My masajid. It re-syncs when
    favourites change and is picked up again in `shukrApp.init`, including a background relaunch
    for a region event.
  - Notifications: entering = "Allahumma-ftah li abwaba rahmatik", leaving = "Allahumma inni
    as'aluka min fadlik"; Arabic + transliteration + meaning, time-sensitive, at most once per
    masjid and direction every 3 h.
  - Info.plist: `NSLocationAlwaysAndWhenInUseUsageDescription` + the Always string now explain
    this feature only.
  - **Traps:** CLMonitor names must be letters only ("shukr.masajid" crashed with "Monitor name is
    not valid"), and only one monitor per name per process ("already in use"). `start()` never
    creates a second.
  - Sim ✓ (simctl location + `privacy grant location-always`): entering and leaving banners at
    Assafa.
- **Still to verify on the phone:** a real Jumu'ah at the masjid (GPS indoors); the arrival
  notification with the app killed (background relaunch); "Only at a masjid" in the map bar (not
  looked at in the sim). The open question stands: should any jama'ah prayer at a masjid score
  full, or only Jumu'ah? Only Jumu'ah is implemented.

Original plan:

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

## Makkah & Madinah (owner idea, 2026-09-26)

**Built — the welcome easter egg:** `HolyCityWelcome` (CursorSwift/PlaceMoments.swift) follows
`EnvLocationManager.locationUpdates` (throttled to 30 s). Within ~6 km of the Kaaba it posts
"Welcome to Makkah" ("May Allah accept your visit to His House…"); within ~5 km of Masjid an-Nabawi,
"Welcome to Madinah" ("The city of the Prophet ﷺ…"). Once per visit: it re-arms after you've been
more than 50 km away, and a first launch counts as away. It only fires while the app gets location
(foreground). Sim ✓: "Welcome to Madinah" banner.

**Wish list — the Umrah companion (not built; plan with the owner first; "a hefty thing"):**
- Know you're there: the welcome above, then offer "Are you doing Umrah?".
- **Umrah tracker:** ihram (intention + talbiyah), tawaf — 7 circuits counted like the tasbeeh,
  maybe by tapping at the Black Stone line; the 2 rak'ah; Zamzam; sa'i — 7 laps Safa ↔ Marwah;
  halq / taqsir. Save each Umrah with its date as a record.
- Duas for each step (talbiyah, entering the Haram, between the Yemeni corner and the Black Stone,
  on Safa and Marwah), sourced carefully. Needs the same knowledgeable review as the Tasbih Fatimah
  reminders.
- Must-dos and common mistakes as a checklist; Madinah etiquette (Rawdah, salam at the grave).
- Open questions: how much is guidance vs tracking; offline content; Hajj later?

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

## Share card — CHANGE ON RELEASE

The Daily Ayah share button (`DailyAyahView`, a `ShareLink`) sends only the image (`AyahShareCard`,
three looks), with no caption or link (owner, 2026-09-25). The line under the shukr mark is
`AyahShareCard.footer`.
- **Now (beta):** "join the beta on TestFlight" (owner, 2026-09-26). Testers get the app through
  the public link `https://testflight.apple.com/join/GW5j85jk`.
- **When shukr is live on the App Store:** change `AyahShareCard.footer` back to "download on the
  App Store", and ask the owner whether to add the App Store link.

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
**Axis lock:** the gesture starts at 5 pt (`minimumDistance: 5`) and decides the axis at 6 pt of
movement, before the pager's own pan reaches its 10 pt slop. **Never `minimumDistance: 0` on the pager** (2026-09-27):
a zero-distance drag claimed every touch, and on iOS 26 that cancelled the Settings Form's row taps (pickers, button /
navigation rows) — Debug and Release alike in the iOS 26.5 simulator; iOS 27 unaffected. Build 9 shipped with it dead. Vertical → `live.pagerLocked`
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
`numberScore` = points / 100: **Perfect** (≤ 30 min after the adhan; called Early until 2026-09-26) 100 · **On time** (first
half of the rest of the window) 99–80 · **Late** (second half) 79–60 · **Qaza** (after the
window) 40 · **Missed** nil/0. Linear from 100 at 30 min to 60 at the window's end, so the
only drop is 60 → 40. Qaza counts on purpose (the app gamifies praying; late beats never).
Day score = average of the five, unmarked = 0 (`PrayerScoring.dayScore`). Colours: Perfect green,
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
- **Streaks from history (2026-09-27, owner-approved fix):** `checkToResetStreak()` (app activation + the start of every
  `calculatePrayerStreak`) now calls `refreshStreaksFromHistory()`: the days BEFORE today are recounted from the prayer rows
  (consecutive days ending yesterday with all five qualifying — day streak by `gradingCriteria`, in-time days by score ≥ 60;
  walked back from yesterday a week at a time, stopping at the first day that breaks both runs — separate cut-offs for
  the day streak and in-time days, ≤ ~1000 days); today stays with the incremental code, which adds it once and posts its
  celebration. Only changed values are written (each write re-renders what's bound to those keys); a new max's date is
  the day that ended the run. The first recount on an install logs old → new (streak, in-time, both maxes) and keeps the
  line in the app group key `streakRecount.firstRun`. Idempotent
  and silent (no celebration for a past day). Fixes: a prayer of an earlier prayer day marked late (watch mark delivered after
  Fajr, widget / "I already prayed" around Fajr, a time edit on an old prayer) never counted, and the next day's gap check
  reset the streak to 0. `PrayerViewModel.recomputeStreaks()` (saves, then
  `calculatePrayerStreak`) is there for marks made elsewhere, but the watch's `.watchMarkedPrayer` handler doesn't need it
  (Sami, round 8): watch marks and unmarks set `widgetWroteStore`, so `reconcileAfterWidgetWrites()` already recomputes,
  even with the app open. Perfect day has no
  streak, nothing to recount. DEBUG `-demoStreakBackfill` (writes rows; sim only): marks the two days before today, fakes a
  stale streak (1, last counted 3 days ago), recounts twice — sim ✓ 1 → 2, then 2 again.
- **In-time days** (keys still `onTimeStreak`, `maxOnTimeStreak`, `lastOnTimeStreakDate`):
  consecutive days with all five prayed within their windows — no Qaza, none missed (≥ 60,
  `PrayerScoring.inWindowFloor`). Owner, 2026-09-25: "days where there was no qaza". Named
  "in-time", not "on-time", because On time is already a grade (80–99). It was all five
  Early / On time (≥ 80) for a day. **Perfect day** (`lastPerfectDay`): all five **Perfect** (was "Early").
  Both in `updateDayMilestones`, once a day, posting `.onTimeStreakContinued` / `.perfectDay`.
- **Top bar** (`TopBar` + `StreakLabel` in Utils.swift): tap the city → the streak for 5 s; tap
  the streak → in-time days → max. Once the day's done (the circle's summary condition) the streak
  stays up instead of the city (owner: keep the city otherwise). Celebrations: heart goes green,
  number rolls up, hearts float; the on-time beat follows ~2.4 s later with sparkles.
- **Completion moment, smooth again (2026-09-27, owner: "not the same quality as it was"):** marking updates the row
  at once, so the circle swapped to the next prayer / the day summary (the new 0.7 s crossfade, the dashed NEXT look)
  in the frame the flourish began, and it showed through the flourish's fade-in; the list hid its "N done" footer
  (the day complete) and dropped the circle ~19 pt, then unfolded all five mid-sweep. Now `MainCircleView.heldPrayer`
  (set from `PrayerCompletionEvent.prayerName`) keeps the marked prayer drawn until the flourish ends; the flourish
  goes in at once (its arc sits on the prayer's own) while the content fades out in 0.25 s; at the end the held
  prayer is dropped with animations off (no Maghrib → Isha morph) and the content fades in. The list keeps the row
  (`lingering`, keyed by the row's name — "Dhuhr" for a Jumu'ah) and the footer for `CompletionFlourish.duration`;
  the perfect-day cascade starts after it. Unmarking is unchanged. DEBUG `-demoPrayerStartSheetOpen` (with
  `-demoPrayerStart…ThenMark`) marks from the open list; `-demoPrayerStartPrayer Isha` completes the day. Sim ✓
  frame by frame (simctl recordVideo — variable frame rate, so pick frames by index: `fps=10,select=between(n,…)`),
  all three paths; Release builds.
- **Completing a prayer** (`CursorSwift/PrayerCompletionFX.swift`): haptic, `.prayerCompleted`,
  the circle's `CompletionFlourish` (arc sweeps closed in the score colour, glow, "✓ Asr ·
  On time · 88"), the row's `CompletionDotPop`. The list folds done prayers into a footer row, "✓ N done ⌄" (tap to show
  them; the words stay "N done" and only the chevron turns — swapping to "hide done" morphed oddly), under a divider like the rows' with even air above and below (2026-09-25;
  it used to hang under the list with a bare gap; a top row of score dots was tried and dropped —
  owner); all five come back when the day's complete; perfect day pops the
  dots in turn and shows "✦ perfect day".
- **Map buzz** (qibla mode, `LocationMapContentView`): a heavy buzz once a second the whole time you're
  lined up (`.task(id: aligned && inQiblaMode)` loop), stopping when you turn off the line — owner,
  feedback 6FB814B9 (the once-per-line-up version, d932ca2, is replaced).
  NextTag uses `NextLabelTuning.defaults` in Release (the playground's AppStorage is DEBUG only) and
  draws in `tertiaryLabel` scaled by opacity / 0.3 (primary 0.3 read darker). What's new hides "Open
  in shukr" for a link outside `WhatsNew.links`.
- **Qibla haptic** (2026-09-27): `checkToTriggerQiblaHaptic` fires only when `circleOnScreen`
  (active, Salah page, `WelcomeTarget.canLand`, `CircleCover.active` empty, settled) and the
  circle's own map isn't up. `CircleCover` (mainCircle.swift) is the register for things presented
  over the Salah page that `somethingCovers` can't see: the ☰ popover, What's new, a prayer row's
  time editor — add any new one there. The old
  `@Published allowQiblaHaptics` flag (toggled on appear / disappear, left on by the pager and
  sheets, and re-rendering everything on each write) is gone. NEXT is a small tag (9 pt medium, tracking
  2.5) at `offset(y: -31)` in the app (~12 pt under the qibla arrow at its highest, r 80; its gap
  to the name ~3× the name–caption gap so it reads as separate), 6 pt at `-15` in the home widget;
  never on the Lock Screen widget (dashed ring only). The app's tag is `NextTag` (NextLabelPlayground.swift; defaults −31 / 9 / 0.3 / 2.5 — the original look. The owner's playground values, −28.76 / 8.72 / 0.263 / 2.57, were the default for one commit (81593de, feedback CC72A6E8) and he preferred the original, 2026-09-27. `NextLabelTuning.clearSavedTuningOnce()` in shukrApp.init forgets saved playground JSON once per install (flag `clearedNextTagTuningForOriginal`). Release always uses the defaults. Sim trap: `simctl spawn … defaults write` writes a second, global plist the simulator merges in, so the app can't remove that value — edit prefs through the app, not simctl), tuned live in DEBUG Settings → My Dev Stuff → NEXT label playground… (offset / size / opacity / spacing, JSON in `nextLabelTuning`; Copy values → paste the JSON into `NextLabelTuning`'s defaults; `-demoNextPlayground`). **Dev toggle** Settings → My Dev Stuff →
  "Next prayer": NEXT + dashed ring / dashed ring only (`NextLabel.key` in the app group, so the
  widget follows; reloads timelines). DEBUG `-demoNextLabel on|off`.
- **One row per prayer in the loaders (2026-09-27):** `loadTodaysPrayerObjects`, `loadPrayerObjects(for:)` and the V2 loader
  also had `fetchLimit = 5`; they now fetch the day and keep one row per name via `PrayerViewModel.onePerPrayer` (a
  completed row wins). With a sixth row a prayer used to drop out of today's list (seen: Isha missing, Dhuhr twice).
- **Duplicate prayer rows (fixed 2026-09-27):** `fetchPrayerTimes` fetched the day's rows with `fetchLimit = 5` sorted by
  time; once a day held a sixth row (a moved / edited / imported one), Maghrib and Isha fell outside the five and a new
  pair was inserted on every refresh (the sim had 285 Isha rows for one day). The limit is gone and a completed row wins
  over an unmarked one. `PrayerViewModel.removeDuplicatePrayerRows(in:)` runs at launch (shukrApp, after the scoring
  pass): per calendar day + name it deletes extra UNMARKED rows only (never a completed one), backing up to
  `Library/Backups/shukr.store.before-dedupe` first; a no-op on a healthy store. Sim ✓: 850 removed (910 → 60).
- **Open problem (2026-09-27): the map hangs in the iOS 26.5 simulator** — opening it (arrow or `-demoMosques`) pins the
  main thread at 100 % in an AttributeGraph cycle ("cycle detected through attribute"), LocationMapContentView rebuilt
  ~250×/s with "@self changed". Same on 9df0676 (this morning, when it worked in the sim), on a second iOS 26.5 simulator
  and with a fresh store — so not today's code or data. The owner's iOS 27 phone opened it fine at 9:25 PM, and so did
  his wife's real iPhone 15 Pro on iOS 26.6 with build 11 from TestFlight (owner's recording, 2026-09-27: qibla arrow →
  map opens). So it's the simulator environment, not a tester bug; don't chase it in the iOS 26.5 sim.
- **Frozen ring while moving (fixed 2026-09-27):** `MainCircleView` made its 1 s timer inline in `body`
  (`.onReceive(Timer.publish(…).autoconnect())`); it observes `CompassState`, so every heading update re-rendered it and
  replaced the timer before it fired — `currentTime` froze and a started prayer showed an empty ring (owner: Isha at 8:28 PM).
  Now `static let ticker` + `currentTime = Date()` on appear and on scene active. Same fix in `TimeColorFadeProgressBar`.
  **Never create a publisher inline in `body`.** DEBUG `-demoCompassJiggle` turns the heading 5×/s (the sim has no compass);
  with `-demoPrayerStart`, sim ✓: 0 ticks in 15 s before, 18 in 20 s after, the ring filling.
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
  (Perfect / On time / Late) is a scrubber; a Qaza time parks the marker at the end, gray. Scrubbing
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

**List filter + reset (2026-09-27, notes #3):** an All · Learning · Known segmented control under
the header ("Known 12" — counts follow the search), combined with search; an empty state per
filter. ··· in the toolbar → "Reset progress" (confirmation alert) clears `namesKnown`. Sim ✓.
"Allah" (id 0) is listed under All but never in Learning / Known or any count (like the header's
"of 99 known"); it can still be marked known.

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

**Map style: the globe (2026-09-27, notes #15)** — `MapModes.swift`. The map / map.fill toggle became
a globe (`globe.americas.fill`, or europe.africa / asia.australia by the user's longitude); one tap
toggles Standard (`MKStandardMapConfiguration`) ⇄ Satellite with labels (`MKHybridMapConfiguration`)
via `preferredConfiguration`, remembered in `@AppStorage("mapMode.satellite")`, applied in `MapView`
only when it changes. An Apple Maps-style "Map Modes" sheet (live snapshot cards, Traffic, Labels)
was built the same day (75e7d7d) and removed — owner: just the globe, no traffic. Sim ✓.
The map follows the app's light / dark / auto setting (`modeToggleNew`; auto = dark outside
Fajr–Maghrib, `PrayerViewModel.isDaytime`) via `MKMapView.overrideUserInterfaceStyle` — it stayed
light in dark mode before. The ? is its own glass circle under the globe / locate capsule, like Apple
Maps' 3D button. Sim ✓ (dark).

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

**Main circle "next" → "now" (2026-09-27; redesigned the same day, owner: "all of these options
suck").** The track (`CircleTrack`, PrayerCompletionFX.swift) *is* the state:
- **Dashed** (1 pt, 3 / 5 dashes, secondary 0.35 — the old future-prayer line, moved out to the
  200 pt track) while the circle shows a prayer that hasn't started: an upcoming prayer, and the
  summary circle's next Fajr (sheet closed). "NEXT" (an overlay above the name, offset −13, so the
  name never moves) and the name / icon at 55 % stay. Next Fajr keeps its own time text ("in 8h 5m"
  ⇄ its window) — the only future prayer shown that way. The countdown is the app's `timeUntilStart`
  in a 1 s `TimelineView` (the summary isn't redrawn by the circle's tick); `.relative` said
  "in 8 hr, 5 min".
- **Solid** 12 pt band for a prayer that's on, a missed one, the day's score (sheet open), while a
  completion sweeps and while the in-circle tasbih offer is up.
- `MainCircleView.trackSolid` 0…1, set by `settleTrack(trackWantsSolid)`: when the circle is on
  screen (`circleOnScreen`: app active, Salah page, `WelcomeTarget.canLand`, settled 0.6 s) it
  **expands** like the welcome's ring (the band grows from a hairline while the dashes fade;
  spring 0.75) or **shrinks** (0.6 s) — after a mark it waits 0.45 s so it happens once the green
  sweep has faded (`flourishEndedAt`); off screen it just switches. Reduce Motion: the band fades
  at full width. The start also gives one soft haptic (`playStartMoment`, on "Asr|next" →
  "Asr|now" with the same on-screen guards). The fade / draw / glow looks and their picker are gone.
- The welcome lands as the dashed ring when `WelcomeTarget.trackDashed` (set by `settleTrack`).
- Prayers widget: the dashed track (no inner ring) for a prayer that hasn't started, no animation.
- An upcoming prayer's progress is 0 (it was 1 in a clear colour and sprang from full to empty).
- **Preview** (DEBUG, Settings → My Dev Stuff → Preview prayer begins): `PrayerStartPreview.request`
  → the Salah page, the circle's prayer drawn "next" (`preview` overrides the status it draws with —
  visual only), then "now" (the expand + haptic), then back. No rows, test times or notifications
  touched (sim ✓: rows' hash unchanged). `-demoPrayerStartPreview` does it from Settings; `-devStuff`
  opens My Dev Stuff (simulated taps don't reach that list).
- DEBUG `-demoPrayerStart [-demoPrayerStartPrayer Fajr] [-demoPrayerStartThenMark]
  [-demoPrayerStartOnZikr]` starts a prayer 6 s after launch (moves the loaded rows — they get saved,
  simulator only); `ThenMark` marks it 4 s later (the shrink). Sim ✓ frame by frame: expand, shrink
  after the sweep, summary next Fajr → Fajr, welcome landing dashed.

**Custom task names — schema 2.4.0 (2026-09-27, notes #7).** `TaskModel.customName` (optional),
plus the reminder fields for notes #11 in the same lightweight bump: `reminderKind` ("time" /
"prayer", nil = off), `reminderTimeMinutes`, `reminderPrayer`, `reminderOffsetMinutes`,
`reminderWeekdays` (bitmask, Sunday = bit 0; nil = every day). Backup `…before-2.4.0` made; sim ✓.
`TaskModel.title` = own name else mantra; `mantraLine` = the mantra when there's an own name.
Medium Zikr widget rows (2026-09-27 review): progress / goal only (no per-row estimate; the header
keeps the total), `fixedSize` + top layout priority so a long name truncates first, the mantra only
when name + mantra fit whole (`ViewThatFits`), and `ViewThatFits(in: .vertical)` over 6 / 5 / 4 / 3
rows (tighter padding for 5–6) so each phone's widget height is used — 6 fit on the 17 Pro sim.
DEBUG `-demoManyTasks` seeds six tasks, one with a very long name.
Shown via `ZikrCircleFace(mantraLine:)` (wheel, arranging grid), the mantra page's task circles
(own name as title, "goal 100" under it), the Zikr widget rows (medium: the mantra quieter after
the name), the Lock Screen card (`name`), the results card ("After Fajr · 5 of 100 today"),
alerts, the reorder list. Session titles stay the mantra (history snapshot). Set in the create /
edit task sheet's "Name (optional), e.g. After Fajr" field. Widget not looked at in the sim.

**Zikr task reminders (2026-09-27, notes #11)** — `ZikrReminders` (CursorSwift/ZikrReminders.swift).
- Set per task in the create / edit task sheet: a "Reminder · Off ›" capsule → `TaskReminderSheet`
  (Off · At a time · Around a prayer; the Fajr alarm's wheels: 0–60 min · After / Before · prayer;
  weekday chips; Save gray until changed). `ReminderDraft` holds it until the task is saved.
- Planned by `NotificationScheduler.plan` (shared budget): one-shot per day a week ahead, ids
  "zikr.<task uuid>.<prayer day>" (owned → rebuilt each run), priority 1 within 48 h, 3 beyond.
  Skipped for today when the task is already done; finishing a task in a session removes today's
  pending one (`taskMaybeDone`, from `saveSession`). Deleting a task reschedules.
- Content: title = the task's title, body "Bismillah · 50 counts · ~3 min"; category
  "ZikrReminder": Start now (foreground) / tap → `ZikrReminders.open` (the widget rows' app-group
  flags + a post that PrayerTimesView handles when already open → Zikr page, `ZikrFocus`),
  Later (30 min) → a one-off "zikrlater.<task>.<ts>" (not owned, survives reschedules). "Skip
  today" was removed (2026-09-27 review).
- 2026-09-27 review fixes: every task delete goes through `TaskModel.delete(_:in:)` (saves, then
  reschedules — the wheel's and the grid's deletes used to leave reminders pointing at nothing;
  sim ✓ "removed 7"); the task sheet saves explicitly (a reminder only in memory was lost when the
  app was killed before autosave); earlier days' delivered reminders (+ "later" ones) are cleared
  like prayer ones (`isStaleDelivered`); the reminder sheet says "Notifications are off · Open
  Settings" / "shukr can't notify you yet · Allow" / "Needs your location for prayer times"
  (untested — the simulator can't change notification permission); a prayer-based reminder with no
  saved location is logged.
- Sim ✓: 10 min after Fajr, Saturday off → six pending (Sun–Fri at Fajr + 10); a clock-time
  reminder fired as "Subhanallah · 10 min". Actions not tappable in the sim — untested.

**Prayer notification scheduling — `NotificationScheduler`** (CursorSwift/NotificationScheduler.swift,
2026-09-27, notes #10). Everything scheduled goes through it; it owns iOS's 64-pending budget.
- ~7 days ahead: the next two prayer days that are still ahead get Start / Mid / End (nudges per
  Settings), days 3–7 Start only; priorities 0 (near starts) / 1 (near nudges) / 2 (far starts),
  trimmed to `64 − other pending − spare 4`. Completed prayers skipped (one fetch over the range).
- Ids are dated: `PrayerNotificationID` (Models/PrayerDay.swift, both targets) →
  "2026-09-27.FajrStart"; `parse` also recognises the old undated "AsrMid". Only ids the scheduler
  owns are removed — never `removeAllPending…` — so snoozes ("snooze-<uuid>") survive.
- Diffed, not rebuilt (2026-09-27 review): a request is the same when its id, minute and wording
  (title / subtitle / body) match; only changed / gone ones are removed and only new / changed ones
  added, and a run with nothing to do logs nothing. It used to remove and re-add ~55 requests on
  every re-plan (every 500 m / 30 s while moving — a suspect for the compass freezing while moving).
- Earlier days' delivered prayer notifications (and legacy undated ones) are removed on each run,
  so Notification Center still shows only today's, as when "AsrStart" replaced yesterday's.
- `cancelUpcomingNudges` (AllModels, runs in the widget too) removes that day's dated Mid / End.
- Content is `NotificationScheduler.prayerNotification` — the old `scheduleThisPrayerNotifAt` moved
  verbatim; the owner wants them to look exactly the same.
- Background top-up: `BGAppRefreshTaskRequest` ("com.betternorms.shukr.refresh", earliest +6 h)
  submitted after each run, handled by `.backgroundTask(.appRefresh(…))` in shukrApp;
  Info.plist `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: fetch`. Not testable in the
  simulator (BGTaskScheduler doesn't run there) — untested.
- The bug it fixed: since the day turns at Fajr only the current prayer day was scheduled, so
  "Fajr Time" never went out (sim, 7:27 PM: only tonight's Maghrib / Isha pending).
- DEBUG: `-logPendingNotifs` prints the pending list after each run; `-debugQueueSnooze` queues a
  10-min snooze (relaunch without it → still pending). Sim ✓: 39 pending across Sep 26 – Oct 3,
  tomorrow's FajrStart among them; the snooze survived a relaunch.

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
Since 2026-09-27 the backup also copies the external-storage folder (zikr photos / voice memos,
`.shukr_SUPPORT/_EXTERNAL_DATA` beside the store) as `Library/Backups/shukr_SUPPORT.<label>` —
visible on purpose; to restore, put it back beside the store as `.shukr_SUPPORT`.
`recoverFromUnopenableStore` sets it aside with the store (`shukr.store.unopenable-<stamp>_SUPPORT`).
Salvage skips that folder. **Not done:** salvage doesn't copy photos / memos back from a set-aside
store — its SQLite column holds Core Data's undocumented inline / external-reference markers
(the blobs are in the `_SUPPORT` folder by UUID); recover them by hand if it ever matters.
DEBUG `-demoBackUpStore` makes a `debug-<time>` backup at launch.
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
**Zikr History (2026-09-27, notes #2b):** day headers show that day's time (sum of
`secondsPassed`, like the rows); a tap flips every header to "N counted" (`@AppStorage
zikrHistory.headersShowCount`). Deleting is **only** Edit → select (native List multi-select via
`editMode`) → "Delete N sessions" (bottom capsule) → confirm; then `WidgetCenter` reloads and
totals / task progress recompute from the queries. Row swipes (both ways) and the strip's Delete
are gone, and a tap opens a glass popover (`SessionRow`, like the ☰ menu, arrow edge left to iOS: Open zikr · Feel the pace; picks run 0.45 s after it closes; a tap on the row stops a playing pace; `tappable: false` in Edit mode; one pace at a time via `PaceCoordinator` — a page change, a sheet opening or Edit mode calls `stopAll()`, since the pager keeps History mounted) — History rows no longer register no-page zones, so the
library pages from them too. The Edit button is in `ZikrLibraryView`'s bar on the History tab
(`HistoryPageView(editing:)`); shown on its own, History has its own Edit. Leaving the tab ends editing.
**History & Azkar: a native paging ScrollView since 2026-09-27** (owner: the hand-made pager
lagged — its per-frame `@State dragX` re-rendered both lists). `.scrollTargetBehavior(.paging)` +
`.scrollPosition(id: page)` (the switch follows; a tap scrolls; `.defaultScrollAnchor` starts on
the right page — the first layout ignores the initial position). No swipes on either page: History
and Azkar both delete via Edit → select → Delete (Azkar: native List selection, built-ins
`selectionDisabled` and dimmed; `MantraModel.delete` per zikr). Paging is off while editing or while
the history chart is scrubbed (`LibraryPagerLock`, driven by a `@GestureState` on the chart so a system-cancelled scrub can't leave it locked; also unlocked on disappear; `scrollPosition(id:anchor: .center)` so the switch changes past halfway):
`.scrollDisabled` on the pager with `.scrollDisabled(false)` on each page so the lists still scroll.
(A UIKit `isScrollEnabled` switch didn't stick — SwiftUI resets it.) iOS 26's swipe-back-from-
anywhere still works while editing (a right swipe closes the page). `NoPageZones` is gone. iOS 26: the search field lives in the bottom bar (`DefaultToolbarItem(kind: .search, placement: .bottomBar)` + `.searchable(placement: .toolbar)` — with the automatic placement it could draw a second field; without the explicit item a ＋ in the bottom bar collapsed the search) with Azkar's ＋ beside it, inserted with the page's spring (iOS 18 keeps it top right). Edit mode is the stock iOS pattern (owner, 2026-09-27): selection circles in the system accent (no green), rows with an explicit `listRowBackground` so there's no grey selected fill, and a plain red "Delete (N)" `ToolbarItem(placement: .bottomBar)` from each list (History, Azkar, a zikr's sessions) — the library drops the bottom search item while editing. A pace hold (`PaceHoldGesture`) takes `LibraryPagerLock` while the finger is down. **Paging lag (2026-09-27, owner):** the library's body runs on every page turn (the scroll
position, the switch, the toolbar), and it re-rendered both lists each time — History regrouping every
session — three times per swipe (measured with `_printChanges`). Each page now sits behind
`LibraryPage` (`.equatable()`, compares the search and that page's edit flag — a Binding is never
equal), so a turn redraws only the page landed on, once. One Edit toolbar item (`id: "libraryEdit"`,
acting on the current tab) replaces the two per-tab items that swapped and redrew on every turn. Both lists only honour their selection binding in Edit mode — outside it a long press (Feel the pace) selected the row and left it grey. **Trap:** a `@Query` with `#Predicate { $0.builtInID == nil }` (+ fetchLimit) in this view looped SwiftUI's layout at 100 % CPU and the page never appeared — the view fetches all azkar and checks `isBuiltIn` in memory instead. Several azkar delete via `MantraModel.deleteMany` (one save / reschedule / widget reload).
The old write-up follows. **History & Mantras are one page** (`ZikrLibraryView`, MantrasView.swift): two pages side by side
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
("drag up to open") and an in-circle prompt first and came back to the pill. **It's the only
prompt** (2026-09-27): the in-circle offer (`PostSalahCircleOffer`, `MainCircleView.postSalahFor`),
the top pill (`FloatingChainZikrButton`, `-demoChainButton`), the dev picker
(`PostSalahPromptStyle`) and the `showChainZikrButton` / `dismissChainZikrItem` bindings threaded
through the Salah page were deleted; the old `postSalahPromptStyle` key is cleared at launch.
DEBUG `-demoPostSalahOffer` shows the pill.

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
