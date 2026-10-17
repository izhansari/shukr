# Map and mosques — current state

Read with CLAUDE.md (rules, traps). When a feature changes, replace its lines here: current behaviour only,
≤ ~15 lines a feature; the story goes in the commit message. History: docs/history/.

**Map & qibla** (LocationMapView2.swift, MapModes.swift)
- Opens qibla-up (`pointQiblaUp`), free rotation, the compass ring on the dot (`MapAnchor`), a heavy buzz each second while aligned, `MapNorthButton` home.
- **One sheet** (`MapLayerSheet.swift`, map-one-sheet): up while prayer spots or mosques are on
  (`interactiveDismissDisabled`); `sheetDetent` small 84 / medium / large, the user's height kept. Content by state:
  mosques = list or `mosquePath.last`'s page; prayers = `PrayerSpotsHome` (prayers in view, `PrayerFilterMenu` on the
  header's right) or `selection`'s page (cluster list ⇄ prayer, in place). Pin taps cross-fade (`pageSwap`); ‹ back to the
  list. Every page wears `MapSheetHeader` (no ✕ anywhere — layers change in Explore; owner, D0C2E6DD). Small =
  the page's header alone in the shared `MapSheetCollapsed` (env `mapSheetCollapsed`). Editing a prayer sizes the sheet to
  the page (`setSpotMode`), then returns the user's height. `SheetMetrics` + `AboveSheet` float the ? above the sheet.
- Explore (`ExploreDock`: Qibla · Prayers · Mosques) under the map-style / locate capsule (`MapModes.styleSymbol` "map", as Find My; owner 2026-10-17 — the region's globe is gone here, on the prayer sheet's map and Memories'), opening downwards: the button turns
  into ✕ while open, one short ease (`ExploreDock.motion`, no bounce / stagger — owner: "don't go overboard"); the ? bottom
  right hides while it's open. DEBUG `-demoMapLayer prayers|mosques` and others in LocationMapView2.swift; `-logMapFrames YES` measures in the
  sheet's own space (global frames go stale while UIKit moves a sheet). Test the map on an iOS 27 sim.
- Locate (`centreOnUser`) lands you in the middle of the map the sheet leaves open (top controls → sheet), as a tapped pin
  does (`keepInView`) — measured with `regionThatFits` (the asked-for span undershot on a tall phone). A tapped pin, or one
  the map opens on, grows and sits on top in its score colour; no glow (owner, 2026-10-17).
- **The one-day map** (`LocationMapContentView(dayOnly:)` — from a day page or the card's picked day): that prayer day only.
  Find My's tabs at the sheet's foot (`dayTabs`, one a prayer, Jumu'ah on a Friday; a tab = `open(row)` and its pin, the open
  one again → the list; dimmed when not on the map). Its sheet opens at `LocationViewModel.dayFit` (400 pt, standing in for
  .medium in the detents, "up through" and where it opens — `useDayTabs`); small = 84 + the tab row. The sheet
  (`PrayerSpotsHome` dayOnly, MapLayerSheet.swift): the date (30 pt, the biggest text) over "Day 61 · 4 places" with the
  day's fifths ring in grade colours (`JourneyDayFifths(colored:)`), then `DayBento`: Where (the day's main place — most
  prayers, of equals the first — a ⌃⌄ menu picks another; a tap flies there), and one row: Prayed here (ever: the
  "prayed here" shortcut's rule, 100 m or the same masjid), Masjid, Moved. Owner: not Journey's own facts again. Tried and
  dropped: a places list (76161bf8), an editorial timeline (43a0e3b7), a Fajr → Isha time tile.

**Mosques, My masajid, masjid-aware prayers** (MosqueFinder.swift, MasjidDetector.swift, PlaceMoments.swift)
- Mosques in the one map sheet (`mosquePath`): nearest list, drive / walk, Look Around, Directions, Call, place card. `MosqueFavorites` (star pins), `MosqueHiding` (not recommended).
- `MasjidDetector` (75 m) sets `mosqueName` (2.2.0) → Jumu'ah — only from a usable fix: the app records a spot under 10 min / 500 m and searches only from ≤ 100 m (else `mosqueName = ""`); widget / watch marks use the saved spot only while `lastFixAt` (a real fix, cleared by a picked city) is under 30 min; `check` re-guards the row after its await; `MasjidArrival` duas (CLMonitor, opt-in; 200 m — a radius change re-adds the conditions, reports in the next 30 s are a baseline; a newly watched masjid is recorded as outside so the first arrival counts; DEBUG Library/Caches/masjid.log = every iOS report, the decision and each dua sent; the simulators don't deliver region events, test on a real visit); `HolyCityWelcome`.

