# shukr 2.0 (12) — What to Test

Built from 994ee5a + the build bump. Released with `scripts/asc.py release 12`.

---

## What to Test (paste this)

Apple Watch, a new setup, and smoother prayer marking. Thank you for testing!

APPLE WATCH
• Zikr on your wrist: the phone's counter (beads, the ring, a dot every hundred); count with a tap, Double Tap or the Digital Crown. Your daily tasks come across, and sessions come back.
• Mark prayers from the watch: tap to mark, or hold the prayer ring. It plays the same completion moment as the phone. Tap a marked prayer to unmark it ("Unmark Asr?").
• Tasbih Fatimah after salah: 33 · 33 · 34, the phrase above the count.
• The qibla on the watch, and complications for your watch face.
• No watch app? iPhone Watch app, Available Apps, shukr, Install. Open shukr on the iPhone once so the watch gets your location.

NEW: FIRST-RUN SETUP
• Opens once after this update, filled in with your current settings. Walk through it or tap Skip.
• Where you pray: location (choose "Always" so times follow you when you travel), the method ("Automatic" picks your country's), then the madhab: only Asr changes, and you see both Asr times.
• Light, dark or auto (follows the sun); reminders per prayer, the same bell as in Settings: off, at the start, or with nudges (halfway and with 30 min left, if not marked yet); the Fajr alarm; your masjid and its arrival and leaving duas.
• A review screen shows what's missing (Always location, notifications), then "bismillah" takes you into the app.
• Your reminders stay as they were. New installs start with Fajr off (the Fajr alarm covers it), Dhuhr, Asr and Maghrib with nudges, and Isha at the start.
• If you turn location off later, shukr says so (the opening lands on its circle) and offers to turn it back on or use a city.
• Beta only: Settings → Run setup again.

FAJR ALARM
• It now says "Start" and "End" of Fajr instead of "Fajr" and "Sunrise".
• Fixed: an alarm left on its default rule now rings before the start of Fajr, as Settings always showed. Before, it could ring at sunrise without saying so.

MARKING A PRAYER
• Smooth again: the ring sweeps closed from where it was and says "Asr · On time · 88". The circle and the list stay still until it's done, then the next prayer (or today's score) fades in.

REMINDERS THAT REACH YOU
• If notifications are off, or iOS holds them for the Scheduled Summary, a calm card says so and shows the fix (at most every few days).
• Beta only: Settings, Notifications, tap the status row: Your reminders shows the 64 slots iOS allows, this week day by day, and how they reach you (your own settings first).
• If shukr isn't opened before its reminders run out, a last one asks you to open it.

ALSO NEW
• Insights: scoring comes first. Each prayer's ring (its symbol inside) shows where the Salah ring usually is when you mark it; tap one for details. The grid has dates and a show-scores switch.
• Daily Ayah, light mode: a clearer green light behind the verse.
• Streaks count every completed day, even when its last prayer is marked late.
• Zikr: after finishing a task, the page lands on the next task to do.
• Pause and results: the rate compares this session with your usual pace ("1.1s faster").
• Azkar: the sort button is top right, green while a sort is on. Delete a zikr from its own page.
• Mosques: the list and each mosque's page share one sheet; swipe it down to a bar.
• Fixed: masjid duas could appear when you weren't at the masjid.
• Prayers widget: the ring fills live in the app's colours (green, then yellow, then red); the check is top left; the chevron opens today's times, where a tap marks a prayer. Mid-morning it shows Dhuhr as next. Edit Widget has a Style: System, Light, Dark or Follows the sun.
• Lock Screen Prayers widget: a smaller icon so the name and time fit.
• A prayer that hasn't started has a dashed ring that fills in when it begins.

Beta only: the build line at the bottom of Settings opens What's new; Your feedback lists every note you've left, All changes every change by day.

Found something off? Send feedback with a screenshot from TestFlight.

---

## By build (for our records)

- **2.0 (12)**: Apple Watch zikr counter, marking and Tasbih Fatimah (Sami); first-run setup + Automatic method + notification defaults; lost / found location ring-to-ring; Fajr alarm Start / End wording + default-rule fix; completion moment smooth again; notification health card + Your reminders (64-bead ring, polish 49171DB2); keep-alive reminder; Insights rework (usual-moment rings, plain picked dates); streaks recount from history; masjid duas only on real crossings; picking pin = Apple mappin (D5818BB9); Prayers widget live ring in the app colours + steady on tap (Sami); What's new: headlines, Your feedback / All changes, changes fold, answer rule.
- Earlier builds: see TestFlightNotes-2.0.11.md.
