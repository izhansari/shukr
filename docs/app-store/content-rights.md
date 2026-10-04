# Content rights — what shukr ships that isn't ours (Ben, 2026-10-04)

App Store Connect asks "Does your app contain, show, or access third-party content?" and, if so, that you hold the
rights. App Review can ask for documentation. This is the inventory; every rights line is a TODO until the source and
its terms are confirmed in writing (a licence file or a page URL saved into this folder).

| File / content | What it is | Where it's used | Rights status |
|---|---|---|---|
| `shukr/quran.sqlite` (table `quran_text`) | The Arabic text of the Quran, Uthmani script | Daily Ayah, the share card, the widget | **TODO: source.** If it's Tanzil.net's Uthmani text, Tanzil allows free use with its copyright notice kept and the text unmodified — add the notice to an in-app About / acknowledgements. If it's from another project (quran.com's QUL, Quran Foundation), use that project's terms. |
| `shukr/english_hilali.sqlite` (`en_hilali`) | Hilali–Khan English translation ("The Noble Qur'an"), published by the King Fahd Glorious Quran Printing Complex (KFGQPC) | Daily Ayah (a selectable translation) | **TODO: permission.** The translation is KFGQPC's copyright. It is widely redistributed (Tanzil, quran.com) but the Complex's terms for apps aren't a general licence; either (a) get written permission, (b) keep it only if the source you took it from grants redistribution (keep that page), or (c) switch to an openly licensed translation. |
| `shukr/english_ar.sqlite` (`en_ahmedraza`) | Ahmed Raza Khan's English rendering (Kanzul Iman, English) | Daily Ayah (selectable) | **TODO: source and terms** — same three options as above. |
| `shukr/KFGQPCUthmanTahaNaskh.ttf` | KFGQPC Uthman Taha Naskh — the Complex's Quran typeface | Every Arabic line in the app (azkar, ayah, names) | **TODO: licence.** KFGQPC fonts are distributed by the Complex with their own terms; typical wording allows free personal / non-commercial use and asks for permission otherwise, and an App Store app (even a free one) may not count as non-commercial. Keep a copy of the terms page here. If permission isn't practical, the drop-in alternatives are SIL Open Font License faces: **Amiri Quran** or **Scheherazade New** (both OFL, free for any use; the OFL text must ship in the app). |
| Hadith texts and the built-in azkar notes (`tasbeehView.swift` Tasbih Fatimah, `BuiltInAzkar.swift`) | Short hadith quotations with references (Bukhari, Muslim) and the 99 Names' meanings | Post-salah session, azkar notes, 99 Names | Not a rights issue (short quotations with attribution) but an **accuracy** one: CLAUDE.md records they were written from memory. **TODO: a knowledgeable person checks every reference and wording before release.** |
| `adhan-swift` (Swift package) | Prayer-time calculation, MIT licence | All prayer times (app, widget, watch) | MIT: ship the licence text and copyright line in an in-app acknowledgements screen. **TODO: the app has no acknowledgements screen yet** — Settings → About → Acknowledgements (adhan-swift MIT; the Quran text, translations and font notices once confirmed; "Apple Maps" needs none). |
| SF Symbols, Apple Maps data, Look Around | Apple's | Everywhere | Covered by the Apple Developer Program licence; no action. |

## What to put in App Store Connect
- "Does your app contain, show, or access third-party content?" → **Yes**.
- "Do you have all necessary rights to that content, or are you otherwise permitted to use it?" → tick only once every
  TODO above is resolved and the terms are saved in this folder.

## Order of work
1. Find the origin of the three SQLite files (whoever built them in 2025 knows; the table names `quran_text`,
   `en_hilali`, `en_ahmedraza` match Tanzil's naming, which points at Tanzil's text + translation downloads).
2. Decide on the font: permission or switch to Amiri Quran / Scheherazade New (a one-line change per `.custom(` site,
   five places, plus the file; Frank).
3. Add the acknowledgements screen (Frank; small).
4. The hadith check (a person).
