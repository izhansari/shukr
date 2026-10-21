//
//  NoRecordDay.swift
//  shukr
//
//  A day with no record (prayer-metrics rethink phase 6; board/scoring-rethink/plan-v3.md §3). 364 of his 690 days had
//  nothing logged — the app not opened, or opened and nothing marked — and every metric read them differently. A
//  no-record day is unknown, never "missed"; one quiet card asks "Wednesday has no record. Did you pray?" with "Pick
//  which" · "Not now", one day at a time. Picked prayers are marked in their time with no clock (MarkKind.timeUnknown —
//  nothing faked); the rest of that day is then a day with a record, so its unmarked prayers go on To make up, honestly.
//
//  This file is the logic and a first look on the design guide's vocabulary; where the card sits (Journey's top) and its
//  final look are Zoe's (board/scoring-rethink/work-split.md).
//

import SwiftUI
import SwiftData

@MainActor enum NoRecordDays {
    /// How far back the card asks: older gaps stay unknown (a fill-in weeks later isn't a memory anyone has).
    static let lookBack = 7
    static let dismissedKey = "noRecord.dismissed"
    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    /// The most recent prayer day before today with nothing marked: on or after the first day anything was ever marked
    /// (and the fresh start, if any), not touched by Excused Mode, not answered "Not now". nil = nothing to ask.
    static func next(in context: ModelContext, now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let todayKey = PrayerDay.key(for: now)
        guard let today = PrayerDay.start(ofKey: todayKey) else { return nil }
        // The first mark ever: a new user's empty past isn't "no record".
        var first = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted },
                                                 sortBy: [SortDescriptor(\.startTime, order: .forward)])
        first.fetchLimit = 1
        guard let firstMark = (try? context.fetch(first))?.first?.dayStart else { return nil }
        let from = max(firstMark, PrayerStats.countsFrom.map { cal.startOfDay(for: $0) } ?? .distantPast)
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        let excused = Excused.Days()
        for back in 1...lookBack {
            guard let day = cal.date(byAdding: .day, value: -back, to: today), day >= from else { break }
            let key = PrayerNotificationID.dayKey(day)
            if dismissed.contains(key) || excused.excludes(day) { continue }
            let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: day)))) ?? []
            if !rows.contains(where: \.isCompleted) { return day }
        }
        return nil
    }

    /// "Not now": this day isn't asked about again.
    static func dismiss(_ day: Date) {
        var keys = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        keys.append(PrayerNotificationID.dayKey(day))
        UserDefaults.standard.set(Array(keys.suffix(60)), forKey: dismissedKey)
    }

    /// The picked prayers of `day`, marked in their time with no clock. A day the app was never opened has no rows: they're
    /// made from that day's times (here, as the list makes them).
    static func fill(_ day: Date, picked: Set<String>, viewModel: PrayerViewModel) {
        // "None of them": answered — not asked again; nothing is made (a day of five unmarked rows would still read "no
        // record", and the card would come straight back — Fable's review).
        guard !picked.isEmpty else { dismiss(day); return }
        let context = viewModel.context
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: day)))) ?? []
        let noon = day.addingTimeInterval(12 * 3600)   // a time on that date for the times lookup
        // All five rows, picked or not: a day filled in is a day with a record, so the ones left are owed (To make up).
        for name in names {
            guard let row = rows.first(where: { $0.name == name }) ?? viewModel.createPrayerModel(name: name, at: noon),
                  picked.contains(name), !row.isCompleted else { continue }
            row.isCompleted = true
            row.mosqueName = ""   // no spot was recorded, so no masjid search
            row.markKind = MarkKind.timeUnknown.rawValue
            row.setPrayerScore(atDate: Date())   // the tap; in its time whatever it says
        }
        try? context.save()
        viewModel.calculateDayScore(for: day)
        viewModel.calculatePrayerStreak()
        DayHistory.invalidate()
        viewModel.pushCompletionsToWidget()
        viewModel.contentChanged()
        JourneyChange.post()
    }

    /// "Wednesday" within the week, else "Oct 12".
    static func name(of day: Date, now: Date = Date()) -> String {
        let daysAgo = Calendar.current.dateComponents([.day], from: day, to: Calendar.current.startOfDay(for: now)).day ?? 99
        if daysAgo == 1 { return "Yesterday" }
        return daysAgo < 7 ? day.formatted(.dateTime.weekday(.wide)) : day.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The card: one quiet line and two answers. Zoe places it (Journey's top) and owns its look.
struct NoRecordCard: View {
    let day: Date
    var onPick: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(NoRecordDays.name(of: day)) has no record. Did you pray?")
                .font(.system(size: 16, weight: .regular, design: .rounded))
            HStack(spacing: 18) {
                Button(action: onPick) {
                    Text("Pick which").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.primary)
                }
                Button(action: onNotNow) {
                    Text("Not now").font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.tertiarySystemFill)))
    }
}

/// "Pick which": the day's five, each one tapped on or off; Save marks the picked ones in their time.
struct NoRecordPickSheet: View {
    let day: Date
    var onSave: (Set<String>) -> Void
    @State private var picked: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    /// One height from the first frame, sized to what it holds (Frank / Fable: it changed detent right after opening, so a
    /// tap during the move landed on the wrong row; 560 also left an empty band under the button). Larger text scrolls in it.
    static let height: CGFloat = 486

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Text("Which did you pray in their time?").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            VStack(spacing: 0) {
                ForEach(NoRecordDays.names, id: \.self) { name in
                    Button {
                        triggerSomeVibration(type: .soft)
                        if picked.contains(name) { picked.remove(name) } else { picked.insert(name) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: picked.contains(name) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(picked.contains(name) ? AnyShapeStyle(MarkKind.inTimeColor) : AnyShapeStyle(.secondary))
                            Text(name).font(.system(size: 18, weight: .light, design: .rounded))
                            Spacer()
                        }
                        .padding(.vertical, 12).padding(.horizontal, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("No time is recorded. The ones you leave go on To make up.")
                .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.horizontal, 24)
            Button {
                onSave(picked)
                dismiss()
            } label: {
                Text(picked.isEmpty ? "None of them" : "Save")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: 240, height: 52)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fontDesign(.rounded)
        .presentationDetents([.height(min(Self.height, UIScreen.main.bounds.height * 0.9))])
        .presentationDragIndicator(.visible)
    }
}
