//
//  PostSalah.swift
//  shukr
//
//  Post-salah zikr, Tasbih Fatimah's 33 · 33 · 34: the session's rules, the reminder under the circle, the pause card and
//  the phrase strip. Moved out of tasbeehView.swift (cleanup-map tangle 5, step 3).
//

import SwiftUI
import SwiftData

/// Post-salah zikr (redesigned 2026-09-25): one 100-count session — Subhanallah ×33,
/// Alhamdulillah ×33, Allahu Akbar ×34 — saved once, under a "Tasbih Fatimah" mantra (the
/// traditional name for it), instead of three chained sessions that each reset the count, saved
/// separately and ended without a results screen. The phrase follows the count.
enum PostSalahTasbeeh {
    static let mantraName = "Tasbih Fatimah"
    static let phases: [(name: String, arabic: String, count: Int)] = [
        ("Subhanallah", "سُبْحَانَ ٱللَّٰهِ", 33),
        ("Alhamdulillah", "ٱلْحَمْدُ لِلَّٰهِ", 33),
        ("Allahu Akbar", "ٱللَّٰهُ أَكْبَرُ", 34),
    ]
    static var total: Int { phases.reduce(0) { $0 + $1.count } }

    /// The ring at a total count: the phrase's share, in step with the big number (0…33 · 0…33 · 0…34), so it's
    /// empty again the moment a phrase is done. Never 1 before 100: the session's progress is this value, and a full
    /// ring before the end once stopped the session at 33 (a276904, Bradley).
    static func ringFraction(at count: Int) -> Double {
        let p = phase(at: count)
        return Double(p.done) / Double(p.of)
    }

    /// The phrase at a total count, and how far into it (0-based index; `done` of `of`).
    static func phase(at count: Int) -> (index: Int, done: Int, of: Int) {
        var start = 0
        for (i, p) in phases.enumerated() {
            if count < start + p.count || i == phases.count - 1 {
                return (i, min(count - start, p.count), p.count)
            }
            start += p.count
        }
        return (0, 0, phases[0].count)
    }

    /// Sets up the session: a 100-count goal on the Tasbih Fatimah mantra (made on first use,
    /// with the three phrases as its full text so the pause card shows them).
    static func prepare(_ state: SharedStateClass, in context: ModelContext) {
        let mantra = MantraModel.find(named: mantraName, in: context) ?? {
            let text = phases.map { "\($0.arabic)  ×\($0.count)" }.joined(separator: "\n")
                + "\nSubhanallah · Alhamdulillah · Allahu Akbar"
            let new = MantraModel(name: mantraName, fullText: text,
                                  notes: "After each obligatory prayer: 33, 33 and 34 — 100 in all.")
            new.builtInID = BuiltInAzkar.key(BuiltInAzkar.tasbihFatimahName)
            context.insert(new)
            return new
        }()
        state.selectedMode = 2
        state.selectedMinutes = 0
        state.targetCount = String(total)
        state.mantraForSession = mantra
        state.titleForSession = mantra.name
    }
}

/// Under the circle during post-salah zikr: why it's worth the minute (owner asked for a
/// reminder of its significance). Both narrations are the well-known ones: the 33/33/34 after
/// each obligatory prayer (Sahih Muslim, from Ka'b ibn 'Ujrah) and the Prophet ﷺ teaching the
/// same words to Fatimah as better than a servant (Bukhari and Muslim, from 'Ali).
struct PostSalahReminder: View {
    var variant = 0

    /// Why this zikr matters, to move people to do it (owner): a short headline — the reason — and
    /// the narration behind it. One per session. Well-known narrations, paraphrased; no hadith
    /// numbers until checked.
    static let reminders: [(title: String, text: String, source: String)] = [
        ("Never let down",
         "Whoever says these after every obligatory prayer is never disappointed.",
         "Sahih Muslim"),
        ("Keep pace with the best",
         "The poor feared the wealthy were ahead of them in charity. The Prophet ﷺ gave them these words after every prayer: no one would surpass them, except one who did the same.",
         "Sahih al-Bukhari · Sahih Muslim"),
        ("They fill the scales",
         "Alhamdulillah fills the Scale, and Subhanallah with Alhamdulillah fill what is between the heavens and the earth.",
         "Sahih Muslim"),
        ("Better than a servant",
         "Worn out by her work, Fatimah asked for a servant. The Prophet ﷺ gave her these hundred words instead, and said they were better for her.",
         "Sahih al-Bukhari · Sahih Muslim"),   // its text doesn't say when — it was taught for bedtime
    ]
    static var count: Int { reminders.count }

    var body: some View {
        let r = Self.reminders[variant % Self.count]
        VStack(spacing: 8) {
            // Quieter than the count (owner: in dark mode it read bright white).
            Text(r.title)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(0.5))
            Text(r.text)
                .font(.footnote.weight(.light))
                .foregroundStyle(.primary.opacity(0.36))
            Text(r.source)
                .font(.caption2)
                .foregroundStyle(Color.sage.opacity(0.75))
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .fontDesign(.rounded)
    }
}

/// The pause screen's card for Tasbih Fatimah: the three phrases as rows — done ✓, the current
/// one with its count, the rest to come — plus the hadith's line. Replaces the mantra card
/// (nothing to edit here; owner: "it's a special one").
struct PostSalahPauseCard: View {
    let count: Int
    /// Inside the soft pause screen's text well: no name (the name row has it) and no card of its own.
    var bare = false

    var body: some View {
        if bare {
            content.padding(12)
        } else {
            content
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
    }

    private var content: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        return VStack(alignment: .leading, spacing: 14) {
            if !bare {
            Text(PostSalahTasbeeh.mantraName)
                .font(.system(size: 24, weight: .light, design: .rounded))
            }
            VStack(spacing: 8) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, phrase in
                    let done = i < now.index || (i == now.index && now.done >= now.of)
                    let current = i == now.index && !done
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phrase.name)
                                .font(.system(size: 16, weight: current ? .regular : .light, design: .rounded))
                                .foregroundStyle(current ? .primary : .secondary)
                            Text(done ? "done" : current ? "\(now.done) of \(phrase.count)" : "\(phrase.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(done ? Color.green : .secondary)
                        }
                        Spacer(minLength: 8)
                        Text(phrase.arabic)
                            .font(.custom("KFGQPCUthmanTahaNaskh", size: 24))
                            .foregroundStyle(current ? .primary : .secondary)
                            .environment(\.layoutDirection, .rightToLeft)
                        Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(done ? Color.green : current ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(width: 22)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(current ? Color.green.opacity(0.08) : Color.primary.opacity(0.03))
                    )
                }
            }
            Text("Never disappointed — Sahih Muslim")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Above the circle during post-salah zikr: the current phrase (Arabic + name), its own count,
/// and three segments that fill phrase by phrase.
struct PostSalahPhaseStrip: View {
    let count: Int

    var body: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        let phrase = PostSalahTasbeeh.phases[now.index]
        VStack(spacing: 8) {
            Text(phrase.arabic)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 30))
                .id(now.index)
                .transition(.blurReplace)
            HStack(spacing: 6) {
                Text(phrase.name)
                Text("·").foregroundStyle(.tertiary)
                Text("\(now.done) of \(now.of)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(now.done)))
            }
            .font(.subheadline.weight(.light))
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, p in
                    let fill: Double = i < now.index ? 1 : i > now.index ? 0 : Double(now.done) / Double(p.count)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.sage).frame(width: geo.size.width * fill)
                        }
                    }
                    .frame(width: 44, height: 4)
                }
            }
        }
        .fontDesign(.rounded)
        .animation(.snappy(duration: 0.3), value: count)
    }
}
