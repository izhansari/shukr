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
- Explore (`ExploreDock`: Qibla · Prayers · Mosques) under the globe / locate capsule, opening downwards: the button turns
  into ✕ while open, one short ease (`ExploreDock.motion`, no bounce / stagger — owner: "don't go overboard"); the ? bottom
  right hides while it's open. DEBUG `-demoMapLayer prayers|mosques` and others in LocationMapView2.swift; `-logMapFrames YES` measures in the
  sheet's own space (global frames go stale while UIKit moves a sheet). Test the map on an iOS 27 sim.

**Mosques, My masajid, masjid-aware prayers** (MosqueFinder.swift, MasjidDetector.swift, PlaceMoments.swift)
- Mosques in the one map sheet (`mosquePath`): nearest list, drive / walk, Look Around, Directions, Call, place card. `MosqueFavorites` (star pins), `MosqueHiding` (not recommended).
- `MasjidDetector` (75 m) sets `mosqueName` (2.2.0) → Jumu'ah — only from a usable fix: the app records a spot under 10 min / 500 m and searches only from ≤ 100 m (else `mosqueName = ""`); widget / watch marks use the saved spot only while `lastFixAt` (a real fix, cleared by a picked city) is under 30 min; `check` re-guards the row after its await; `MasjidArrival` duas (CLMonitor, opt-in; 200 m — a radius change re-adds the conditions, reports in the next 30 s are a baseline; a newly watched masjid is recorded as outside so the first arrival counts; DEBUG Library/Caches/masjid.log = every iOS report, the decision and each dua sent; the simulators don't deliver region events, test on a real visit); `HolyCityWelcome`.

