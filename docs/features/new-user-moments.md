# New-user moments — everything that shows once

Owner, 2026-10-20: "a lot of stuff in the app that I don't see, or I forget about … because a lot of it is for new
users … lets save this somewhere so i have somewhere to check these things." Every screen, hint or celebration that a
user sees once (or until they act), so he can find them again. **A new one-time screen adds its row here in the same
commit; removing one deletes its row.** The page he opens, https://claude.ai/artifact/X3fmUNJrXdmCq79RzCZSNz, is rebuilt from this file (republish it from the same Artifact URL).

## Only on a fresh install
| What | When a new user sees it | See it again | Code · key |
|---|---|---|---|
| Setup: hadith → location → method → Asr → appearance → reminders → Live Activities → Fajr alarm → masjid → review → bismillah → opening | First launch | My Dev Stuff → Run setup from the start (dev builds) | FirstRunSetup.swift · `firstRunSetup.v1` |
| Tour invitation "Want a quick look around?" | 3 s after setup | With the app tour below | Tour.swift · `tour.v1.pending` |
| App tour: 1 Prayer Circle (qibla, mark) · 2 Prayer List (edit Fajr to Qaza, Save) · 3 Settings (bell, Live Activities, Fajr alarm, ⓘ) | From the invitation | Settings → Tours → Take the app tour again (everyone) | Tour.swift, TourCopy.swift · `tour.v1.done`, `tour.v2.completed` |
| Green dot on ☰ | After Later or a skip, until the tour is finished | — | `TourMenuBadge` |
| First-mark celebration: edge glow + "Your first prayer, marked." | First real mark after setup | Comes back with the app tour replay | Tour.swift · `tour.firstMark.armed` |
| Zikr lock (the hadith flow): Zikr frosted; 1 the verse · 2 the narration (Bukhari 7405) · the three ways to count · 3 pick the first zikr → its first session → unlocked | Installs with no zikr history (anyone with a task or session when the lock arrived keeps Zikr open — his phone did) | Settings → Tours → Take the zikr tour again (plays over an open tab); My Dev Stuff → Zikr locked (test) | ZikrLock.swift · `zikrLock.alreadyUsed`, `zikrTour.v1.completed` |
| Count tips: 1 Counting (tap · drags · one stroke) · 2 Pausing · 3 After (Done · History · delete the practice session, never saved) | First freestyle session | Come back with the app tour replay | CountTips.swift · `countTips.v3.stage` |

## Once, whenever they first get there
| What | When | See it again | Code · key |
|---|---|---|---|
| Map guide: 3 pages each for qibla, prayer spots, mosques | First open of each map layer | The map's ? | QiblaMapGuide.swift · `qiblaMapGuideSeen`, `mapGuideSeen.<layer>` |
| Sleep mode intro | First tap on the session's sleep chip | The chip's (i) | SleepMode.swift · `sleepIntroConfirmed` |
| Excused Mode story | First open of Excused Mode | DEBUG `-demoExcusedIntro` | Excused.swift · `excused.introSeen` |
| Watch: "Pinch to count · or turn the Crown" | First watch session | — | WatchZikr.swift · `watch.countHintSeen` |
| Milestone celebrations (Day one, first week, every hundred prayers …) | When earned; the first check after install / update records what's already earned silently | DEBUG `-demoMilestoneCelebration` | YourJourney.swift · `journey.milestones.seen` |
| "New" on Explore cards | Features under 30 days old, until opened | — | ExploreSimple.swift · `explore.opened.<id>` |

## Off, code kept
- The app tour's Zikr chapter (Tour.swift `.zikr`, TourCopy.Zikr): unreached since the Classic flow went (v2 goes List → Settings).
- The first-mark pill card and map hint after the celebration (off since 2026-10-14; owner wants to come back to them).
