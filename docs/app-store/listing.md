# App Store listing — draft (Ben, 2026-10-04; source: docs/app-store-features.md)

Limits (App Store Connect): name ≤ 30 · subtitle ≤ 30 · promotional text ≤ 170 · description ≤ 4000 · keywords ≤ 100
(comma-separated, no spaces after commas, don't repeat the name or the category) · What's New ≤ 4000.

## Name (≤ 30)
shukr — Prayer Times & Zikr

## Subtitle (≤ 30)
Prayer tracker, qibla, tasbeeh

## Promotional text (≤ 170, editable without a new build)
Prayer times that follow you, a tracker that scores each prayer by when you prayed, a tap-anywhere tasbeeh, and the qibla
on a map. Nothing leaves your phone.

## Description (≤ 4000)
shukr is a calm, circle-based companion for your prayers and your zikr.

PRAYER TIMES THAT FOLLOW YOU
Accurate times for where you are, from GPS or a city you pick, with the calculation method and madhab of your choice.
Give shukr Always location and your times, reminders, widgets and Fajr alarm travel with you, even when the app is
closed.

ONE CIRCLE FOR THE DAY
The current prayer and a live ring of how much of its window is left, coloured by the score you'd get right now. Tap to
flip between "ends at" and time left.

A TRACKER THAT SCORES WHEN YOU PRAYED
Mark each prayer with a tap. It's scored by when: Perfect in the first 30 minutes, then On time, Late, Qaza or Missed,
and each day gets a score. Done prayers fold away; all five bring a perfect-day moment. Prayed earlier? Edit the time
with a wheel that won't let you pick an impossible one. The day runs Fajr to Fajr, so a late Isha after midnight still
counts for its day.

STREAKS AND INSIGHTS
Your day streak, your in-time days, your best. Three insight pages: how you're scoring, how consistent you are, and
whether you're getting better, prayer by prayer, over eight weeks.

REMINDERS THAT KNOW YOU
A notification at each prayer, with "I already prayed" and "nudge me in 5 or 10 minutes" right on it. Tune each prayer
separately. An optional daily Fajr alarm.

WIDGETS
The current prayer's ring on your home screen, and you can mark it prayed from there. Today's zikr tasks with their
progress. A Name of the Day. Today's verse, once you've revealed it. Lock Screen widgets with the time left.

QIBLA AND MOSQUES
The qibla on the main circle and on a map: the line to the Kaaba from where you stand, a compass ring that tells you
which way to turn, and a glow when you're facing Makkah. A qibla-up map that turns so the line points straight up your
screen. One tap finds the mosques around you: distance, drive and walk times, Look Around, directions, a call.

YOUR PRAYERS ON THE MAP
Every prayer you've marked, pinned where you prayed it and coloured by score. Filter by prayer and date.

TASBEEH AND ZIKR
A tap-anywhere counter with haptics and beads. Freestyle, a count goal or a time goal, with a live finish estimate.
Daily zikr tasks as a wheel of circles, each ringed with today's progress, with streaks for every task. Count in sets
when you recite on your fingers. Post-salah tasbih (33 · 33 · 34) in one flowing session. Sleep mode for zikr in bed.

YOUR OWN AZKAR
Keep every zikr with its Arabic, transliteration and your notes. Add a voice memo of how it's said and a photo of the
written dua, both a tap away while you count. Lifetime count, time and pace for each.

QURAN AND THE 99 NAMES
A verse a day in the Uthmani script with translation, and a share card for Stories. The 99 Names with meanings and
flashcards to learn them.

APPLE WATCH
Prayer times, marking with undo, the qibla, and the tasbeeh with the Digital Crown.

PRIVATE BY DESIGN
No accounts. No tracking. No ads. Your location is used on your phone and never leaves it. Your prayers, your zikr and
your notes stay on your device.

## Keywords (≤ 100 characters)
prayer,salah,namaz,athan,adhan,qibla,tasbeeh,tasbih,dhikr,zikr,muslim,islam,quran,ramadan,mosque,masjid

(96 characters. "prayer times" is covered by prayer; the name isn't repeated. TODO: swap in "azan"/"iqamah" if ASC's
search data favours them.)

## Category
Primary: Lifestyle. Secondary: Reference. (TODO: confirm; Utilities is the other common choice for prayer apps.)

## Age rating
4+. The questionnaire's triggers (violence, mature themes, gambling, unrestricted web access, contests) are all "None".
Religious content is not a rating trigger.

## What's New (first App Store release)
Welcome to shukr: prayer times that follow you, a tracker that scores each prayer by when you prayed, streaks and
insights, reminders you can answer from the banner, a tap-anywhere tasbeeh with daily zikr tasks, your own azkar with
voice memos and photos, the qibla and mosques on a map, a verse a day and the 99 Names, widgets, and an Apple Watch app.
Nothing leaves your phone.

## Screenshot captions (6.9" and 6.5"; one line each, ≤ ~40 characters reads best)
1. Salah circle — "Your prayer, live"
2. Tracker list, three marked — "Scored by when you prayed"
3. Streaks / Insights — "See yourself getting better"
4. Tasbeeh counter — "Tap anywhere. Count."
5. Zikr wheel — "Daily zikr, with streaks"
6. Qibla map — "The qibla, right where you stand"
7. Mosque finder — "Mosques around you"
8. Widgets on a home screen — "Mark it prayed from your home screen"
9. Daily Ayah share card — "A verse a day"
10. Apple Watch — "On your wrist"

## App Review notes (the "Notes" field)
No account is needed. Location is optional: without it, pick a city in setup. The Fajr alarm uses AlarmKit on iOS 26.1+
and a Shortcut on earlier versions. The Apple Watch app needs the phone app installed once. No server, no login,
no in-app purchases.
