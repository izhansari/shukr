# App Store readiness — drafts (Ben, 2026-10-04; queue app-store-drafts)

Everything App Store Connect will ask for, drafted from the code and docs/app-store-features.md. Nothing here is
deployed or submitted; Izhan reviews and pastes. Facts I didn't have are marked **TODO** in each file and listed here.

## TODOs, in one pass (yours unless named)

**Facts only you have**
1. A support email address (support.html, privacy-policy.html, the ASC "support URL" page).
2. The developer / company name and country as it should appear (both pages; ASC shows your Apple Developer name).
3. A public URL for the two pages. Simplest: a folder on the board's Vercel project — but `board/site/` deploys itself
   from the Stop hook, so the pages go there only when you say; or any static host. ASC needs the privacy URL before
   submission; the support URL too.
4. Category (listing.md: Lifestyle + Reference proposed) and the final keywords.
5. The effective date on the privacy policy.

**Decisions**
6. The font: get KFGQPC's permission for Uthman Taha Naskh, or switch to an OFL face (Amiri Quran / Scheherazade New).
   content-rights.md has the options; a switch is five `.custom(` sites + the file (Frank).
7. The translations: keep Hilali–Khan and Ahmed Raza with their source's redistribution terms saved here, get
   permission, or switch to an openly licensed one (content-rights.md).

**Team work before submission (small, Frank / Sami)**
8. Watch app privacy manifest (app-privacy.md; the file is `PrivacyInfo.xcprivacy` here) — Sami.
9. File-timestamp reason in the app's manifest if the four sites read file attributes — Frank.
10. An Acknowledgements screen (Settings → About): adhan-swift's MIT text, the Quran text / translation / font
    notices once confirmed — Frank.
11. Screenshots at 6.9" and 6.5" (ten captions in listing.md; `-demo…` args and `scripts/circle-check.sh shots` give
    clean frames; the What's new shots folder is a pattern) — Frank, after you pick the captions.
12. `AyahShareCard.footer` → "download on the App Store" at release (CLAUDE.md, Open items).
13. `SHUKR_APPSTORE=1 scripts/testflight.sh` for the store archive (no What's new shots; `grep -c wn-` → 0).

**A person, not an agent**
14. The hadith references and wording in the post-salah session and the built-in azkar (content-rights.md, last row).

## Files
- `listing.md` — name, subtitle, promotional text, description, keywords, category, age rating, What's New,
  screenshot captions, App Review notes.
- `privacy-policy.html` — the policy page (dark / light, phone-width). Honest to the code: no server, no SDKs,
  Apple's location / maps services named.
- `support.html` — the support page: contact, six common questions, data.
- `app-privacy.md` — the App Privacy questionnaire answers ("Data Not Collected", with the one point to re-check) and
  the privacy-manifest state.
- `PrivacyInfo.xcprivacy` — a manifest for the watch target (and the timestamp category, if needed).
- `content-rights.md` — the inventory of third-party content and what each needs.

## What I verified in the code
No network calls of our own (only links out to quran.com, Google Maps, Waze and the Shortcut); one Swift package
(adhan-swift); no analytics / crash / ad SDK; entitlements: app group + time-sensitive notifications only; permission
strings for location (both levels), camera, microphone, AlarmKit; two privacy manifests shipping (app, widget).
