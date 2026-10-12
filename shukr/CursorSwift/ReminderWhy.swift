import SwiftUI

/// The three explanations behind Your reminders (owner, reminders-page-g2: "I still like that information that says why
/// only 64, the top itself up and arrives on time" — the last now "Notification settings" … items at the bottom that when clicked, open a sheet"), each a row
/// at the bottom of the page with an orange ! when one of his settings is in the way. Settings → Notifications' status
/// row opens the same sheet when something's wrong.
enum ReminderWhy: Int, Identifiable, CaseIterable {
    case budget, topsUp, onTime

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .budget: "Why only 64?"
        case .topsUp: "Tops itself up"
        // Not "Arrives on time" (owner: "the initial question … would be, why wouldn't they?"): it's his settings
        // doing their job, so it's named after them.
        case .onTime: "Notification settings"
        }
    }
    var symbol: String {
        switch self {
        case .budget: "questionmark.circle"
        case .topsUp: "arrow.triangle.2.circlepath"
        case .onTime: "checkmark.shield"
        }
    }
    /// Notification settings' symbol follows them: a shield with a check when they let reminders through, with a ! when not.
    @MainActor func symbol(_ health: NotificationHealth) -> String {
        self == .onTime && needsHand(health) ? "exclamationmark.shield" : symbol
    }

    /// Whether one of his settings is in the way (the row's orange !).
    @MainActor func needsHand(_ health: NotificationHealth) -> Bool {
        switch self {
        case .budget: false
        case .topsUp: health.backgroundRefresh != .available
        case .onTime: health.authorization == .denied || health.timeSensitive == .disabled || Self.late(health)
        }
    }

    /// The sheet a problem in Settings opens: background refresh has its own; everything else is delivery.
    static func forIssues(_ issues: [NotificationHealth.Issue]) -> ReminderWhy {
        issues.allSatisfy { $0 == .backgroundRefreshOff } && !issues.isEmpty ? .topsUp : .onTime
    }

    /// The Summary on with Time Sensitive off: the one setup that makes them late.
    @MainActor static func late(_ health: NotificationHealth) -> Bool { health.summaryOn && health.timeSensitive != .enabled }

    struct Point {
        let big: String; let small: String; let symbol: String; let warn: Bool
        /// Explaining, not about his settings: drawn in grey, never orange.
        var neutral = false
    }

    struct Content {
        let head: String
        let points: [Point]
        var explainHead: String? = nil
        var explain: [Point] = []
        var fix = false
    }

    @MainActor func content(_ health: NotificationHealth, pendingCount: Int) -> Content {
        switch self {
        case .budget:
            // Plan v2 in his words (owner, 2026-10-12): every slot used, nearest first.
            let n = NotificationScheduler.nudgeDaysAhead
            let spare = NotificationScheduler.spare
            return Content(head: "iOS lets each app keep 64 notifications waiting. shukr fills them, nearest first.", points: [
                Point(big: "A week of starts, always", small: "Each prayer's start for at least the next \(NotificationScheduler.daysAhead) days — longer if you usually open shukr less often.", symbol: "calendar", warn: false),
                Point(big: "Full reminders for the next \(n) days", small: "Halfway and 30 minutes left too, and for more days when there's room. After that, just the starts, so we never pile on (a filled dot under the day; an empty ring means starts only for now).", symbol: "bell.badge", warn: false),
                Point(big: "Zikr reminders for today and tomorrow", small: "Later days are added as they come closer, so they never crowd out your prayers.", symbol: "circle.hexagonpath", warn: false),
                Point(big: "\(spare) kept for snoozes", small: "Room for \u{201C}Nudge me in 5 minutes\u{201D} and similar. The rest go further ahead.", symbol: "circle.dashed", warn: false),
            ])
        case .topsUp:
            let lastRun = UserDefaults.standard.double(forKey: NotificationHealth.lastRefreshKey)
            let ran = lastRun == 0 ? "" : " Last ran " + Self.whenText(Date(timeIntervalSince1970: lastRun)) + "."
            let bgOn = health.backgroundRefresh == .available
            let keep = health.keepAliveDate.map { " (\($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))" } ?? ""
            return Content(head: "Your week keeps topping itself up.", points: [
                bgOn ? Point(big: "Background App Refresh is on", small: "iOS wakes shukr now and then to add the next days." + ran, symbol: "arrow.triangle.2.circlepath", warn: false)
                     : Point(big: "Background App Refresh is off", small: "Turn it on in Settings, or open shukr every few days.", symbol: "arrow.triangle.2.circlepath", warn: true),
                Point(big: "Opening shukr tops it up too", small: "Any time you open the app, the week refills.", symbol: "iphone", warn: false),
                Point(big: "Never a silent stop", small: "If iOS can't refresh, shukr tells you first: when it eases off to just the starts, two days before your reminders run out, and at the last one\(keep).", symbol: "bell.badge", warn: false),
            ], fix: !bgOn)
        case .onTime:
            // His settings first (orange only where one is really in the way), then how iOS delivers, neutrally.
            let off = health.authorization == .denied
            let ts = health.timeSensitive == .enabled
            let tsOff = health.timeSensitive == .disabled
            let late = Self.late(health)
            var mine: [Point] = []
            mine.append(off
                ? Point(big: "Notifications: off", small: "shukr can't remind you at all until you turn them on.", symbol: "bell.slash", warn: true)
                : Point(big: "Notifications: on", small: "shukr can remind you.", symbol: "bell", warn: false))
            if !off {
                mine.append(ts
                    ? Point(big: "Time Sensitive: on", small: "Reminders come through Focus and the Scheduled Summary.", symbol: "clock", warn: false)
                    : Point(big: "Time Sensitive: \(tsOff ? "off" : "not available")", small: "A Focus can hold reminders back.", symbol: "clock", warn: tsOff))
                mine.append(health.summaryOn
                    ? Point(big: "Scheduled Summary: on", small: ts ? "Reminders still come right away (Time Sensitive lets them through)."
                                                                   : "Reminders wait for the next summary, so they can arrive late.",
                            symbol: "tray.full", warn: !ts)
                    : Point(big: "Scheduled Summary: off", small: "Reminders come right away.", symbol: "checkmark.circle", warn: false))
            }
            let explain = [
                Point(big: "Time Sensitive", small: "Lets a reminder through Focus and the Scheduled Summary. shukr marks prayer reminders Time Sensitive.", symbol: "clock", warn: false, neutral: true),
                Point(big: "Scheduled Summary", small: "Collects notifications and delivers them at the times you choose, instead of right away.", symbol: "tray.full", warn: false, neutral: true),
                Point(big: "Focus", small: "Silences notifications, except apps you allow and Time Sensitive ones.", symbol: "moon", warn: false, neutral: true),
                Point(big: "Together", small: "With the Summary on and Time Sensitive off, reminders wait for the next summary — the one setup that makes them late.", symbol: "info.circle", warn: false, neutral: true),
            ]
            // Fine: credit his settings (owner: "it's doing good because of the settings that the user has granted").
            return Content(head: off ? "Notifications are off for shukr." : late ? "Yours may arrive late."
                                     : tsOff ? "A Focus may hold yours back." : "Your settings let shukr's reminders through on time.",
                           points: mine, explainHead: "How iOS delivers notifications", explain: explain,
                           fix: off || late || tsOff)
        }
    }

    private static func whenText(_ date: Date) -> String {
        let t = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "today, \(t)" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday, \(t)" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", \(t)"
    }
}

/// One explanation as a pushed page (owner: not a sheet): the headline as the page's own words, then his settings in one
/// card, then (Notification settings) how iOS delivers in another — the rows in the info cards' style (symbol, a bold
/// line, a grey one).
struct ReminderWhySheet: View {
    let kind: ReminderWhy
    var pendingCount = 0
    @ObservedObject private var health = NotificationHealth.shared

    var body: some View {
        let c = kind.content(health, pendingCount: pendingCount)
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    if kind == .onTime {
                        // A shield: green with a check when his settings let reminders through, orange when not.
                        let bad = kind.needsHand(health)
                        Image(systemName: bad ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(bad ? Color.orange : Color(.systemGreen))
                    }
                    Text(c.head).font(.system(.title3, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
            Section(c.explainHead == nil ? "" : "Your settings") {
                ForEach(c.points.indices, id: \.self) { row(c.points[$0]) }
                if c.fix {
                    Button("Fix in Settings") {
                        kind == .topsUp ? SettingsLinks.app() : SettingsLinks.notifications()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
                }
            }
            if let head = c.explainHead {
                Section(head) {
                    ForEach(c.explain.indices, id: \.self) { row(c.explain[$0]) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .fontDesign(.rounded)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(kind.title).font(.system(.headline, design: .rounded, weight: .regular))
            }
        }
        .task { await health.refresh() }
    }

    /// The info cards' row: the symbol (green, orange where it's in the way, grey when only explaining), a bold line, a
    /// grey one.
    private func row(_ p: ReminderWhy.Point) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.symbol)
                .font(.system(size: 17))
                .foregroundStyle(p.neutral ? Color.secondary : p.warn ? Color.orange : Color(.systemGreen))
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.big).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(p.warn && !p.neutral ? Color.orange : .primary)
                Text(p.small).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Why only 64? / Tops itself up as a sheet (owner: "pop up as sheets – glass material"; then, after the first try was
/// "pretty terrible": no title bar repeating the headline, the rows on the frost itself with hairlines — not grey cards
/// on glass —, a frost thick enough that the page's colours don't smudge through, and the sheet as tall as what it says).
struct ReminderWhyGlassSheet: View {
    let kind: ReminderWhy
    var pendingCount = 0
    @ObservedObject private var health = NotificationHealth.shared
    @State private var height: CGFloat = 0

    var body: some View {
        let c = kind.content(health, pendingCount: pendingCount)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(c.head)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                group(c.explainHead == nil ? nil : "Your settings", c.points)
                if c.fix {
                    Button("Fix in Settings") {
                        kind == .topsUp ? SettingsLinks.app() : SettingsLinks.notifications()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
                    .padding(.top, 14)
                }
                if let head = c.explainHead {
                    group(head, c.explain).padding(.top, 22)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fontDesign(.rounded)
        // As tall as its words (a guessed half height cut Tops itself up off at its third row); the rest scrolls.
        .presentationDetents(height > 0 ? [.height(min(height, UIScreen.main.bounds.height * 0.85))] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .task { await health.refresh() }
    }

    @ViewBuilder private func group(_ title: String?, _ points: [ReminderWhy.Point]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            ForEach(points.indices, id: \.self) { i in
                if i > 0 { Divider().padding(.leading, 40) }
                row(points[i]).padding(.vertical, 10)
            }
        }
    }

    private func row(_ p: ReminderWhy.Point) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.symbol)
                .font(.system(size: 17))
                .foregroundStyle(p.neutral ? Color.secondary : p.warn ? Color.orange : Color(.systemGreen))
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.big).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(p.warn && !p.neutral ? Color.orange : .primary)
                Text(p.small).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Why only 64? / Tops itself up in the floating ⓘ card (InfoModal): the headline, the points, a fix when one is needed,
/// then the explaining points — rows in InfoModalRow's look.
struct ReminderWhyInfo: View {
    let kind: ReminderWhy
    var pendingCount = 0
    @ObservedObject private var health = NotificationHealth.shared

    var body: some View {
        let c = kind.content(health, pendingCount: pendingCount)
        VStack(alignment: .leading, spacing: 14) {
            Text(c.head)
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(c.points.indices, id: \.self) { row(c.points[$0]) }
            if c.fix {
                Button("Fix in Settings") {
                    kind == .topsUp ? SettingsLinks.app() : SettingsLinks.notifications()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.sage)
            }
            if let head = c.explainHead {
                Text(head.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(c.explain.indices, id: \.self) { row(c.explain[$0]) }
            }
        }
        .task { await health.refresh() }
    }

    private func row(_ p: ReminderWhy.Point) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.symbol)
                .font(.system(size: 17))
                .foregroundStyle(p.neutral ? Color.secondary : p.warn ? Color.orange : Color(.systemGreen))
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.big).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(p.warn && !p.neutral ? Color.orange : .primary)
                Text(p.small).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
