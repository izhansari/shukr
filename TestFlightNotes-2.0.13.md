# shukr 2.0 (13) — What to Test

Built from 155615f + the build bump. Released with `scripts/asc.py release 13`.

---

## What to Test (paste this)

A smoother opening, easier prayer marking, zikr reminders in one place, and a better Apple Watch. Thank you for testing!

SALAH
• Marking from the list: tap round a prayer's circle (a bigger tap area). Tapping the name or time still flips the time.
• After you mark a prayer, the "Post-salah tasbih?" pill goes by itself after 15 seconds. A ring round its beads counts down. It waits while you're away from the page.

ZIKR
• Reminders in one place: the bell at the top right of the Zikr page lists every task reminder with its next time. Tap one to edit it, swipe to remove it, or add one.
• Arrange your tasks on the wheel: long-press a task and the circles jiggle. Drag one along the arc, or tap Reorder for a list. Done saves.
• After you finish a task, the wheel moves on to the next one still to do.
• Pause screen: the phone chip sets the counter's haptics: light, medium, strong or silent. Silent turns off every counting buzz; buttons keep theirs.

APPLE WATCH
• Tap the prayer ring to flip its time ("at 5:35 AM" or "in 1h 50m"; "ends 6:46 AM" or "3h left").
• Counting with the Digital Crown: one count per nudge, however far you turn it.
• A new pause screen: your count, time and pace, and the haptics setting (including silent).
• The post-salah prompt goes by itself after 15 seconds, like on the phone.
• A task you finish keeps its place, and the next one comes to the middle.

WIDGETS
• Prayers widget: the ring's empty part is plain grey again, with only the arc in colour.
• Tapping a marked prayer in the widget's times list asks "Unmark?" wherever you are in the app.

FIRST OPEN AND SETUP
• New installs and Run setup again open on a new first page: a moving green gradient and "welcome to shukr". Tap to go on.
• On the setup's review, tapping a row opens just that step. Done takes you straight back to the review.
• At the end, the ring now grows all the way out to the prayer circle before it appears.

Found something off? Send feedback with a screenshot from TestFlight.

---

## By build (for our records)

2.0 (13), from 155615f (bump + build record committed after the upload). Since build 12 (994ee5a):
- Salah: dot tap circle (completion-moment-3), post-salah 15 s ring (post-salah-2) and the ☰ menu (post-salah-3).
- Zikr: haptics silent / chip steps (tasbeeh-haptics-1…3, -ed15), wheel arranging and done order (zikr-wheel-1, -c16d), zikr reminders page (Sami, e1d6311).
- Watch: ring tap (apple-watch-3), Crown nudge (-4), pause screen (-5), post-salah ring (-6), done order (-7810).
- Widgets: plain ring track (widget-next-13), unmark prompt anywhere (widget-next-6608).
- Setup: edit returns to review (first-run-setup-15), opening page (-16), dashed landing (-17).
- What's new (team only, hidden from testers): v4 page, areas, ideas, Next build + Ready for TestFlight.
