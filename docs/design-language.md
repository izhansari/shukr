# shukr's design language (Sami with Izhan, 2026-10-14)

The pictures: `shukrGit/board/mocks/design-library/01-…24-*.jpg` (same numbers as below); everything on one page: `shukrGit/board/mocks/design-library/design-language.html`.
Izhan is still picking the model pages; until he does, all 24 are the reference.

## What the strong pages share

1. **The ring holds the state.** The circle is shukr's signature: the most important thing on a screen lives in a ring — the prayer (01, 02), the day's score (03), the zikr (04), the goal (15), a setup step's symbol (17–20), a check (21), a slashed bell (23), even "location is off" (24).
2. **One thing in the middle.** Every strong screen has a single centred focal object; everything else is quieter and gives it room.
3. **Soft, not flat — for the big things.** Surfaces are raised from or pressed into the page; depth from light and shade, not borders or dividers. Cards rise; rings sit in a groove. **Raised = heroes and block cards; lists stay flat** (Izhan, Zikr round 7: a shadow on every row or every day "gets overdone"; Your azkar's raised blocks work "because it's all one kind of big block"). Long lists of sessions are plain rows on the soft page with faint lines.
4. **Light type, grey hierarchy.** Big but light titles (thin / light, often rounded) over one grey line; importance from size and grey, almost never bold or colour.
5. **Sage means tap.** One accent, on what you can act on (outlined or tinted buttons, links, the dashed add row). Green / yellow / red are for prayer grades only. **Except Journey** (and the Salah page): no sage anywhere — taps there are ink or grey (owner, 2026-10-17: "I'd rather not use, Sage. Anywhere on this page.").
6. **One pill, one quiet line.** A screen ends with one soft sage pill and a plain grey line under it ("Not now", "I changed my mind"). Never a row of buttons, never two of equal weight.
7. **Frost, don't scold.** Something off = the real thing frosted over, a slashed symbol, one gentle sentence (17–20, 23). No error pages, no red.
8. **Show the real thing.** Demos are the actual product (banner, Live Activity card, alarm, widgets), each in a soft sage panel (08, 12, 13, 18).
9. **The glass sheet template.** Symbol in a ring → light title → one grey line → a short icon list → the pill and its quiet line (21, 23).
10. **Calm words, honest air.** One short human sentence per idea; space around things, no empty dead zones; nothing shouts.
11. **Motion that means something.** Rings draw in, the hadith is written in, the list fades as it rises.
12. **Where flat lists fall short.** Settings-style grouped lists (Which zikr?, Your tasks, the Zikr mockups) get 4 and 5 but miss 1–3: no ring, no single focus, no depth — the "not shukr" feeling.

## The gap: data-heavy pages (Izhan, 2026-10-14)

Almost every page above says one or two things. The Zikr work is the opposite: a lot of data on screen at once, and
paging between related pages (azkar → a zikr → its goals → its history). shukr has no strong example of that yet, which
is why this is hard. The points above still hold, but they have to be stretched, not copied:

- **The closest we have:** Memories (10) — lots of data (a calendar of photo stacks, three levels) with the controls in one glass bar at the bottom; Your Notifications (in the "Your …" pages) — status first, then the evidence, then the detail by day; the day's page (03) — five prayers' worth of data folded into one ring.
- **A summary hero, then quiet density.** One ring or number at the top says the state of the whole page; the rows under it stay quiet (grey lines, no extra colour), so the eye has somewhere to start.
- **Rings as data glyphs.** Small rings inside rows (a goal's progress, a day's fifths) carry the state at a glance instead of more text.
- **Paging in glass.** Moving between levels or filters lives in a bottom glass bar (as Memories), not in more headers and chips.
- **Pages that feel related.** Going deeper should feel like zooming into the same object (the ring or card you tapped), not opening a new form.

## How we mock up (owner, 2026-10-18)

- **Swift lab** — to settle type, spacing, colour and feel on the real screen: a copy of only the views being redesigned, in
  its own DEBUG file under `shukr/CursorSwift/DevLabs/`, opened from My Dev Stuff (a new, blue row). The real page is never
  touched. Real data (plus a switch for the states that need one); the shapes the design doesn't touch are the real views.
  The first commit is the copy as it is; later commits are the design, so the file's diff from that commit is the spec for
  the real build. Knobs (a tuner) live in the lab only; once he picks, the values go into the copy as plain numbers. No
  circle-check or pixel checks. Delete the lab once the real build lands. Example: `SalahTypeLab.swift`.
- **Artifact / canvas** — for storyboards and motion sequences (Journey v6) and several options side by side.

## Vocabulary

| Term | Meaning |
|---|---|
| Soft look | The raised / pressed surfaces of the Salah page and its rings |
| The ring | A circle that holds a state: a prayer, a score, a symbol, a check |
| Hero | The one focal object on a screen |
| Raised card / pressed ring | Up from the page vs. sunk into it |
| Block card | A big raised card that is one thing (a hero, a goal block); lists inside a page stay flat |
| Sage panel | The soft green area a demo sits in |
| Frost / frosted state | The real thing blurred over, a slashed symbol and one line: it's off |
| Glass sheet | A partial sheet in Liquid Glass over the page (21, 23) |
| Soft pill | The sage-tinted, rounded main button |
| Quiet line | The grey text button under the pill |
| Outlined button | Sage text + sage border, no fill (setup) |
| Grey line | The one secondary sentence under a title |
| Dashed add row | The sage dashed "+ A new …" row |
| Drawn in / written in | Motion that builds a thing instead of fading it in |
| Calm | No bounce, no glow, nothing loud — the opposite of "tacky" |
| Streak | Always "streak", never "run": "best streak 10 days", "4-day streak · keep it today" (Izhan, Zikr round) |
| Week grid | A long stretch in small: a week a row in rounded bars (like a GitHub heat map), today's week at the bottom, scrolling up to the first day under a fade from anywhere on it (a hold on a tile picks instead, and moving picks across rows); the month names are a rail too — hold them, and where the finger is along the column is the month (a pill, a tick each, a slim scroll bar at rest); each kind its own color — in time green, all five with a Qaza grey-green, incomplete grey, none the faintest — shaded by the day's score on the user's own scale (their lowest of a kind faintest, their best full, never fading into the kind below); grey month names beside it open the month (Journey on one screen, owner 2026-10-16: "squares is more familiar (like github heatmap)"; colors tuned by him 2026-10-17, board/mocks/journey-v6/tile-colors-handoff.md; picture 25) |
| Hold to choose | A number that could be measured more than one way: one default, and a touch-and-hold menu with every way, each with its value and what it counts; the choice sticks (Journey's This month row, owner 2026-10-16) |
| Month rail | Many months (or a long list by month) on one page: a dot per month down the right edge, the one on show bigger and named at rest ("Sep"), a year's first month carrying its year, cleared months green; a finger on it runs through the months, a tick each, a pill naming the one under it (To make up; Journey's card and its expanded weeks hold the names instead; owner 2026-10-17: "Yeah, I like A … we should definitely keep that somewhere"; picture 26) |
| Grows into the calendar | A compact grid that opens to the whole screen as itself: the same rows grow, its tiles fly into rings, its names gain their numbers, centred on their months; the rest of the page lifts away; focus only by a tap (a day, or a name), everything else faded; pinch back to tiles, a toggle to the year (Journey's card, owner 2026-10-17: "I imagine it literally just expands the card so that the same tiles and rows turn into our view of the calendar"; picture 30) |
| Picked day: top and bottom | A day picked from a grid (the card's tiles, the month's rings) takes the place's top and bottom instead of opening: the top its fifths ring with the score, the date, "Day N · Rth of M" and its kind (the day's ring opens it, flying into it), the bottom its notes · photos · on the map · zikr as counts that open them; each area on its own hairline, nothing below moves (Journey, owner 2026-10-17: "let's put like separators or something. So that the top area and the bottom area have like a dedicated space"; picture 27) |
| Slot readout | A chart you can touch: tap, or hold and drag across, its columns; the one under the finger stays dark, the rest fade, and its numbers replace the lines above the chart in the same room ("38 prayers (12%) · 10–20 min after it starts · Middle"); a tap elsewhere puts them back (Prayer scores' histogram, owner 2026-10-17; picture 28) |
| Fold into the day | A mark's moment on the Salah circle: the arc sweeps closed with the day ring's hollow dot popped in where it was marked, then the whole ring folds along itself into the prayer's fifth (its ends slide to the fifth's, the dot rides along, the band thins to the day ring's); the other fifths draw in round it, marked in their colors, the rest faint dashes, with "3 of 5 today" under the words; it holds, then the next prayer comes in — a tap moves on, the last of the five lands on the day page in place. One dial, every beat eased on its own stretch, as Journey's flights (owner, 2026-10-17: "After sweeping, it smoothly glides it into the fifth that it belongs at"; picture 29) |
| Scrolling sage chips | For a choice with no fixed count (a zikr's goals — could be 10): chips that scroll sideways. A capsule switch only for a fixed two or three (Sadaqah \| Community) |

## The 24 pictures

01 Salah ring · 02 Salah + list · 03 the day's page · 04 Zikr wheel · 05 session pause · 06 setup hadith · 07 "welcome to shukr" · 08 setup welcome · 09 prayer photo · 10 Memories · 11 qibla map · 12 Live Activity card · 13 Explore shukr · 14 Give to Causes · 15 New task goal · 16 zikr card modal · 17 setup: notifications off · 18 setup: Live Activities · 19 setup: Fajr alarm off · 20 setup: location off · 21 "All reminders topped up" sheet · 22 calibrate your compass · 23 "Your prayer reminders are off" sheet (home) · 24 "shukr lost your location" · 25 Your journey (the week grid) · 26 Journey's month (retired) · 27 a picked day's top and bottom · 28 Prayer scores' slot readout · 29 a mark folding into the day ring · 30 the expanded card.
