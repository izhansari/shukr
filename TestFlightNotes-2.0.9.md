# shukr 2.0 (9) — What to Test

Everything since 2.0 (8) (built from bfab208), from WhatsNew.json. Paste the "What to Test" block
into App Store Connect → TestFlight → build 9 (`scripts/asc.py release 9 <notes.txt>`).

---

## What to Test (paste this)

A big update, and the first build with the Apple Watch app. Thank you for testing!

NEW: APPLE WATCH
• shukr is now on Apple Watch: today's five prayer times, a ring for the current prayer, and complications for your watch face (the prayer ring, time left, next prayer).
• Install it from the Watch app on your iPhone (look for shukr under available apps). Open shukr on the iPhone once first so the watch gets your location and prayer settings.
• For now the watch shows your prayers; marking them and tasbeeh on the wrist come later.

PRAYER
• Jumu'ah prayed at a masjid counts in full and shows as "Jumu'ah". The best grade is now called "Perfect".
• Change where you prayed: drag the map under the pin or type an address. Edits keep what the app recorded, so you can put it back.
• A prayer that hasn't started has a dashed ring that fills in when it begins.
• Prayer notifications are planned a week ahead, so Fajr always arrives.
• After marking a prayer, one "Post-salah tasbih?" pill at the bottom.
• The qibla buzz only happens when the prayer circle is on screen.

MAP & MOSQUES
• The globe button switches the map between Standard and Satellite, and the map follows light and dark mode.
• Tap a prayer pin for its own page: when you prayed, the window, where, and Edit right there.
• The explore button opens in place: Qibla, Prayers, Mosques. Filter your prayer pins to "Only at a masjid".
• My masajid: star the mosques you pray at. Mosques live in one sheet that shrinks to a bar.
• The qibla-up button also brings you back to your location.
• Opt-in: a dua when you arrive at or leave one of your masajid. A welcome in Makkah and Madinah.

ZIKR
• "Mantra" is now "zikr", and your library is "Azkar".
• A zikr can keep a voice memo (how it's said, with slow 0.75x and loop) and a photo, both on the pause screen.
• Eight built-in azkar with their Arabic and meaning, kept apart from your own.
• Give a task its own name ("After Fajr") and a reminder, at a time or around a prayer.
• New task: the number pad is ready, pick or make a zikr, or start from a zikr's page.
• History: day headers show the time (tap for counts). Tap a session for "Open zikr" or "Feel the pace". Edit to select and delete.
• History and Azkar page smoothly; Azkar has Edit to delete your own.

WIDGETS & MORE
• The Lock Screen prayer ring and bar fill as the prayer's time passes, with a dashed ring before it starts.
• The medium Zikr widget fits more tasks.
• 99 Names: filter by All, Learning or Known.
• The welcome animation only plays when the app starts fresh.
• Tap the build line at the bottom of the menu to see what changed in each build.

PLEASE TRY
• The Apple Watch app and a complication on your watch face.
• Record a voice memo for a zikr and play it on the pause screen.
• Paging between History and Azkar: does it feel smooth?

Found something off? Send feedback with a screenshot from TestFlight.

---

## By build (for our records)

- **2.0 (9)**: Apple Watch app + complications (first build with it); zikr rename + voice memo / photo + built-in azkar; new task flow; zikr reminders and task names; Zikr History (day time headers, Edit → Delete, session popover, native History ⇄ Azkar paging); map globe (Standard / Satellite) + dark map; prayer pages on the map with edit / move; recorded vs edited; My masajid, Jumu'ah scoring, masjid duas; notifications a week ahead; dashed next ring; Lock Screen rings fill; What's new v2 (cards, feedback). Schema 2.6.0.
- Earlier builds: see TestFlightNotes-2.0.8.md.
