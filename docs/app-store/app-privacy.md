# App Privacy (App Store Connect → App Privacy) — draft answers (Ben, 2026-10-04)

**What the app does with data (verified in the code, 2026-10-04):** no server of ours, no account, no analytics /
crash / ad SDK (the only package is adhan-swift, on-device). Location goes to Apple's Core Location / MapKit for the
city name, the map, mosque search and Look Around; directions open Apple Maps / Google Maps / Waze with the
destination. Microphone and camera content stays in the app's container. Notifications are local. Watch data moves
device-to-device (Watch Connectivity). TestFlight feedback is shared by the user through the share sheet.

## The questionnaire

**Do you or your third-party partners collect data from this app?** → **No** ("Data Not Collected"), recommended.

Apple's definition: data is "collected" when it is transmitted off the device in a way that is accessible to you or a
third-party partner. Nothing is transmitted to us. The one thing to confirm is Apple's own services: location is sent
to Apple's geocoder and MapKit on the user's behalf. Apple's guidance treats data sent to Apple's frameworks for the
app's functionality, under Apple's privacy policy, as not the developer's collection — **TODO: re-read the current
"App privacy details on the App Store" page before submitting**, and if it has changed, answer instead:

- Location → Precise Location → used for **App Functionality** → **not linked** to the user's identity → **not used
  for tracking**.

Everything else is "not collected": no contact info, no identifiers, no usage data, no diagnostics of ours (Apple's
crash logs are Apple's), no user content leaves the device (photos, audio, notes are stored locally only).

**Tracking:** No. The app has no ad network, no cross-app identifier, no ATT prompt.

## Privacy manifest (PrivacyInfo.xcprivacy) — a submission requirement, not a questionnaire answer

Checked 2026-10-04: the app and the widget extension already ship one (`shukr/PrivacyInfo.xcprivacy`,
`shukrWidget/PrivacyInfo.xcprivacy`): tracking false, UserDefaults with reasons CA92.1 + 1C8F.1. Two gaps:

- **The watch app has none** and it reads the app-group UserDefaults too. `PrivacyInfo.xcprivacy` in this folder is a
  ready copy for it (UserDefaults CA92.1, plus the file-timestamp category below). **TODO (Sami): add it to the watch
  target.**
- **File timestamps:** the app reads file attributes in a few places (BuildInfo.swift, LocMans.swift's log,
  PlaceMoments.swift, WatchZikrSync.swift — `attributesOfItem` / `contentModificationDateKey`). If any of those is a
  file-system timestamp read (not a model's Date), the app's manifest needs
  `NSPrivacyAccessedAPICategoryFileTimestamp` with reason **C617.1** (files inside the app's own container). **TODO
  (Frank): confirm the four sites and add the category if so.** Apple flags missing reasons as ITMS-91053 in the
  upload mail from `scripts/testflight.sh`; a clean upload mail is the check.

## Permission strings (already in the build; here for the record)
- Location (When In Use / Always): on-device prayer times, qibla, prayer pins; Always = travel, widget / watch marks
  pinned, masjid duas. "Your location stays on your phone."
- Camera: a photo of a written dua, kept with the zikr on the iPhone.
- Microphone: a memo of how a zikr is said, kept on the iPhone.
- AlarmKit (iOS 26.1+): the Fajr alarm.
