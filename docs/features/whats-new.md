# What's new — the page and whatsnew.py in full

The rule (one entry per item) is in CLAUDE.md.

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

**Ideas (ask wn-ideas):** `FeedbackItem.Kind.idea` (💡, "Idea") with an optional
`area`: on a change, "Comment or idea" → the composer's "About this change | New idea" (keeps `onEntry` = the card), or the
header's "New idea" (no card, an area picker). `Kind.isVerdict` (works / issue) is what counts as an answer — never an idea
or a comment. feedback.md: "## 💡 Idea — <area>" + "- From: `<change>` (<headline>)".

**Next build (ask wn-next-build):** `build` records in the change log (`whatsnew.py build --number N [--commit] [--time]`;
testflight.sh writes one after a confirmed upload; build 12 backfilled at 994ee5a). `WhatsNew.lastBuild` / `sinceLastBuild`
(live changes after its time — the same set as `whatsnew.py testflight --since last`). A "Next build · N changes" row
under Your answers → the asks still waiting, by name (tap → onto that card, outlined; Your asks is one flat row list so
`scrollTo(id:)` finds it; never animated — fails on unbuilt lazy rows), the list by area, and
"I'm happy with this — ready for TestFlight" = a `.ship` note (commits = the change ids; "## 🚀 Ready for TestFlight" at
the top of feedback.md until picked up). Not a gate, nothing uploads: Frank still confirms with him before testflight.sh
(as a decide.sh ask, or his Ready note on the page).

**Speed + Later (ask wn-speed):** no file write on the open path — feedback.md / state.json are debounced, written on
`FeedbackStore.writer`, flushed on going to the background; `status(of:)` / `openAsks()` are cached per
`FeedbackStore.revision`; debounced search; lazy stacks; pictures decode
in `.task`. **Later:** a card's fold sets it aside
(`whatsNew.later`: ask → change; a newer change brings it back) to one line under "Set aside · N". **Size rule:** an ask
card ≤ ~40 % of the screen (picture 110 pt, headline / "Look for" 2 lines, words folded, buttons 40 pt); a change row
1–2 lines; Next build one line.

**Decisions (ask wn-decisions):** a checklist badge top right (beside Done, always there — the count only when any; the page says "No decisions needed") = `WhatsNew.openDecisions()`
(cached per revision) → `DecisionsView` (WhatsNewDecisions.swift): waiting first, then Decided as one folded row, closed on every open; options side
by side (pictures, "Bradley's pick"); a tap chooses at once, Edit re-picks / adds a note, and tapping the pick again un-picks it ("Clear answer" → back to Waiting; an answer with `option: null`). The asker can `whatsnew.py decision-withdraw ID [--why]` (kept in Decided, greyed, "withdrawn") or `decision-revise ID [--question] [--option …] [--recommend]` (reopens it; earlier answers stop counting); board/decide.sh mirrors them. His pick =
`FeedbackItem.Kind.decision` (`decision`, `option`, note in `text`) → feedback.md "🗳 Decision",
state.json `decisions`; `import-verdicts` / `add` turn pulled ones into `decision-answer` lines (source phone).

**The data:** `shukr/WhatsNew.jsonl`, JSON Lines, written only by `scripts/whatsnew.py` (never by hand):
topics (features), **asks** (his requests, verbatim), changes, chat verdicts. `.gitattributes` merges it with
`merge=union`, so branches appending lines don't conflict; `whatsnew.py check` flags a line a merge kept twice.
Screenshots: `shukr/WhatsNewShots/wn-*.jpg` (a synchronized group: in the repo and dev builds, the team's picture
record; `testflight.sh` leaves them and the log out of every upload, TestFlight and App Store — owner 2026-10-15).

**One entry per item, not per commit** (owner 2026-10-15, agreed by Frank, Sami, Bradley). He doesn't use the page;
it's the team's record, with pictures, of what changed and why, so anyone can look up another's change without the sim.
- One entry per thing he'd recognise: a feature sprint or a one-off fix. Never for a state he threw away; none for
  invisible changes.
- During a sprint: small commits + pushes, no entries. Each commit message = what changed + his words for that step,
  and "tried X, dropped because Y" when something goes.
- Written when the first build of it goes to his phone (or at the sprint's end if none did). Each later install round
  replaces it: `add` a fresh one with the same `--ask`, then `status --entry <old> --set replaced` (committed entries
  can't be edited). The new one carries the old one's "Tried and dropped:" line and any words he added since.
- It holds: a fresh shot of the latest state; how it works in 2–3 lines (`--title`); a `--try`; the ask slug + the words
  that started it; one "Tried and dropped:" line and what was / wasn't checked (`--notes`).
- Wrapping up an item = the entry matches what's on his phone → commit → push → `queue.sh done`.
How:
1. A screenshot only if one was taken while testing (lean — owner 2026-10-17; never a sim run just for it) →
   `scripts/whatsnew.py shot <png> <name>` (≤ 600 px, 20–40 KB). First check WhatsNew.jsonl: skip an item another entry covers.
2. `scripts/whatsnew.py add --topic <id> --headline "<≤ 40 chars>" --title "<one line>" --try "…" [--try "…"]
   --shot wn-<name>.jpg [--ask <slug> [--ask-words "<his words>"] | --ask-note <feedback id>] [--notes "#17"]`
   - **--ask**: the ask this answers. Bradley's brief gives the slug and, for a new chat ask, his exact words
     (`--ask-words`, verbatim, typos kept). A fix for a note on the phone: `--ask-note <id>`. Several attempts at one
     ask use the same slug; only the newest waits for his answer (a new attempt reopens it).
   - A new feature: add `--area Zikr --topic-title "<≤ 60 chars>" [--topic-summary "…"] [--topic-link salah|zikr|…]`.
     Change a feature's title / summary / steps / link: `whatsnew.py topic --id …`.
3. Commit. **No resolve step**: `add` stamps the time; ids get a random suffix, so branches can't clash.
- Not committed yet and wrong: `whatsnew.py edit --entry <id> …` / `drop --entry <id>`. Committed and undone later:
  `whatsnew.py status --entry <id> --set replaced|dropped` (greyed in history).
- He answers in chat instead of on the phone: Bradley queues it in `shukrGit/board/verdicts.jsonl`
  (`board/verdict.sh <slug> works|notyet "<words>"`); the next `add`
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
Decode screenshots / thumbnails off the main thread. DEBUG args (`-demoWhatsNew…`, `-whatsNewDump`, …) are listed in
WhatsNewPage.swift.

**Other beta extras** (Your reminders' link, its Details and card previews) follow `WhatsNewAccess.beta`: DEBUG or any
TestFlight install. "Run setup from the start" and What's new follow `.available` (the owner only).
