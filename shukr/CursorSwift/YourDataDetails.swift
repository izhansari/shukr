import SwiftUI
import SwiftData

// Your Data → a row of "On this iPhone" (owner, 2026-10-14: "click into any of the sections … so that I can see more
// details"; then: "people who are actually using this feature … are really power users, very particular about wanting
// their data and being in control of it"): everything shukr keeps of that kind, in the same grouped-list look, and that
// part alone as a spreadsheet. Prayer photos get their own page: the photos themselves, by month, to save or share all
// or a few. Nothing here changes or deletes anything. Worked out once when the page opens.

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

    /// The copy's spreadsheets for this kind (`DataExport.sheets`); settings make their own.
    var sheets: [String] {
        switch self {
        case .prayers: ["prayers.csv"]
        case .zikr: ["zikr-sessions.csv"]
        case .azkar: ["azkar.csv", "daily-goals.csv"]
        case .donations: ["donations.csv"]
        case .excused: ["excused-mode.csv"]
        case .settings: ["settings.csv"]
        case .photos: []
        }
    }
}

struct DataDetailPage: View {
    let kind: DataKind
    let sizes: YourDataPage.Sizes
    @Environment(\.modelContext) private var context
    @State private var sections: [DetailSection] = []
    @State private var sharing: [URL]?

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
        if kind == .photos {
            PhotoDataPage(sizes: sizes)
        } else {
            list
        }
    }

    private var list: some View {
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
            if !sections.isEmpty {
                Section {
                    Button(action: exportThis) {
                        Label(kind.sheets.count == 1 ? "Export as a spreadsheet" : "Export as spreadsheets",
                              systemImage: "tablecells").foregroundStyle(Color.sage)
                    }
                } footer: {
                    Text("Just this part, as a .csv you can open in Numbers, Excel or Google Sheets. Export my data has everything.")
                }
            }
        }
        .reminderPageTitle(kind.title)
        .task { sections = DataDetails.sections(kind, context, sizes) }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                FeedbackShareSheet(items: sharing) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    private func exportThis() {
        var sheets = DataExport.sheets(context)
        if kind == .settings { sheets["settings.csv"] = DataDetails.csv(sections) }
        let urls = kind.sheets.compactMap { name in sheets[name].flatMap { DataExport.oneFile(name, $0) } }
        if !urls.isEmpty { sharing = urls }
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
        case .photos: []
        case .donations: donations()
        case .excused: excused()
        case .settings: settings()
        }
    }

    /// A page's rows as a spreadsheet (Your settings: Section, Setting, Value).
    static func csv(_ sections: [Section]) -> String {
        func cell(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        let rows = sections.flatMap { s in s.rows.map { [s.header ?? "", $0.title, $0.value].map(cell).joined(separator: ",") } }
        return (["Section,Setting,Value"] + rows).joined(separator: "\n")
    }

    private static let five = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private static func n(_ v: Int) -> String { v.formatted() }
    private static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().year()) }
    private static func about(_ bytes: Int64) -> String { "about " + YourDataPage.size(bytes) }
    private static func pct(_ part: Int, _ whole: Int) -> String { whole == 0 ? "–" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%" }
    /// Scores are stored 0…1; shown out of 100, as everywhere in shukr.
    private static func average(_ rows: [PrayerModel]) -> Int? {
        let s = rows.compactMap(\.numberScore)
        return s.isEmpty ? nil : Int((s.reduce(0, +) / Double(s.count) * 100).rounded())
    }

    // MARK: Prayers

    private static func prayers(_ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        let now = Date()
        let past = rows.filter { $0.endTime < now || $0.isCompleted }
        let marked = rows.filter(\.isCompleted)
        let days = (try? context.fetchCount(FetchDescriptor<DailyPrayerScore>())) ?? 0
        var summary = [Row(title: "Prayer records", value: n(rows.count), line: "One for each prayer of each day, prayed or not"),
                       Row(title: "Marked", value: n(marked.count), line: past.isEmpty ? nil : "\(pct(marked.count, past.count)) of the prayers whose time has passed"),
                       Row(title: "Not marked", value: n(past.count - marked.count)),
                       Row(title: "Average score", value: average(marked).map(String.init) ?? "–", line: "Of the marked prayers"),
                       Row(title: "Days with a score", value: n(days))]
        if let first = rows.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.prayers))) }

        // The last 30 prayer days.
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: PrayerDay.start(for: now)) ?? now
        let recent = past.filter { $0.dayStart >= monthAgo }
        let recentMarked = recent.filter(\.isCompleted)
        let last30 = [Row(title: "Marked", value: "\(n(recentMarked.count)) of \(n(recent.count))"),
                      Row(title: "Average score", value: average(recentMarked).map(String.init) ?? "–"),
                      Row(title: "At a masjid", value: n(recentMarked.filter(\.atMasjid).count))]

        let d = UserDefaults.standard
        let bestOn = d.double(forKey: "dateOfMaxPrayerStreak")
        let streaks = [Row(title: "Day streak", value: n(d.integer(forKey: "prayerStreak")), line: "Days in a row with all five marked"),
                       Row(title: "Best day streak", value: n(d.integer(forKey: "maxPrayerStreak")),
                           line: bestOn > 0 ? "Reached " + day(Date(timeIntervalSince1970: bestOn)) : nil),
                       Row(title: "In-time streak", value: n(d.integer(forKey: "onTimeStreak")), line: "Days in a row with no Qaza"),
                       Row(title: "Best in-time streak", value: n(d.integer(forKey: "maxOnTimeStreak")))]

        func gradeOf(_ p: PrayerModel) -> String { p.isJumuah ? "Jumu'ah" : (p.gradeWord ?? "Marked") }
        let byPrayer = five.map { name -> Row in
            let all = past.filter { $0.name == name }
            let done = all.filter(\.isCompleted)
            var g: [String: Int] = [:]
            for p in done { g[gradeOf(p), default: 0] += 1 }
            let line = [average(done).map { "Average \($0)" }, g["Perfect"].map { "Perfect \($0)" }, g["Qaza"].map { "Qaza \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
            return Row(title: name, value: "\(n(done.count)) of \(n(all.count))", line: line.isEmpty ? nil : line)
        }

        var grades: [String: Int] = [:]
        for p in marked { grades[gradeOf(p), default: 0] += 1 }
        let order = ["Perfect", "On time", "Late", "Qaza", "Jumu'ah", "Marked"]
        let byGrade = order.compactMap { g in grades[g].map { Row(title: g, value: n($0), line: pct($0, marked.count) + " of marked") } }
            + grades.keys.filter { !order.contains($0) }.sorted().map { Row(title: $0, value: n(grades[$0] ?? 0)) }

        // By year, newest first.
        var years: [Int: [PrayerModel]] = [:]
        for p in past { years[Calendar.current.component(.year, from: p.dayStart), default: []].append(p) }
        let byYear = years.keys.sorted(by: >).map { y -> Row in
            let all = years[y] ?? [], done = all.filter(\.isCompleted)
            return Row(title: String(y), value: "\(n(done.count)) of \(n(all.count))", line: average(done).map { "Average \($0)" })
        }

        let atMasjid = marked.filter(\.atMasjid)
        let withPlace = marked.filter { $0.latPrayedAt != nil }.count
        var masajid: [String: Int] = [:]
        for p in atMasjid { if let m = p.mosqueName, !m.isEmpty { masajid[m, default: 0] += 1 } }
        var whereRows = [Row(title: "With the place you prayed", value: n(withPlace)),
                         Row(title: "At a masjid", value: n(atMasjid.count))]
        whereRows += masajid.sorted { $0.value > $1.value }.prefix(8).map { Row(title: $0.key, value: n($0.value)) }

        let edited = marked.filter(\.timeEdited).count
        let spotEdited = marked.filter(\.spotEdited).count
        return [
            Section(rows: summary),
            Section(header: "Last 30 days", rows: last30),
            Section(header: "Streaks", rows: streaks),
            Section(header: "By prayer", rows: byPrayer, footer: "Marked of those whose time has passed."),
            Section(header: "By grade", rows: byGrade.isEmpty ? [Row(title: "None marked yet")] : byGrade),
            Section(header: "By year", rows: byYear.isEmpty ? [Row(title: "None yet")] : byYear),
            Section(header: "Where", rows: whereRows,
                    footer: "A place is kept only when location was on as you marked the prayer. It stays on this iPhone."),
            Section(header: "Changed after marking", rows: [Row(title: "Time changed", value: n(edited)),
                                                            Row(title: "Place changed", value: n(spotEdited))],
                    footer: "Holding a prayer lets you change when or where it was prayed. The first record is kept too."),
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
        if counted > 0 { summary.append(Row(title: "Average pace", value: String(format: "%.1f s", seconds / Double(counted)), line: "Per count")) }
        if let first = sessions.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.zikr), line: "With your azkar's photos and voice memos")) }

        var records: [Row] = []
        if let longest = sessions.max(by: { $0.secondsPassed < $1.secondsPassed }) {
            records.append(Row(title: "Longest session", value: time(longest.secondsPassed), line: "\(name(longest)) · \(day(longest.startTime))"))
        }
        if let most = sessions.max(by: { $0.totalCount < $1.totalCount }) {
            records.append(Row(title: "Most in one session", value: n(most.totalCount), line: "\(name(most)) · \(day(most.startTime))"))
        }
        var perDay: [Date: Int] = [:]
        for s in sessions { perDay[PrayerDay.start(for: s.startTime), default: 0] += s.totalCount }
        if let busiest = perDay.max(by: { $0.value < $1.value }) {
            records.append(Row(title: "Most in one day", value: n(busiest.value), line: day(busiest.key)))
        }
        records.append(Row(title: "Days with zikr", value: n(perDay.count)))

        let kinds = [Row(title: "To a count", value: n(sessions.filter { $0.sessionMode == 2 }.count)),
                     Row(title: "For a time", value: n(sessions.filter { $0.sessionMode == 1 }.count)),
                     Row(title: "Freestyle", value: n(sessions.filter { $0.sessionMode != 1 && $0.sessionMode != 2 }.count)),
                     Row(title: "For a daily goal", value: n(sessions.filter { $0.task != nil }.count)),
                     Row(title: "Ended by sleep mode", value: n(sessions.filter(\.endedAsleep).count))]

        var by: [String: (sessions: Int, count: Int, seconds: Double)] = [:]
        for s in sessions {
            var e = by[name(s)] ?? (0, 0, 0)
            e.sessions += 1; e.count += s.totalCount; e.seconds += s.secondsPassed
            by[name(s)] = e
        }
        let top = by.sorted { $0.value.sessions > $1.value.sessions }.map { name, e in
            Row(title: name, value: n(e.sessions), line: "\(n(e.count)) counted · \(time(e.seconds))")
        }

        var years: [Int: (sessions: Int, count: Int, seconds: Double)] = [:]
        for s in sessions {
            let y = Calendar.current.component(.year, from: s.startTime)
            var e = years[y] ?? (0, 0, 0)
            e.sessions += 1; e.count += s.totalCount; e.seconds += s.secondsPassed
            years[y] = e
        }
        let byYear = years.sorted { $0.key > $1.key }.map { y, e in
            Row(title: String(y), value: n(e.sessions), line: "\(n(e.count)) counted · \(time(e.seconds))")
        }
        return [Section(rows: summary),
                Section(header: "Records", rows: records),
                Section(header: "Kinds of session", rows: kinds),
                Section(header: "By zikr", rows: top.isEmpty ? [Row(title: "No sessions yet")] : top,
                        footer: "Sessions of each. Each one keeps when it was, how long, how many and the goal it ran with."),
                Section(header: "By year", rows: byYear.isEmpty ? [Row(title: "None yet")] : byYear)]
    }

    /// A session's zikr; one with none is freestyle (saved as "Untitled").
    private static func name(_ s: SessionDataModel) -> String {
        s.mantra?.name ?? (s.title.isEmpty || s.title == "Untitled" ? "Freestyle" : s.title)
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
        func line(_ z: MantraModel) -> String {
            ["\(n(z.sessions.count)) session\(z.sessions.count == 1 ? "" : "s")",
             z.imageData != nil ? "photo" : nil, z.audioData != nil ? "voice memo" : nil,
             z.notes.isEmpty ? nil : "notes", z.fullText.isEmpty ? nil : "full text"].compactMap { $0 }.joined(separator: " · ")
        }
        let yours = all.filter { !$0.isBuiltIn }.map { Row(title: $0.name, value: n($0.totalCount), line: line($0) + " · added \(day($0.createdAt))") }
        let builtIns = all.filter(\.isBuiltIn)
        let builtInRows = builtIns.filter { $0.totalCount > 0 || $0.imageData != nil || $0.audioData != nil }
            .map { Row(title: $0.name, value: n($0.totalCount), line: line($0)) }
        let tasks = ((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let goals = tasks.map { t -> Row in
            let each = t.isCountMode ? "\(n(t.goal)) a day" : "\(t.goal) min a day"
            let streak = t.streak()
            let line = [t.title != t.displayName ? t.displayName : nil,
                        streak.best > 0 ? "streak \(streak.current) · best \(streak.best)" : nil,
                        t.reminderKind != nil ? "reminder on" : nil,
                        t.pausedAt != nil ? "paused" : nil].compactMap { $0 }.joined(separator: " · ")
            return Row(title: t.title, value: each, line: line.isEmpty ? nil : line)
        }
        return [Section(header: "Your azkar", rows: yours.isEmpty ? [Row(title: "None of your own yet")] : yours,
                        footer: "Counted in all, and what each one keeps."),
                Section(header: "Built in", rows: [Row(title: "Built-in azkar", value: n(builtIns.count))] + builtInRows,
                        footer: "The ones you've said, and anything you added to them."),
                Section(header: "Daily goals", rows: goals.isEmpty ? [Row(title: "No daily goals yet")] : goals,
                        footer: "In the wheel's order.")]
    }

    // MARK: Donations and Excused Mode

    private static func donations() -> [Section] {
        let list = SadaqahLog.shared.donations
        var byCurrency: [String: Double] = [:]
        for d in list { byCurrency[d.currency, default: 0] += d.amount }
        let totals = byCurrency.keys.sorted().map { c in
            Row(title: "Given in \(c)", value: (byCurrency[c] ?? 0).formatted(.currency(code: c)))
        }
        var byTo: [String: (count: Int, amount: Double, currency: String)] = [:]
        for d in list {
            var e = byTo[d.to] ?? (0, 0, d.currency)
            e.count += 1; e.amount += d.amount
            byTo[d.to] = e
        }
        let to = byTo.sorted { $0.value.count > $1.value.count }.map {
            Row(title: $0.key, value: $0.value.amount.formatted(.currency(code: $0.value.currency)), line: "\(n($0.value.count)) logged")
        }
        var byKind: [String: Int] = [:]
        for d in list { byKind[d.purpose == .unspecified ? "Not set" : d.purpose.title, default: 0] += 1 }
        let kinds = byKind.sorted { $0.value > $1.value }.map { Row(title: $0.key, value: n($0.value)) }
        var summary = [Row(title: "Donations logged", value: n(list.count))]
        if let first = list.map(\.date).min() { summary.append(Row(title: "Since", value: day(first))) }
        return [Section(rows: summary + totals, footer: "Only what you logged in Give to Causes. shukr never sees a payment."),
                Section(header: "Where it went", rows: to.isEmpty ? [Row(title: "None yet")] : to),
                Section(header: "What for", rows: kinds.isEmpty ? [Row(title: "None yet")] : kinds)]
    }

    private static func excused() -> [Section] {
        let ranges = Excused.ranges.sorted { $0.start > $1.start }
        let rows = ranges.map { r -> Row in
            let end = r.end.map(day) ?? "still on"
            let days = Calendar.current.dateComponents([.day], from: r.start, to: r.end ?? .now).day ?? 0
            return Row(title: "\(day(r.start)) – \(end)", value: "\(days + 1) day\(days == 0 ? "" : "s")",
                       line: r.pauseZikr ? "Zikr reminders paused" : nil)
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
            + [Row(title: "Card look", value: LiveActivityLook.current.title)]
        var alarm = [Row(title: "Fajr alarm", value: group?.bool(forKey: "alarmEnabled") == true ? "On" : "Off")]
        if group?.bool(forKey: "alarmEnabled") == true {
            let mins = group?.integer(forKey: "alarmOffsetMinutes") ?? 0
            let before = group?.object(forKey: "alarmIsBefore") == nil || group?.bool(forKey: "alarmIsBefore") == true
            let fajr = group?.object(forKey: "alarmIsFajr") == nil || group?.bool(forKey: "alarmIsFajr") == true
            alarm.append(Row(title: "Rings", value: mins == 0 ? (fajr ? "As Fajr starts" : "As Fajr ends")
                             : "\(mins) min \(before ? "before" : "after") Fajr \(fajr ? "starts" : "ends")"))
        }
        let places = [Row(title: "Your masajid", value: n(MosqueFavorites.all.count), line: "Starred on the map"),
                      Row(title: "Hidden from the map", value: n((d.stringArray(forKey: "hiddenMosques") ?? []).count)),
                      Row(title: "A dua on arriving at a masjid", value: d.bool(forKey: MasjidArrival.enabledKey) ? "On" : "Off")]
        let photos = [Row(title: "Show where on shared photos", value: d.bool(forKey: PrayerPhotos.showPlaceKey) ? "On" : "Off")]
        let look = Row(title: "Look", value: looks[d.integer(forKey: "modeToggleNew")] ?? "System")
        return [Section(header: "Prayer times", rows: prayerTimes),
                Section(header: "Notifications", rows: notifications),
                Section(header: "Live Activities", rows: live),
                Section(header: "Fajr alarm", rows: alarm),
                Section(header: "Masajid", rows: places),
                Section(header: "Memories", rows: photos),
                Section(header: "Appearance", rows: [look],
                        footer: "Your settings stay on this iPhone and come back with an iPhone backup. Export my data copies your data, not these settings.")]
    }
}

// MARK: - Prayer photos

/// The photos themselves, by month (owner: "show the photos too, in case they want to export only the photos"): all of
/// them saved or shared at once, or Select a few. The back photo is the picture; the front ones come too when asked.
private struct PhotoDataPage: View {
    let sizes: YourDataPage.Sizes
    @State private var photos: [MemoryPhoto] = PrayerPhotos.all().reversed()
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var withFront = true
    @State private var sharing: [URL]?

    private var months: [(title: String, photos: [MemoryPhoto])] {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy-MM"
        var order: [String] = [], by: [String: [MemoryPhoto]] = [:]
        for p in photos {
            let m = String(p.dayKey.prefix(7))
            if by[m] == nil { order.append(m) }
            by[m, default: []].append(p)
        }
        return order.map { (parse.date(from: $0)?.formatted(.dateTime.month(.wide).year()) ?? $0, by[$0] ?? []) }
    }

    var body: some View {
        let names = PrayerPhotos.files()
        List {
            Section {
                row("Photos", "\(photos.count)")
                row("With the front camera too", "\(photos.filter { names.contains(PrayerPhotos.url($0.key, front: true).lastPathComponent) }.count)")
                row("With a note", "\(names.filter { $0.hasSuffix("-note.txt") }.count)")
                if sizes.known { row("Space", YourDataPage.size(sizes.photos)) }
            } footer: {
                Text("Kept inside shukr, not in your Photos library, and never synced. Unmarking a prayer deletes its photo.")
            }
            if !photos.isEmpty {
                Section {
                    Toggle("Include the front-camera photos", isOn: $withFront).tint(Color.sage)
                    Button { share(photos) } label: {
                        Label("Save or share all \(photos.count)", systemImage: "square.and.arrow.up").foregroundStyle(Color.sage)
                    }
                } footer: {
                    Text("Save Images puts them in your Photos library. Tap Select to pick a few. Their notes come with Export my data.")
                }
            }
            ForEach(months, id: \.title) { month in
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                        ForEach(month.photos) { photo in
                            PhotoCell(photo: photo, selecting: selecting, picked: picked.contains(photo.key))
                                .onTapGesture {
                                    if !selecting { selecting = true }
                                    if picked.contains(photo.key) { picked.remove(photo.key) } else { picked.insert(photo.key) }
                                }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3))
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text("\(month.photos.count)").monospacedDigit()
                    }
                }
            }
        }
        .reminderPageTitle("Prayer photos")
        .toolbar {
            if !photos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { picked = [] }
                    }
                }
            }
            if selecting {
                ToolbarItem(placement: .bottomBar) {
                    Button(picked.count == photos.count ? "Select None" : "Select All") {
                        picked = picked.count == photos.count ? [] : Set(photos.map(\.key))
                    }
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    Button { share(photos.filter { picked.contains($0.key) }) } label: {
                        Label(picked.isEmpty ? "Share" : "Share \(picked.count)", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                FeedbackShareSheet(items: sharing) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(Color(.secondaryLabel)).monospacedDigit() }
    }

    /// The files themselves (HEIC, older ones JPEG), back first, the front after it when asked.
    private func share(_ list: [MemoryPhoto]) {
        let names = PrayerPhotos.files()
        var urls: [URL] = []
        for p in list {
            urls.append(PrayerPhotos.url(p.key, front: false))
            let front = PrayerPhotos.url(p.key, front: true)
            if withFront, names.contains(front.lastPathComponent) { urls.append(front) }
        }
        if !urls.isEmpty { sharing = urls }
    }
}

/// A square of the grid: the back photo's small copy (Memories' cache), the prayer's name in a corner, a check when
/// picked.
private struct PhotoCell: View {
    let photo: MemoryPhoto
    let selecting: Bool
    let picked: Bool
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(photo.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, picked ? Color.sage : Color.clear)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(4)
                }
            }
            .opacity(selecting && !picked ? 0.75 : 1)
            .contentShape(Rectangle())
            .task {
                image = PrayerPhotos.cachedThumbnail(photo.key)
                if image == nil { image = await PrayerPhotos.thumbnail(photo.key) }
            }
            .accessibilityLabel("\(photo.name), \(photo.dayKey)")
            .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
