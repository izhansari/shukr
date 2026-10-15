import SwiftUI
import SwiftData

// Your Data → a row of "On this iPhone" (owner, 2026-10-14: "click into any of the sections … so that I can see more
// details about that item or category"): what shukr keeps of that kind, in the same grouped-list look. Read-only: these
// pages show, they never change anything. Worked out once when the page opens.

enum DataKind: Hashable {
    case prayers, zikr, azkar, photos, donations, excused, settings

    var title: String {
        switch self {
        case .prayers: "Prayers"
        case .zikr: "Zikr sessions"
        case .azkar: "Azkar and daily goals"
        case .photos: "Prayer photos"
        case .donations: "Donations"
        case .excused: "Excused Mode"
        case .settings: "Your settings"
        }
    }
}

struct DataDetailPage: View {
    let kind: DataKind
    let sizes: YourDataPage.Sizes
    @Environment(\.modelContext) private var context
    @State private var sections: [DetailSection] = []

    struct DetailSection: Identifiable {
        let id = UUID()
        var header: String? = nil
        var rows: [DetailRow]
        var footer: String? = nil
    }
    struct DetailRow: Identifiable {
        let id = UUID()
        let title: String
        var value: String = ""
        var line: String? = nil
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                if let line = row.line {
                                    Text(line).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                            Spacer(minLength: 12)
                            Text(row.value).foregroundStyle(Color(.secondaryLabel)).monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    if let header = section.header { Text(header) }
                } footer: {
                    if let footer = section.footer { Text(footer) }
                }
            }
        }
        .reminderPageTitle(kind.title)
        .task { sections = DataDetails.sections(kind, context, sizes) }
    }
}

/// Each page's sections, from the store and the files. Main actor: SwiftData's objects.
@MainActor enum DataDetails {
    typealias Section = DataDetailPage.DetailSection
    typealias Row = DataDetailPage.DetailRow

    static func sections(_ kind: DataKind, _ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        switch kind {
        case .prayers: prayers(context, sizes)
        case .zikr: zikr(context, sizes)
        case .azkar: azkar(context)
        case .photos: photos(sizes)
        case .donations: donations()
        case .excused: excused()
        case .settings: settings()
        }
    }

    private static let five = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private static func n(_ v: Int) -> String { v.formatted() }
    private static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().year()) }
    private static func about(_ bytes: Int64) -> String { "about " + YourDataPage.size(bytes) }

    // MARK: Prayers

    private static func prayers(_ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        let now = Date()
        let marked = rows.filter(\.isCompleted)
        let missed = rows.filter { !$0.isCompleted && $0.endTime < now }
        let days = (try? context.fetchCount(FetchDescriptor<DailyPrayerScore>())) ?? 0
        var summary = [Row(title: "Prayer records", value: n(rows.count), line: "One for each prayer of each day, prayed or not"),
                       Row(title: "Marked", value: n(marked.count)),
                       Row(title: "Not marked", value: n(missed.count)),
                       Row(title: "Days with a score", value: n(days))]
        if let first = rows.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.prayers))) }

        let byPrayer = five.map { name -> Row in
            let all = rows.filter { $0.name == name }
            let done = all.filter(\.isCompleted)
            let scores = done.compactMap(\.numberScore)
            // Scores are stored 0…1; shown out of 100, as everywhere in shukr.
            let avg = scores.isEmpty ? nil : Int((scores.reduce(0, +) / Double(scores.count) * 100).rounded())
            return Row(title: name, value: "\(n(done.count)) of \(n(all.count))", line: avg.map { "Average score \($0)" })
        }

        var grades: [String: Int] = [:]
        for p in marked { grades[p.isJumuah ? "Jumu'ah" : (p.gradeWord ?? "Marked"), default: 0] += 1 }
        let order = ["Perfect", "On time", "Late", "Qaza", "Jumu'ah", "Marked"]
        let byGrade = order.compactMap { g in grades[g].map { Row(title: g, value: n($0)) } }
            + grades.keys.filter { !order.contains($0) }.sorted().map { Row(title: $0, value: n(grades[$0] ?? 0)) }

        let atMasjid = marked.filter(\.atMasjid).count
        let withPlace = marked.filter { $0.latPrayedAt != nil }.count
        let masajid = Set(marked.compactMap { $0.mosqueName }.filter { !$0.isEmpty }).count
        return [
            Section(rows: summary),
            Section(header: "By prayer", rows: byPrayer, footer: "Marked of all recorded, and the average score of the marked ones."),
            Section(header: "By grade", rows: byGrade.isEmpty ? [Row(title: "None marked yet")] : byGrade),
            Section(header: "Where", rows: [Row(title: "With the place you prayed", value: n(withPlace)),
                                            Row(title: "At a masjid", value: n(atMasjid)),
                                            Row(title: "Different masajid", value: n(masajid))],
                    footer: "A place is kept only when location was on as you marked the prayer. It stays on this iPhone."),
        ]
    }

    // MARK: Zikr

    private static func zikr(_ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        let seconds = sessions.reduce(0) { $0 + $1.secondsPassed }
        let counted = sessions.reduce(0) { $0 + $1.totalCount }
        var summary = [Row(title: "Sessions", value: n(sessions.count)),
                       Row(title: "Counted", value: n(counted)),
                       Row(title: "Time", value: time(seconds))]
        let withGoal = sessions.filter { $0.task != nil }.count
        summary.append(Row(title: "For a daily goal", value: n(withGoal)))
        let asleep = sessions.filter(\.endedAsleep).count
        if asleep > 0 { summary.append(Row(title: "Ended by sleep mode", value: n(asleep))) }
        if let first = sessions.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.zikr), line: "With your azkar's photos and voice memos")) }

        var by: [String: (sessions: Int, count: Int, seconds: Double)] = [:]
        for s in sessions {
            // A session with no zikr is a freestyle one (saved as "Untitled").
            let name = s.mantra?.name ?? (s.title.isEmpty || s.title == "Untitled" ? "Freestyle" : s.title)
            var e = by[name] ?? (0, 0, 0)
            e.sessions += 1; e.count += s.totalCount; e.seconds += s.secondsPassed
            by[name] = e
        }
        let top = by.sorted { $0.value.sessions > $1.value.sessions }.prefix(12).map { name, e in
            Row(title: name, value: n(e.sessions), line: "\(n(e.count)) counted · \(time(e.seconds))")
        }
        return [Section(rows: summary),
                Section(header: "Most said", rows: top.isEmpty ? [Row(title: "No sessions yet")] : Array(top),
                        footer: "Sessions for each zikr. Each one keeps when it was, how long, how many and the goal it ran with.")]
    }

    private static func time(_ s: Double) -> String {
        if s < 60 { return "\(Int(s)) s" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min" }
        let h = s / 3600
        return h < 10 ? String(format: "%.1f hr", h) : "\(Int(h.rounded()).formatted()) hr"
    }

    // MARK: Azkar and goals

    private static func azkar(_ context: ModelContext) -> [Section] {
        let all = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        func media(_ z: MantraModel) -> String? {
            let parts = [z.imageData != nil ? "photo" : nil, z.audioData != nil ? "voice memo" : nil,
                         z.notes.isEmpty ? nil : "notes"].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let yours = all.filter { !$0.isBuiltIn }.map { Row(title: $0.name, value: n($0.totalCount), line: media($0)) }
        let builtIns = all.filter(\.isBuiltIn)
        let builtInRows = builtIns.filter { $0.totalCount > 0 || media($0) != nil }
            .map { Row(title: $0.name, value: n($0.totalCount), line: media($0)) }
        let goals = ((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { t in
            let each = t.isCountMode ? "\(n(t.goal)) a day" : "\(t.goal) min a day"
            let line = [t.title != t.displayName ? t.displayName : nil, t.reminderKind != nil ? "reminder on" : nil,
                        t.pausedAt != nil ? "paused" : nil].compactMap { $0 }.joined(separator: " · ")
            return Row(title: t.title, value: each, line: line.isEmpty ? nil : line)
        }
        return [Section(header: "Your azkar", rows: yours.isEmpty ? [Row(title: "None of your own yet")] : yours,
                        footer: "Counted in all, and what each one keeps."),
                Section(header: "Built in", rows: [Row(title: "Built-in azkar", value: n(builtIns.count))] + builtInRows,
                        footer: "The ones you've said, and anything you added to them."),
                Section(header: "Daily goals", rows: goals.isEmpty ? [Row(title: "No daily goals yet")] : goals)]
    }

    // MARK: Photos

    private static func photos(_ sizes: YourDataPage.Sizes) -> [Section] {
        let files = PrayerPhotos.files()
        let backs = files.filter { $0.contains("-back.") }
        let notes = files.filter { $0.hasSuffix("-note.txt") }.count
        let fronts = files.filter { $0.contains("-front.") }.count
        // "<YYYY-MM-DD>-<prayer>-back.heic": the month from the name.
        var months: [String: Int] = [:]
        for f in backs { months[String(f.prefix(7)), default: 0] += 1 }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy-MM"
        let byMonth = months.keys.sorted(by: >).map { key in
            Row(title: parse.date(from: key)?.formatted(.dateTime.month(.wide).year()) ?? key, value: n(months[key] ?? 0))
        }
        var summary = [Row(title: "Photos", value: n(backs.count)),
                       Row(title: "With the front camera too", value: n(fronts)),
                       Row(title: "With a note", value: n(notes))]
        if sizes.known { summary.append(Row(title: "Space", value: YourDataPage.size(sizes.photos))) }
        return [Section(rows: summary,
                        footer: "Kept inside shukr, not in your Photos library, and never synced. Unmarking a prayer deletes its photo."),
                Section(header: "By month", rows: byMonth.isEmpty ? [Row(title: "No photos yet")] : byMonth)]
    }

    // MARK: Donations and Excused Mode

    private static func donations() -> [Section] {
        let list = SadaqahLog.shared.donations
        var byCurrency: [String: Double] = [:]
        for d in list { byCurrency[d.currency, default: 0] += d.amount }
        let totals = byCurrency.keys.sorted().map { c in
            Row(title: "Given in \(c)", value: (byCurrency[c] ?? 0).formatted(.currency(code: c)))
        }
        var byTo: [String: Int] = [:]
        for d in list { byTo[d.to, default: 0] += 1 }
        let to = byTo.sorted { $0.value > $1.value }.prefix(10).map { Row(title: $0.key, value: n($0.value)) }
        var summary = [Row(title: "Donations logged", value: n(list.count))]
        if let first = list.map(\.date).min() { summary.append(Row(title: "Since", value: day(first))) }
        return [Section(rows: summary + totals, footer: "Only what you logged in Give to Causes. shukr never sees a payment."),
                Section(header: "Where it went", rows: to.isEmpty ? [Row(title: "None yet")] : Array(to))]
    }

    private static func excused() -> [Section] {
        let ranges = Excused.ranges.sorted { $0.start > $1.start }
        let rows = ranges.map { r -> Row in
            let end = r.end.map(day) ?? "still on"
            let days = Calendar.current.dateComponents([.day], from: r.start, to: r.end ?? .now).day ?? 0
            return Row(title: "\(day(r.start)) – \(end)", value: "\(days + 1) day\(days == 0 ? "" : "s")")
        }
        return [Section(rows: rows.isEmpty ? [Row(title: "None")] : rows,
                        footer: "When Excused Mode was on. Those days are left out of your streaks and scores.")]
    }

    // MARK: Settings

    private static func settings() -> [Section] {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        let d = UserDefaults.standard
        let methods = [1: "University of Islamic Sciences, Karachi", 2: "Islamic Society of North America", 3: "Muslim World League",
                       4: "Umm Al-Qura University, Makkah", 5: "Egyptian General Authority of Survey",
                       7: "Institute of Geophysics, University of Tehran", 8: "Gulf Region", 9: "Kuwait", 10: "Qatar",
                       11: "Majlis Ugama Islam Singapura, Singapore", 12: "Union Organization islamic de France",
                       13: "Diyanet İşleri Başkanlığı, Turkey", 14: "Spiritual Administration of Muslims of Russia"]
        let saved = group?.object(forKey: "calculationMethod") == nil ? 2 : (group?.integer(forKey: "calculationMethod") ?? 2)
        let method = saved == 0 ? "Automatic · " + (methods[AutoMethod.effectiveMethod()] ?? "") : (methods[saved] ?? "Method \(saved)")
        let city = group?.string(forKey: "lastCityName").flatMap { $0 == "Wonderland" || $0.isEmpty ? nil : $0 } ?? "Not set"
        let looks = [3: "System", 0: "Light", 1: "Dark", 2: "Sun"]
        let prayerTimes = [Row(title: "Location", value: city),
                           Row(title: "Calculation method", value: method),
                           Row(title: "Asr", value: group?.integer(forKey: "school") == 1 ? "Hanafi" : "Shafi'i")]
        let notifications = five.map { p -> Row in
            let k = p.lowercased()
            let on = d.object(forKey: "\(k)Notif") == nil ? NotificationDefaults.notify(p) : d.bool(forKey: "\(k)Notif")
            let nudges = d.object(forKey: "\(k)Nudges") == nil ? NotificationDefaults.nudges(p) : d.bool(forKey: "\(k)Nudges")
            return Row(title: p, value: !on ? "Off" : nudges ? "Nudge" : "At the start")
        }
        let live = five.map { Row(title: $0, value: LiveActivityPrefs.isOn($0) ? "On" : "Off") }
        var alarm = [Row(title: "Fajr alarm", value: group?.bool(forKey: "alarmEnabled") == true ? "On" : "Off")]
        if group?.bool(forKey: "alarmEnabled") == true {
            let mins = group?.integer(forKey: "alarmOffsetMinutes") ?? 0
            let before = group?.object(forKey: "alarmIsBefore") == nil || group?.bool(forKey: "alarmIsBefore") == true
            let fajr = group?.object(forKey: "alarmIsFajr") == nil || group?.bool(forKey: "alarmIsFajr") == true
            alarm.append(Row(title: "Rings", value: mins == 0 ? (fajr ? "As Fajr starts" : "As Fajr ends")
                             : "\(mins) min \(before ? "before" : "after") Fajr \(fajr ? "starts" : "ends")"))
        }
        let look = Row(title: "Look", value: looks[d.integer(forKey: "modeToggleNew")] ?? "System")
        return [Section(header: "Prayer times", rows: prayerTimes),
                Section(header: "Notifications", rows: notifications),
                Section(header: "Live Activities", rows: live),
                Section(header: "Fajr alarm", rows: alarm),
                Section(header: "Appearance", rows: [look],
                        footer: "Your settings stay on this iPhone and come back with an iPhone backup. Export my data copies your data, not these settings.")]
    }
}
