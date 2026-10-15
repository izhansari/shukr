import SwiftUI
import SwiftData
import CoreLocation

/// A day in Journey (spec screen 2, mock-up Day5): the day's ring for any day (DayRing, as the Salah page's day page), its
/// score and "N of 5 in time"; the five prayers (time · place · grade, the photo); the notes; the day's zikr → History
/// filtered to that day. ‹ › walk the days from the first one to today. Marking from here is phase 2 (the prayer sheet).
struct JourneyDayPage: View {
    @State var date: Date
    let firstDay: Date?
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @State private var rows: [PrayerModel] = []
    @State private var sessions: [SessionDataModel] = []
    @State private var picked: Int?
    @State private var showZikr = false
    @State private var places = 0   // bumps as place names arrive
    @State private var pickToken = 0

    private var today: Date { PrayerDay.start() }
    private var canGoBack: Bool { firstDay.map { date > $0 } ?? false }
    private var canGoForward: Bool { date < today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading
                ring.frame(maxWidth: .infinity).padding(.top, 22)
                prayerRows.padding(.top, 26)
                notes
                zikrRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack).accessibilityLabel("Previous day")
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward).accessibilityLabel("Next day")
            }
        }
        .navigationDestination(isPresented: $showZikr) { ZikrAreaPage(start: .day(date)) }
        .task { load() }
    }

    private func step(_ by: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: by, to: date) else { return }
        triggerSomeVibration(type: .light)
        // At once, rows and all (owner's rule: out, then in — a fade left the two days' words over each other).
        picked = nil
        date = next
        load()
    }

    // MARK: Data

    private var key: String { PrayerNotificationID.dayKey(date) }

    private func load() {
        let all = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: date)))) ?? []
        let mine = all.filter { $0.dayKey == key && JourneyLog.names.contains($0.name) }
        // One per prayer, a completed row winning.
        var kept: [String: PrayerModel] = [:]
        for row in mine where !(kept[row.name]?.isCompleted ?? false) || row.isCompleted { kept[row.name] = row }
        rows = JourneyLog.names.compactMap { kept[$0] }
        // The day's zikr: sessions whose prayer day is this one.
        let from = date.addingTimeInterval(-86_400), to = date.addingTimeInterval(2 * 86_400)
        let near = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= from && $0.startTime < to }))) ?? []
        sessions = near.filter { PrayerDay.start(for: $0.startTime) == date }.sorted { $0.startTime < $1.startTime }
        let spots = rows.compactMap(spot)
        PrayerPlaceNames.fill(spots) { places += 1 }
    }

    private func spot(_ row: PrayerModel) -> CLLocationCoordinate2D? {
        guard let lat = row.latPrayedAt, let lon = row.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// For the ring (DayRing finds its fifths by the five names: a Jumu'ah row is Dhuhr's).
    private var dayPrayers: [DayPrayer] { rows.map(DayPrayer.init) }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 30, weight: .light, design: .rounded))
            Text(subtitle)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var subtitle: String {
        let back = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
        let when = back == 0 ? "Today" : back == 1 ? "Yesterday" : back < 14 ? "\(back) days ago"
            : date.formatted(.dateTime.year())
        // The Hijri date at midday (Memories' search uses Umm al-Qura too).
        var hijri = Date.FormatStyle()
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        return "\(when) · \(date.addingTimeInterval(12 * 3600).formatted(hijri.day().month(.wide)))"
    }

    // MARK: The ring

    private var ring: some View {
        let day = dayPrayers
        let marked = rows.filter(\.isCompleted).count
        return ZStack {
            NeuRaised(shape: Circle(), radius: 9, offset: 4.5).frame(width: 222, height: 222)
            DayRing(day: day, picked: picked) { i in
                triggerSomeVibration(type: .light)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == i ? nil : i }
                pickToken += 1
                let mine = pickToken
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    if pickToken == mine { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } }
                }
            }
            if marked == 0 && picked == nil {
                Text(rows.isEmpty ? "No prayers\nthat day" : "Nothing marked")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                DayCentre(day: day, score: PrayerScoring.dayScore(for: rows), picked: picked, yesterday: false)
                    .allowsHitTesting(picked != nil)
            }
        }
        .frame(width: 222, height: 222)
    }

    // MARK: The prayers

    private var prayerRows: some View {
        let _ = places
        let ranges = Excused.ranges
        return VStack(spacing: 0) {
            ForEach(rows, id: \.id) { row in
                JourneyPrayerRow(row: row, excused: !row.isCompleted && Excused.covers(start: row.startTime, end: row.endTime, in: ranges),
                                 place: place(row))
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
            if rows.isEmpty {
                Text("shukr wasn't opened that day, so there are no prayer times to show.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }

    private func place(_ row: PrayerModel) -> String? {
        if let m = row.mosqueName, !m.isEmpty { return m }
        return spot(row).flatMap(PrayerPlaceNames.name)
    }

    // MARK: Notes

    @ViewBuilder private var notes: some View {
        let written = rows.compactMap { row -> (String, String)? in
            guard row.isCompleted, let text = PrayerPhotos.note(PrayerPhotos.key(dayKey: row.dayKey, name: row.name)) else { return nil }
            return (row.displayName, text)
        }
        if !written.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(written.count == 1 ? "NOTE" : "NOTES")
                    .font(.system(size: 12, design: .rounded)).tracking(0.8).foregroundStyle(.secondary)
                ForEach(written, id: \.0) { name, text in
                    Text(written.count == 1 ? text : "\(name) · \(text)")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .lineSpacing(3)
                }
            }
            .padding(.top, 22)
        }
    }

    // MARK: Zikr

    @ViewBuilder private var zikrRow: some View {
        if !sessions.isEmpty {
            let seconds = sessions.reduce(0) { $0 + $1.secondsPassed }
            let names = Array(NSOrderedSet(array: sessions.map { $0.mantra?.name ?? "Freestyle" })) as? [String] ?? []
            Button {
                triggerSomeVibration(type: .light)
                showZikr = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "circle.hexagonpath").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zikr · \(ZikrMinutes.text(seconds))").font(.system(size: 16, weight: .light, design: .rounded))
                        Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(names.prefix(3).joined(separator: ", "))")
                            .font(.system(size: 13, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }
}

enum ZikrMinutes {
    /// "14 min", "1 hr 5 min", "under a minute".
    static func text(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min"
    }
}

/// One prayer on a day's page: its dot in its grade colour, the name, when · where (or its window, unmarked), the photo,
/// the grade.
private struct JourneyPrayerRow: View {
    let row: PrayerModel
    let excused: Bool
    let place: String?

    var body: some View {
        let score = row.isCompleted ? row.numberScore : nil
        HStack(spacing: 12) {
            Group {
                if let score {
                    Circle().fill(PrayerScoring.color(for: score))
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                }
            }
            .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(row.isCompleted ? .primary : .secondary)
                Text(line)
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if row.isCompleted, PrayerPhotos.has(photoKey) {
                PrayerPhotoCard(key: photoKey, width: 40)
            }
            if let score {
                Text(row.isJumuah ? "100" : PrayerScoring.grade(for: score) == .perfect ? "Perfect" : PrayerScoring.summary(for: score))
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var photoKey: String { PrayerPhotos.key(dayKey: row.dayKey, name: row.name) }

    private var line: String {
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        if let at = row.timeAtComplete, row.isCompleted {
            return [time(at), place].compactMap { $0 }.joined(separator: " · ")
        }
        if excused { return "Excused" }
        if row.endTime > Date() { return "Until \(time(row.endTime))" }
        return "Not marked · its window was \(time(row.startTime)) – \(time(row.endTime))"
    }
}
