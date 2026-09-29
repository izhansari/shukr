# What's new v1–v3: the old rules and history

Moved out of CLAUDE.md on 2026-09-29 when What's new v4 replaced them (see CLAUDE.md "What's new").
Kept for the record only; nothing here is current.

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
- **Hard rule — chat requests too (2026-09-28):** when Bradley relays the owner's request from chat (his exact words
  are in the brief), the entry gets `--asked "<his words>"`: the app shows "You asked in chat: '…'" and puts the change
  under **To check** (Looks good / Still off) exactly like addressed feedback. Backfill: `whatsnew.py asked --entry <id>
  --text "…"`. Don't add `--asked` to an entry that already `--addresses` the same request (two check cards).
  **His feedback answers it (owner, 14CEC68B):** a note on that topic written on a build that has the change
  (`WhatsNew.answer(to:)` / `saw`: the note's build time ≥ the change's commit, or `followUpOfEntry` = its id) takes the
  check off To check — 👍 Works = looks good (the topic acknowledged through it), Issue / Note = still off (saving one
  also links `followUpOfEntry` and reopens). feedback.md's "Asked in chat" says which. **Trap:** anything that reads
  `FeedbackStore.shared` must not run inside `FeedbackStore.init` — its feedback.md write is deferred a turn for that
  (writing asks `askedState` → `answer` → `.shared`: a recursive dispatch_once crashed opening What's new; never shipped).
- **Hard rule — steps per change:** every entry has its own `--try` steps for THAT change (the app's "Try it" lists
  every untested change with its own steps, then the feature's general steps folded). `whatsnew.py add` refuses an
  entry without `--try`; `--no-try` only for invisible changes.
- **Hard rule — a headline per change (2026-09-28, owner: "a small title … what it is that got changed or what it is to
  look for"):** every entry has `--headline "…"` — what changed in a few words, ≤ 40 chars ("Only the newest change
  shown"); `whatsnew.py add` refuses an entry without one, and `whatsnew.py headline --entry <id> --text "…"` backfills.
  It's the bold line of a To check card (`ScannableCheck`: the card's name + where it came from in one quiet line, ✓ the
  headline, "Look for: <its first try step>", then Looks good / Still off; his words and the full "Done in / Addressed
  in <build>: <title>" fold behind "your words ›") and a To test card's subtitle (newest untested change's headline,
  "· +N more"). `WhatsNewEntry.short` = headline, else the title (older entries). The whats-new topic's area is "Beta".
- **Short topic titles:** `--topic-title` ≤ 60 chars (a name: "Prayers widget", "Insights"); the feature as it is now,
  in full, goes in `--topic-summary` (the detail shows it under the title). The script refuses longer titles.
- **How the page reads (2026-09-28, owner: "so everyone is on the same page"):** each card has one state. To check
  (your note addressed, or something you asked in chat done) → To test (changes nobody has tested or given feedback
  on, newest untested first, a green dot when the newest is unseen) → With the team (you left a 👎 / note: "You said
  '…' · saved · Claude will pick it up / sent / received") → Archive (tested, 👍, looked good). Any feedback, or the
  tick, acknowledges the card up to its latest change (`WhatsNew.acknowledge`, `whatsNew.acked`: topic → entry id); a
  newer change always reopens it (`WhatsNew.untested`). Older ticks / notes still count (tested keys per entry; a
  note's `commits` snapshot). Chat-request checks live in `whatsNew.asked.closed / .reopened`; Still off opens a note
  with `followUpOfEntry`; feedback.md lists them under "Asked in chat". Those defaults-only states also go to
  `Library/Feedback/state.json` (`acked`, `askedClosed`, `askedReopened`, `tested`, `updated`; written at launch and on
  change, only when changed) — `pull-feedback.sh` copies it next to feedback.json for the plan board. "unsent" is gone from the UI ("saved · Claude
  will pick it up"). Review fix-ups: Looks good acknowledges the topic through the fixing change (`FeedbackStore.close` →
  `WhatsNew.acknowledge(topic:through:)`; `closeAsked` too); older closed notes / asked closes count the same in
  `ackedIndex`; a note whose commits snapshot ends in "next" covers every entry committed before its build (the build
  time in its build line, else `created`); asked "Still off" drafts are their own (`draft(for:followUpOf:followUpOfEntry:)`);
  an entry with both `asked` and `addresses` is checked once (through the note); `writeState` only where What's new is
  available (TestFlight writes once `AppTransaction` confirms); the testflight notes use each topic's `summary`.
  Checked on the owner's pulled feedback.json (`-whatsNewDump` logs each card's section): qibla-haptic → Archive,
  zikr-history down to its one real new change, a Looks good tap → Archive after relaunch.
- **Never hand-edit the entries** — use `scripts/whatsnew.py` (it keeps `shukr/WhatsNew.json`'s layout):
  1. `scripts/whatsnew.py resolve` (fills in earlier "next" hashes and every commit's time).
  2. Screenshot in the sim, then `scripts/whatsnew.py shot <png> <name>` → `shukr/WhatsNewShots/wn-<name>.jpg`
     (≤ 600 px, ~20–40 KB; keep the folder modest — it ships in TestFlight builds). The folder is a
     synchronized group in the app target, so nothing else to add.
  3. `scripts/whatsnew.py add --topic <id> --notes "#17" --title "<this change, one line>" --headline "<≤ 40 chars>"
     --try "…" --try "…" --shot wn-<name>.jpg`. A new feature: also `--area Zikr --topic-title "…"`.
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
- **Your feedback / All changes (2026-09-28, owner: "where do i go … to see my feedback?"):** two quiet sage links under
  Send feedback (`headerLink`) push `YourFeedbackView` (every note, newest by `updated`, kind icon · card · 2 lines ·
  when · `FeedbackStore.stateLine` — the one wording the card's Feedback section uses too; closed / still-off greyed,
  addressed in green) and `AllChangesView` (every `live` entry by day, time · card · title, a green dot when untested, a
  44 pt thumbnail decoded off the main thread in `ShotThumb`), both in CursorSwift/WhatsNewLists.swift, both searchable
  (pull down). A row pushes `WhatsNewRoute.cardAt(topic, focus:)`: the detail scrolls (ScrollViewReader, 0.35 s after the
  push) to `.id("feedback")` or the change's `.id(entry.id)`, which lights sage for 2 s. DEBUG `-demoWhatsNewPage
  feedback|changes`, `-demoWhatsNewFocus feedback|<entry id>` (with `-demoWhatsNewTopic`).
  **Changes fold (owner, 4E1AD6F2):** a card's Changes shows the newest change, every untested one and a focused one;
  the older tested ones sit behind "Show N earlier changes" (`showAllChanges`, expands in place; "Show fewer").
- The page: `CursorSwift/WhatsNew.swift` (cards, detail, timeline — each change's shots stacked, fitted to the column
  (≤ 300 pt the newest, 170 the rest); never a horizontal ScrollView there: with `scrollClipDisabled` it let the page
  move sideways (owner, BA0ECB7A); tested per topic — a new change
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

