# shukr 2.0 (10) — What to Test

Built from c830b80 (the iOS 26 Settings fix) + the build bump. Released with `scripts/asc.py release 10`.

---

## What to Test (paste this)

A fix for Settings, plus smaller changes. Thank you for testing!

FIXED
- Settings rows respond again. On some phones the Calculation Method and School pickers, Refresh Location, Choose City and the Sneak Peek rows did nothing when tapped in build 9.
  Try: Settings > Calculation Method > tap Method or School: the menu opens.

ZIKR
- Azkar: your own azkar are at the top, built-ins below. A filter button next to the search field hides the built-ins so only yours show; tap it again to bring them back.
- History and Azkar page more smoothly, and the Edit button no longer redraws when you page.
- Editing a zikr: adding or removing a photo or voice memo lights up Save, and Cancel asks before throwing it away.
- A zikr's sessions: in Edit, a tap selects the session, with one Delete at the bottom.

WIDGET
- Prayers widget: the circle sits centred above the five prayer dots. New "Score colours" switch in Edit Widget (off = prayed prayers in plain grey). A clearer dashed ring before a prayer starts, and the times list fits all six times.

MAP
- The qibla map keeps buzzing the whole time you're lined up with the qibla, and stops when you turn away.

WHAT'S NEW (tap the build line at the bottom of the menu or Settings)
- It now shows only what needs you: notes a change has addressed ("Looks good" / "Still off"), changes to test, and unsent notes. The rest is in a searchable Archive.

Found something off? Send feedback with a screenshot from TestFlight.

---

## By build (for our records)

- **2.0 (10)**: Settings rows dead on iOS 26 in build 9 (pager DragGesture minimumDistance 0 → 5; verified dead / fixed on a 15 Pro, iOS 26.6, with Release builds of 3fe870a / c830b80); Azkar yours-first + built-ins filter; History ⇄ Azkar paging lag; zikr editor media drafts; Prayers widget score colours / centring / dashed ring / times list; qibla map buzz while aligned; What's new v3.
- Earlier builds: see TestFlightNotes-2.0.9.md.
