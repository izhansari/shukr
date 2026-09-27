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
             note: "“All praise is for Allah.” It fills the Scale. (Muslim 223)"),
        Zikr(name: "Subhanallah",
             arabic: "سُبْحَانَ ٱللَّٰهِ",
             note: "“Glory be to Allah.” Said 100 times, a thousand good deeds are written or a thousand sins wiped away. (Muslim 2698)"),
        Zikr(name: "Allahu Akbar",
             arabic: "ٱللَّٰهُ أَكْبَرُ",
             note: "“Allah is the Greatest.” Among the four words most beloved to Allah. (Muslim 2137)"),
        Zikr(name: "Astaghfirullah",
             arabic: "أَسْتَغْفِرُ ٱللَّٰهَ",
             note: "“I seek Allah’s forgiveness.” The Prophet ﷺ sought forgiveness more than 70 times a day. (Bukhari 6307)"),
        Zikr(name: "La ilaha illallahu wahdahu",
             arabic: "لَا إِلَٰهَ إِلَّا ٱللَّٰهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ ٱلْمُلْكُ وَلَهُ ٱلْحَمْدُ، وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ",
             note: "“None has the right to be worshipped but Allah alone, without partner. His is the dominion and His is the praise, and He is over all things capable.” Said 100 times a day: like freeing ten slaves, 100 good deeds written, 100 sins erased, and protection from Shaytan until evening. (Bukhari 3293, Muslim 2691)"),
        Zikr(name: "SubhanAllahi wa bihamdihi",
             arabic: "سُبْحَانَ ٱللَّٰهِ وَبِحَمْدِهِ",
             note: "“Glory be to Allah, and praise be to Him.” Said 100 times a day, sins are forgiven even if they are like the foam of the sea. (Bukhari 6405, Muslim 2691)"),
        Zikr(name: "Allahumma salli 'ala Muhammad",
             arabic: "ٱللَّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ",
             note: "“O Allah, send blessings upon Muhammad.” Whoever sends one blessing on the Prophet ﷺ, Allah sends ten on them. (Muslim 408)"),
        Zikr(name: "Hasbunallahu wa ni'mal-wakil",
             arabic: "حَسْبُنَا ٱللَّٰهُ وَنِعْمَ ٱلْوَكِيلُ",
             note: "“Allah is sufficient for us, and He is the best Disposer of affairs.” (Quran 3:173)"),
    ]

    static let doneKey = "builtInAzkar.v1"
    /// The original four's own seed-once flag (the V2 data pass used to re-seed one every launch).
    static let originalsSeededKey = "builtInAzkar.originalsSeeded"

    /// Built-ins (and the app's own Tasbih Fatimah) are locked: name and full text can't change
    /// and they can't be deleted; notes, memo and photo stay the user's (owner, 2026-09-27).
    static let lockedKeys: Set<String> = Set(all.map { key($0.name) } + MantraModel.builtIn.map(key) + [key("Tasbih Fatimah")])
    static func isBuiltIn(_ name: String) -> Bool { lockedKeys.contains(key(name)) }
    /// Built-ins in their own order (the four originals, then the rest, then Tasbih Fatimah).
    static func order(_ name: String) -> Int {
        let k = key(name)
        return all.firstIndex { key($0.name) == k } ?? all.count
    }

    /// "SubhanAllahi wa bihamdihi" == "subhanallahi wabihamdihi": letters and digits only.
    static func key(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
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
                    if touched { filled += 1 }
                } else {
                    let m = MantraModel(name: z.name, fullText: z.arabic, notes: z.note)
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
