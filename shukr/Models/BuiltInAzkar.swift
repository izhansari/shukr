//
//  BuiltInAzkar.swift
//  shukr
//
//  The azkar that ship with the app, with their Arabic and a short note (2026-09-27, notes #17).
//  The first four have always been seeded as bare names (`MantraModel.builtIn`, every launch in
//  the V2 data pass); this fills them in and adds four more, ONCE (`doneKey`):
//  - a missing one is added with its text and note (matched by name, ignoring case, spaces and
//    punctuation, so a user's own "Subhanallahi wa bihamdihi" isn't doubled);
//  - an existing one only gets a field that's empty — the user's edits are never overwritten.
//  Once done it never runs again, so a deleted zikr or cleared note stays that way.
//
//  ⚠️ The sources were written from memory (owner + agent). They need a knowledgeable check
//  before release, like the Tasbih Fatimah reminders.
//

import Foundation
import SwiftData

enum BuiltInAzkar {
    struct Zikr { let name: String; let arabic: String; let note: String }

    static let all: [Zikr] = [
        Zikr(name: "Alhamdulillah",
             arabic: "ٱلْحَمْدُ لِلَّٰهِ",
             note: "• “All praise is for Allah.”\n• It fills the Scale. (Muslim 223)"),
        Zikr(name: "Subhanallah",
             arabic: "سُبْحَانَ ٱللَّٰهِ",
             note: "• “Glory be to Allah.”\n• Said 100 times: a thousand good deeds are written, or a thousand sins wiped away. (Muslim 2698)"),
        Zikr(name: "Allahu Akbar",
             arabic: "ٱللَّٰهُ أَكْبَرُ",
             note: "• “Allah is the Greatest.”\n• Among the four words most beloved to Allah. (Muslim 2137)"),
        Zikr(name: "Astaghfirullah",
             arabic: "أَسْتَغْفِرُ ٱللَّٰهَ",
             note: "• “I seek Allah’s forgiveness.”\n• The Prophet ﷺ sought forgiveness more than 70 times a day. (Bukhari 6307)"),
        Zikr(name: "La ilaha illallahu wahdahu",
             arabic: "لَا إِلَٰهَ إِلَّا ٱللَّٰهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ ٱلْمُلْكُ وَلَهُ ٱلْحَمْدُ، وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ",
             note: "• “None has the right to be worshipped but Allah alone, without partner. His is the dominion and His is the praise, and He is over all things capable.”\n• Said 100 times a day: like freeing ten slaves, 100 good deeds written, 100 sins erased.\n• Protection from Shaytan until evening. (Bukhari 3293, Muslim 2691)"),
        // The shahada (owner, 2026-10-08); the note checked against sunnah.com's Bukhari 128.
        Zikr(name: "La ilaha illallah, Muhammadur Rasulullah",
             arabic: "لَا إِلَٰهَ إِلَّا ٱللَّٰهُ مُحَمَّدٌ رَسُولُ ٱللَّٰهِ",
             note: "• “None has the right to be worshipped but Allah, and Muhammad is the Messenger of Allah.”\n• The Prophet ﷺ told Mu'adh: no one testifies to it sincerely from the heart except that Allah saves them from the Fire. (Bukhari 128)"),
        Zikr(name: "SubhanAllahi wa bihamdihi",
             arabic: "سُبْحَانَ ٱللَّٰهِ وَبِحَمْدِهِ",
             note: "• “Glory be to Allah, and praise be to Him.”\n• Said 100 times a day, sins are forgiven even if they are like the foam of the sea. (Bukhari 6405, Muslim 2691)"),
        // The Zikr Tour's first zikr (owner, 2026-10-08), the words of the last hadith in Sahih al-Bukhari (7563).
        Zikr(name: FirstZikr.name, arabic: FirstZikr.arabic, note: FirstZikr.note),
        Zikr(name: "Allahumma salli 'ala Muhammad",
             arabic: "ٱللَّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ",
             note: "• “O Allah, send blessings upon Muhammad.”\n• Whoever sends one blessing on the Prophet ﷺ, Allah sends ten on them. (Muslim 408)"),
        Zikr(name: "Hasbunallahu wa ni'mal-wakil",
             arabic: "حَسْبُنَا ٱللَّٰهُ وَنِعْمَ ٱلْوَكِيلُ",
             note: "• “Allah is sufficient for us, and He is the best Disposer of affairs.” (Quran 3:173)"),
    ]

    /// v2 (2026-10-08): the Zikr Tour's first zikr joins them; v3 (2026-10-08): the shahada; v4 (2026-10-08): the notes
    /// as bullet points (owner) — a note still exactly as we shipped it (`shippedNotes`) takes the new one; an edited
    /// note is left alone. Existing rows otherwise only get empty fields filled.
    static let doneKey = "builtInAzkar.v4"

    /// The notes as shipped before v4 (one sentence each, no bullets), to tell an untouched note from the user's own.
    static let shippedNotes: [String] = [
        "“All praise is for Allah.” It fills the Scale. (Muslim 223)",
        "“Glory be to Allah.” Said 100 times, a thousand good deeds are written or a thousand sins wiped away. (Muslim 2698)",
        "“Allah is the Greatest.” Among the four words most beloved to Allah. (Muslim 2137)",
        "“I seek Allah’s forgiveness.” The Prophet ﷺ sought forgiveness more than 70 times a day. (Bukhari 6307)",
        "“None has the right to be worshipped but Allah alone, without partner. His is the dominion and His is the praise, and He is over all things capable.” Said 100 times a day: like freeing ten slaves, 100 good deeds written, 100 sins erased, and protection from Shaytan until evening. (Bukhari 3293, Muslim 2691)",
        "“None has the right to be worshipped but Allah, and Muhammad is the Messenger of Allah.” The Prophet ﷺ told Mu'adh: no one testifies to it sincerely from the heart except that Allah saves them from the Fire. (Bukhari 128)",
        "“Glory be to Allah, and praise be to Him.” Said 100 times a day, sins are forgiven even if they are like the foam of the sea. (Bukhari 6405, Muslim 2691)",
        "“O Allah, send blessings upon Muhammad.” Whoever sends one blessing on the Prophet ﷺ, Allah sends ten on them. (Muslim 408)",
        "“Allah is sufficient for us, and He is the best Disposer of affairs.” (Quran 3:173)",
        "“Glory be to Allah, and praise be to Him. Glory be to Allah, the Most Great.” Two phrases, light on the tongue, heavy on the Scale, beloved to the Most Merciful. (Bukhari 7563, 6406)",
    ]
    /// The original four's own seed-once flag (the V2 data pass used to re-seed one every launch).
    static let originalsSeededKey = "builtInAzkar.originalsSeeded"

    /// Built-ins in their own order (the four originals, then the rest, then Tasbih Fatimah).
    static func order(_ name: String) -> Int {
        let k = key(name)
        return all.firstIndex { key($0.name) == k } ?? all.count
    }

    /// "SubhanAllahi wa bihamdihi" == "subhanallahi wabihamdihi": letters and digits only (any
    /// script). A name with none (all emoji / punctuation) falls back to itself, lowercased, so
    /// such names don't all collapse to "". Used for every zikr-name comparison: duplicates,
    /// seeding, the data pass's linking.
    static func key(_ name: String) -> String {
        let k = String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        return k.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : k
    }

    /// The app's own zikr names and their built-in ids (the id is the key of the name).
    static let tasbihFatimahName = "Tasbih Fatimah"
    static var canonicalNames: [String] { MantraModel.builtIn + all.map(\.name) + [tasbihFatimahName] }

    /// Every launch, cheap: mark the app's own rows as built-in (`builtInID`), by their EXACT
    /// seeded name — a user's "Subhan Allah" is never taken for one (2026-09-27 review; this used
    /// to be decided by a loose name match, which locked such rows). One row per id.
    @discardableResult
    static func tagRows(in context: ModelContext) -> Int {
        guard let rows = try? context.fetch(FetchDescriptor<MantraModel>()) else { return 0 }
        let taken = Set(rows.compactMap(\.builtInID))
        var tagged = 0
        for name in Set(canonicalNames) where !taken.contains(key(name)) {
            if let row = rows.first(where: { $0.builtInID == nil && $0.name == name }) {
                row.builtInID = key(name)
                tagged += 1
            }
        }
        if tagged > 0 { try? context.save() }
        return tagged
    }

    /// App only, after the V2 data pass. Returns a log summary, or nil when already done.
    @discardableResult
    static func applyIfNeeded(in context: ModelContext) -> String? {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return nil }
        do {
            var byKey: [String: MantraModel] = [:]
            for m in try context.fetch(FetchDescriptor<MantraModel>()) where byKey[key(m.name)] == nil {
                byKey[key(m.name)] = m
            }
            var added = 0, filled = 0
            for z in all {
                if let m = byKey[key(z.name)] {
                    var touched = false
                    if m.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.fullText = z.arabic; touched = true }
                    if m.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.notes = z.note; touched = true }
                    else if m.notes != z.note, shippedNotes.contains(m.notes.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        m.notes = z.note; touched = true
                    }
                    if touched { filled += 1 }
                } else {
                    let m = MantraModel(name: z.name, fullText: z.arabic, notes: z.note)
                    m.builtInID = key(z.name)
                    context.insert(m)
                    byKey[key(z.name)] = m
                    added += 1
                }
            }
            try context.save()
            defaults.set(true, forKey: doneKey)
            return "added=\(added) filled=\(filled)"
        } catch {
            print("❌ built-in azkar failed (will retry next launch): \(error)")
            return nil
        }
    }
}

/// The Zikr Tour's first zikr (owner, 2026-10-08: "SubhanAllahi wa bihamdihi, SubhanAllahil-'Azim … full arabic text,
/// notes/meaning, voice memo … 33 count goal"): a built-in (BuiltInAzkar), its words those of Sahih al-Bukhari 7563 —
/// the book's last hadith — checked on sunnah.com. Its recording ships in the app as `first-zikr.m4a` once it's in (ZikrLock.swift).
enum FirstZikr {
    static let name = "SubhanAllahi wa bihamdihi, SubhanAllahil-'Azim"
    static let arabic = "سُبْحَانَ ٱللَّٰهِ وَبِحَمْدِهِ، سُبْحَانَ ٱللَّٰهِ ٱلْعَظِيمِ"
    static let meaning = "Glory be to Allah, and praise be to Him. Glory be to Allah, the Most Great."
    static let note = "• “Glory be to Allah, and praise be to Him. Glory be to Allah, the Most Great.”\n• Two phrases, light on the tongue, heavy on the Scale, beloved to the Most Merciful. (Bukhari 7563, 6406)"
    static let source = "Light on the tongue, heavy on the Scale\nSahih al-Bukhari 7563"
    static let goal = 33
    /// The task's own short English name (owner: "our nicknames are usually english"; the zikr's full name doesn't fit a
    /// circle) — from the hadith.
    static let taskName = "Light on the Tongue"
    /// For display: one phrase a line.
    static let arabicLines = "سُبْحَانَ ٱللَّٰهِ وَبِحَمْدِهِ\nسُبْحَانَ ٱللَّٰهِ ٱلْعَظِيمِ"
    static let meaningLines = "Glory be to Allah, and praise be to Him.\nGlory be to Allah, the Most Great."
}
