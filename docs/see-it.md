# How to see it — the views that only show in a certain state

Owner, 2026-10-21: "give me links to all these views in the dev settings section. or a prompt to get you guys to show me in
simulator. just keep a document handy so it lists it out. especially things i wouldn't be able to normally see on my phone."

Three ways in, for each view below:
- **On your phone, Dev Stuff:** Settings → tap "Sneak Peek…" → My Dev Stuff. The newest rows are at the top
  ("Dev · Goal ladder"). Toggles keep their view on until you turn them off.
- **In the sim:** paste the **Ask** line to any of us ("Zoe, show me …"). We launch the real app on our own sim with your
  data copy and send you a picture.
- **On your phone with arguments:** the same launch arguments work through an install ("Zoe, open … on my phone"); they
  last that one launch.

Every launch argument is DEBUG-only. `-demoLand salah|zikr|journey|settings` lands on a page with no welcome, setup or tour.
Whoever adds a view that needs a certain state adds its line here in the same commit.

## Goal ladder (Journey, the Salah page)

Not on the team line yet: these are in Zoe's work in progress (local on zoe/main, waiting on his look OK); the Dev Stuff
rows and the `-demoGoalOffer` / `-demoMidweek` / `-demoMorningLine` arguments arrive with it.

| View | Shows for real when | Dev Stuff | Ask / launch arguments |
|---|---|---|---|
| Sunday sheet, one step up | First app open on Sunday, after 3 weeks met at your goal | "Sunday sheet: one step up" | "Show me the Sunday step-up sheet" · `-demoLand salah -demoGoalOffer up` |
| Sunday sheet, one step down | First app open on Sunday, after 2 weeks short of your goal (none on Prayed) | "Sunday sheet: one step down" | "Show me the Sunday step-down sheet" · `-demoLand salah -demoGoalOffer down` |
| Week out of reach (Journey's week card: "N left · make them count", the days to come hollow) | Mid-week, once your goal can't be met this week | "Week out of reach (Journey)" | "Show me the week out of reach" · `-demoLand journey -demoMidweek` |
| Morning after a miss (the line under the Salah ring) | Fajr → Dhuhr, the day after an unmarked prayer | "Morning after a miss (Salah page)" | "Show me the morning line" · `-demoLand salah -demoMorningLine` |
| Journey counted at another goal | Your goal in Settings → Your goal | — (change your goal, then change it back) | "Show me Journey on Middle" · `-demoLand journey -prayerStreakMode "<integer>3</integer>"` (1 Prayed · 2 In its window · 3 Middle · 4 Opening; your saved goal untouched) |

## Marking and records (the Salah page, Journey)

| View | Shows for real when | Ask / launch arguments |
|---|---|---|
| The late-mark question (In its window → Set a time · I don't know the time / Making it up now) | You mark a prayer after its window ends | Mark any earlier prayer today from the circle or the list |
| The same question, for a widget / notification / watch mark | At the next open after an outside late mark | "Show me the late question for an outside mark" · `-demoLateOutsideMark` |
| No-record card ("Yesterday has no record. Did you pray?") | A day you opened the app nowhere | "Show me the no-record card" · `-demoLand salah -demoNoRecordCard` |
| Your prayers page, a prayer open | Journey → Your prayers → a prayer | "Show me Your prayers open on Asr" · `-demoLand journey -demoPrayerScores Asr` |
| A Journey day page | Journey → a day | "Show me Journey's day page, 3 days back" · `-demoLand journey -demoJourneyDay 3` |
| To make up | Journey → To make up | `-demoLand journey -demoJourneyMakeUp` |
| A milestone celebration | A milestone reached | "Show me a milestone celebration" · `-demoMilestoneCelebration` |
| The streak celebration | A streak kept | `-demoStreakCelebration` |
| The prayer-completion moment | Marking a prayer | `-demoPrayerCompletion` |
| The post-salah offer under the circle | Marking the prayer on now | `-demoPostSalahOffer` |
| The prayer-begins moment | A prayer's window opening with the app open | Dev Stuff "Preview prayer begins" · `-demoPrayerStart` |

## Compass, Excused Mode, reminders

| View | Shows for real when | Ask / launch arguments |
|---|---|---|
| "Compass needs calibration · tap" + the ☰ red dot | The compass reads untrustworthy for ~3 s | `-demoCompassUnreliable` (add `-demoMenuOpen` for ☰'s row) |
| The calibration page | That line tapped | `-demoCalibrationSheet` |
| Excused Mode's daily ask / its first-time story | Excused Mode on | `-demoExcusedAsk` / `-demoExcusedIntro` |
| Notifications' top-up sheet | Reminders topped themselves up | `-demoTopUpSheet` |
| Every notification shukr sends | Through the day | Dev Stuff "Send notification samples" (lock the phone) |
| The masjid arrival dua | Arriving at a masjid | `-demoMasjidDua` |

## The first run and what's new

| View | Ask / launch arguments |
|---|---|
| The welcome | `-demoWelcome` |
| Setup from the start | Dev Stuff "Run setup from the start" |
| What's new | `-demoWhatsNew` |
