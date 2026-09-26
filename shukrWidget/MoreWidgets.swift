//
//  MoreWidgets.swift
//  shukrWidget
//
//  Three small widgets beside Prayers (owner, 2026-09-26: "a few simple ones"):
//  - Zikr: laid out like the Reminders widget — today's overall ring and how many are left on
//    top, then the tasks, each with a circle that fills with its progress. Tap → the Zikr page.
//  - Name of the day: one of the 99 Names a day (`NamesOfAllah.nameOfTheDay`). Tap → 99 Names.
//  - Daily Ayah: today's verse once it's been revealed in the app (never spoils the reveal);
//    before that, "today's ayah is waiting". Tap → Daily Ayah.
//  Name and Ayah wear the Daily Ayah share card's look (mint / forest, tracked captions, the
//  circle). Each is one entry per timeline with a far-off refresh: they only change when the day turns or
//  the app says so (a saved session, a reveal), and the app reloads them then.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

private let uthmani = "KFGQPCUthmanTahaNaskh"

private extension View {
    func shukrWidgetBackground() -> some View {
        containerBackground(Color("widgetBgColor"), for: .widget)
    }
    /// The share card's look (AyahShareCard): mint in light mode, forest in dark.
    func shukrBrandBackground() -> some View {
        containerBackground(for: .widget) { BrandBackground() }
    }
}

/// The app's greens, from the Daily Ayah share card: deep-green ink and a leaf-green accent on
/// mint; white and a brighter green on forest.
private enum Brand {
    static let accentLight = Color(red: 0.12, green: 0.52, blue: 0.29)
    static let accentDark = Color(red: 0.45, green: 0.85, blue: 0.55)
    static let inkLight = Color(red: 0.06, green: 0.15, blue: 0.10)
    static let sage = Color(red: 0.40, green: 0.64, blue: 0.50)
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? accentDark : accentLight }
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : inkLight }
}

private struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if scheme == .dark {
            LinearGradient(colors: [Color(red: 0.07, green: 0.17, blue: 0.12), Color(red: 0.02, green: 0.05, blue: 0.035)],
                           startPoint: .top, endPoint: .bottom)
        } else {
            // Stronger than the share card's mint: on a small widget that one read as plain white
            // (owner). A soft light in the top corner keeps it from going flat.
            ZStack {
                LinearGradient(colors: [Color(red: 0.86, green: 0.945, blue: 0.875), Color(red: 0.66, green: 0.84, blue: 0.71)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.55), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 190)
            }
        }
    }
}

/// "name of the day" / "daily ayah · fri, sep 26": the share card's tracked lowercase caption.
private struct BrandCaption: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text.lowercased())
            .font(.system(size: 9, weight: .regular, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Brand.ink(scheme).opacity(0.45))
            .lineLimit(1)
    }
}

/// Midnight tonight: when the name and the ayah change.
private var nextMidnight: Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
}

// MARK: - Zikr tasks

struct ZikrTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.zikr, provider: ZikrTasksProvider()) { entry in
            ZikrTasksWidgetView(entry: entry).shukrWidgetBackground()
        }
        .configurationDisplayName("Zikr")
        .description("Today's zikr tasks and how far along you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ZikrTaskSnapshot: Identifiable {
    let id: String
    let name: String
    let isCountMode: Bool
    let goal: Int
    let count: Int
    let minutes: Int
    let done: Bool
    /// Roughly how long what's left takes at your pace (nil: no history yet).
    var secondsLeft: TimeInterval? = nil

    var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(isCountMode ? count : minutes) / Double(goal), 1)
    }
    var valueText: String { isCountMode ? "\(count)" : "\(minutes)m" }
    var progressText: String { isCountMode ? "\(count)/\(goal)" : "\(minutes)/\(goal) min" }
}

struct ZikrTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [ZikrTaskSnapshot]
    let storeReady: Bool
    var doneCount: Int { tasks.filter(\.done).count }
}

struct ZikrTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZikrTasksEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (ZikrTasksEntry) -> Void) {
        let entry = load()
        completion(context.isPreview && entry.tasks.isEmpty ? Self.sample : entry)
    }

    /// One entry; next refresh when the prayer day turns (Fajr). The app reloads it whenever a
    /// session is saved or it goes to the background.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ZikrTasksEntry>) -> Void) {
        let turn = PrayerDay.rolloverInstant(after: PrayerDay.start())
        completion(Timeline(entries: [load()], policy: .after(max(turn, Date().addingTimeInterval(900)))))
    }

    private func load() -> ZikrTasksEntry {
        guard let container = SharedStore.widgetContainer else {
            return ZikrTasksEntry(date: Date(), tasks: [], storeReady: false)
        }
        let context = ModelContext(container)
        let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let dayStart = PrayerDay.sessionDayStart()
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(
            predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
        let snaps = tasks.map { task -> ZikrTaskSnapshot in
            let p = task.progress(in: sessions)
            return ZikrTaskSnapshot(id: task.id.uuidString, name: task.displayName,
                                    isCountMode: task.isCountMode, goal: task.goal,
                                    count: p.count, minutes: Int(p.seconds / 60),
                                    done: task.isCompleted(with: p),
                                    secondsLeft: task.secondsLeft(p))
        }
        // Like the Zikr page: what's left first, done ones at the end.
        let ordered = snaps.filter { !$0.done } + snaps.filter(\.done)
        return ZikrTasksEntry(date: Date(), tasks: ordered, storeReady: true)
    }

    static let sample = ZikrTasksEntry(date: Date(), tasks: [
        ZikrTaskSnapshot(id: "1", name: "Subhanallah", isCountMode: true, goal: 100, count: 40, minutes: 0, done: false),
        ZikrTaskSnapshot(id: "2", name: "Astaghfirullah", isCountMode: true, goal: 100, count: 0, minutes: 0, done: false),
        ZikrTaskSnapshot(id: "3", name: "Durood", isCountMode: false, goal: 10, count: 0, minutes: 4, done: false),
        ZikrTaskSnapshot(id: "4", name: "Alhamdulillah", isCountMode: true, goal: 33, count: 33, minutes: 0, done: true),
    ], storeReady: true)
}

/// Today's zikr as a whole: each task's share of its goal, averaged (a count task and a minutes
/// task weigh the same).
private extension ZikrTasksEntry {
    var overall: Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.map(\.fraction).reduce(0, +) / Double(tasks.count)
    }
    var left: Int { tasks.count - doneCount }
    var allDone: Bool { !tasks.isEmpty && left == 0 }
    /// Time for everything left today; nil if nothing left has any history to go by.
    var secondsLeft: TimeInterval? {
        let known = tasks.filter { !$0.done }.compactMap(\.secondsLeft)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    var estimateText: String? {
        guard let s = secondsLeft, s > 0 else { return nil }
        return zikrEstimateString(s)
    }
    /// "3 left · ~14 min" (Lock Screen card).
    var lockHeadline: String {
        if tasks.isEmpty { return "" }
        if allDone { return "all done" }
        let base = "\(left) left"
        guard let estimate = estimateText else { return base }
        return base + " · " + estimate
    }
}

extension ZikrTaskSnapshot {
    /// "5/100 · ~4 min" beside a row (medium).
    var rowTrailing: String {
        if done { return "" }
        guard let s = secondsLeft, s > 0 else { return progressText }
        return progressText + " · " + zikrEstimateString(s)
    }
}

/// A row's circle, Reminders style: an empty circle that fills round with the task's progress,
/// and a filled sage check once it's done.
private struct TaskDot: View {
    let task: ZikrTaskSnapshot
    var size: CGFloat = 15
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if task.done {
                Circle().fill(Brand.sage)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.2)
                Circle()
                    .trim(from: 0, to: task.fraction)
                    .stroke(Brand.accent(scheme), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The header ring: today's zikr overall, beads in the middle.
private struct OverallRing: View {
    let entry: ZikrTasksEntry
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: max(entry.overall, 0.001))
                .stroke(entry.allDone ? Brand.sage : Brand.accent(scheme),
                        style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: entry.allDone ? "checkmark" : "circle.hexagonpath")
                .font(.system(size: size * 0.36, weight: entry.allDone ? .semibold : .light))
                .foregroundStyle(entry.allDone ? Brand.sage : Brand.accent(scheme))
        }
        .frame(width: size, height: size)
    }
}

private struct TaskRow: View {
    let task: ZikrTaskSnapshot
    /// Small widget: names only, like Reminders — the circle shows the progress.
    var showsProgress = true
    var body: some View {
        HStack(spacing: 8) {
            TaskDot(task: task)
            Text(task.name)
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(task.done ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsProgress {
            Text(task.rowTrailing)
                .font(.system(size: 11, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}

/// Like the Reminders widget: the ring and a big count on top, the list's name, then the tasks.
struct ZikrTasksWidgetView: View {
    let entry: ZikrTasksEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Lock Screen: today's zikr as a ring, beads (or ✓) inside.
            Gauge(value: entry.overall) {
                Image(systemName: "circle.hexagonpath")
            } currentValueLabel: {
                Image(systemName: entry.allDone ? "checkmark" : "circle.hexagonpath")
                    .font(.system(size: 16, weight: .medium))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.hexagonpath")
                    Text("Zikr").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Text(entry.lockHeadline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .widgetAccentable()
                if let next = entry.tasks.first(where: { !$0.done }) {
                    Text("\(next.name) · \(next.progressText)")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.tasks.isEmpty ? "no tasks yet" : "every task done today")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Gauge(value: entry.overall) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        default:
            // Rows are their own buttons (to their task); the rest opens the Zikr page.
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    Button(intent: OpenTasbeehIntent()) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                }
        }
    }

    private func bigCount(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: -2) {
            Text(entry.allDone ? "✓" : "\(entry.left)")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(entry.allDone ? Brand.sage : .primary)
            Text(entry.allDone ? "all done" : "left today")
                .font(.system(size: 9, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
            if !entry.allDone, let estimate = entry.estimateText {
                Text(estimate)
                    .font(.system(size: 9, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: some View {
        Text("Zikr")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.accent(scheme))
    }

    private func rows(_ limit: Int, progress: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let shown = Array(entry.tasks.prefix(limit))
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, task in
                // Each row opens the Zikr page on its own task (owner).
                Button(intent: OpenZikrTaskIntent(taskID: task.id)) {
                    TaskRow(task: task, showsProgress: progress)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < shown.count - 1 {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 23)
                }
            }
            if entry.tasks.count > limit {
                Text("+\(entry.tasks.count - limit) more")
                    .font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 23).padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !entry.storeReady || entry.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    OverallRing(entry: entry, size: 32)
                    Spacer()
                }
                Spacer()
                title
                Text(entry.storeReady ? "add a daily zikr in shukr" : "open shukr to set things up")
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else if family == .systemMedium {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    OverallRing(entry: entry, size: 40)
                    Spacer(minLength: 0)
                    bigCount(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    title.padding(.top, 2)
                }
                .frame(width: 88)
                rows(4)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    OverallRing(entry: entry, size: 32)
                    Spacer()
                    bigCount(.trailing)
                }
                title.padding(.bottom, 2)
                rows(entry.tasks.count > 3 ? 2 : 3, progress: false)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Name of the day

struct NameOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.name, provider: NameOfTheDayProvider()) { entry in
            NameOfTheDayView(entry: entry).shukrBrandBackground()
        }
        .configurationDisplayName("Name of the Day")
        .description("One of the 99 Names of Allah each day, with its meaning.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NameOfTheDayEntry: TimelineEntry {
    let date: Date
    let name: AllahName
}

struct NameOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> NameOfTheDayEntry { NameOfTheDayEntry(date: Date(), name: NamesOfAllah.all[1]) }
    func getSnapshot(in context: Context, completion: @escaping (NameOfTheDayEntry) -> Void) {
        completion(NameOfTheDayEntry(date: Date(), name: NamesOfAllah.nameOfTheDay()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NameOfTheDayEntry>) -> Void) {
        let entry = NameOfTheDayEntry(date: Date(), name: NamesOfAllah.nameOfTheDay())
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct NameOfTheDayView: View {
    let entry: NameOfTheDayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // Lock Screen: the Arabic beside its name and meaning.
            HStack(spacing: 8) {
                Text(entry.name.arabic)
                    .font(.custom(uthmani, size: 26))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name.transliteration)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(entry.name.meaning)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Text("\(entry.name.transliteration) · \(entry.name.meaning)")
        default:
            Button(intent: OpenNamesIntent()) {
                Group {
                    if family == .systemMedium { medium } else { small }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var ink: Color { Brand.ink(scheme) }
    private var accent: Color { Brand.accent(scheme) }

    private var number: String {
        entry.name.id == 0 ? "the greatest name" : "name \(entry.name.id) of 99"
    }

    /// The Arabic inside a thin ring: the app's circle.
    private func medallion(_ size: CGFloat, font: CGFloat) -> some View {
        ZStack {
            Circle().stroke(accent.opacity(0.28), lineWidth: 1)
            Circle().stroke(accent.opacity(0.10), lineWidth: 1).padding(5)
            Text(entry.name.arabic)
                .font(.custom(uthmani, size: font))
                .foregroundStyle(ink.opacity(0.92))
                .lineLimit(1).minimumScaleFactor(0.4)
                .padding(.horizontal, size * 0.14)
                .offset(y: font * 0.08)   // the font sits high; centre it optically
        }
        .frame(width: size, height: size)
    }

    private var small: some View {
        VStack(spacing: 5) {
            BrandCaption(text: "name of the day")
            medallion(84, font: 30)
            VStack(spacing: 1) {
                Text(entry.name.transliteration)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(entry.name.meaning)
                    .font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            medallion(112, font: 38)
            VStack(alignment: .leading, spacing: 3) {
                BrandCaption(text: number)
                Text(entry.name.transliteration)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(entry.name.meaning)
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Circle().fill(accent.opacity(0.7)).frame(width: 3, height: 3).padding(.vertical, 3)
                Text(entry.name.explanation)
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(0.62))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Daily Ayah

struct DailyAyahWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.ayah, provider: DailyAyahProvider()) { entry in
            DailyAyahWidgetView(entry: entry).shukrBrandBackground()
        }
        .configurationDisplayName("Daily Ayah")
        .description("Today's ayah, once you've revealed it in shukr.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DailyAyahEntry: TimelineEntry {
    let date: Date
    /// Today's revealed ayah; nil = not revealed yet today.
    let ayah: DailyAyahWidgetPayload?
}

struct DailyAyahProvider: TimelineProvider {
    static let sample = DailyAyahWidgetPayload(
        day: Date(), arabic: "فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", english: "So verily, with the hardship, there is relief.",
        reference: "Ash-Sharh · 94:5")

    func placeholder(in context: Context) -> DailyAyahEntry { DailyAyahEntry(date: Date(), ayah: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (DailyAyahEntry) -> Void) {
        let today = DailyAyahWidgetPayload.load().flatMap { $0.isToday ? $0 : nil }
        completion(DailyAyahEntry(date: Date(), ayah: context.isPreview ? (today ?? Self.sample) : today))
    }
    /// The app reloads this when the ayah is revealed; otherwise it only needs to hide it again
    /// at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyAyahEntry>) -> Void) {
        let today = DailyAyahWidgetPayload.load().flatMap { $0.isToday ? $0 : nil }
        completion(Timeline(entries: [DailyAyahEntry(date: Date(), ayah: today)], policy: .after(nextMidnight)))
    }
}

struct DailyAyahWidgetView: View {
    let entry: DailyAyahEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(intent: OpenDailyAyahIntent()) {
            Group {
                if let ayah = entry.ayah { verse(ayah) } else { waiting }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var large: Bool { family == .systemLarge }
    private var ink: Color { Brand.ink(scheme) }
    private var accent: Color { Brand.accent(scheme) }
    private var caption: String {
        "daily ayah · " + entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Laid out like the share card: caption, the Arabic, a small dot, the meaning, the reference.
    private func verse(_ ayah: DailyAyahWidgetPayload) -> some View {
        VStack(spacing: 0) {
            BrandCaption(text: caption)
            Spacer(minLength: large ? 10 : 4)
            Text(ayah.arabic)
                .font(.custom(uthmani, size: large ? 28 : 20))
                .foregroundStyle(ink.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(large ? 8 : 2)
                .lineLimit(large ? 6 : 2)
                .minimumScaleFactor(0.55)
            Circle().fill(accent.opacity(0.8)).frame(width: 3.5, height: 3.5)
                .padding(.vertical, large ? 14 : 6)
            Text(ayah.english)
                .font(.system(size: large ? 15 : 12, weight: .light, design: .rounded))
                .foregroundStyle(ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(large ? 3 : 0)
                .lineLimit(large ? 8 : 2)
                .minimumScaleFactor(0.8)
            Text(ayah.reference)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(accent)
                .padding(.top, large ? 12 : 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    /// Not revealed yet: the verse as the app shows it before the reveal — blurred lines — with
    /// the invitation over it.
    private var waiting: some View {
        VStack(spacing: 0) {
            BrandCaption(text: caption)
            Spacer(minLength: 0)
            ZStack {
                VStack(spacing: large ? 12 : 8) {
                    ForEach([0.8, 0.95, 0.6], id: \.self) { w in
                        Capsule().fill(ink.opacity(0.14)).frame(height: large ? 12 : 9)
                            .frame(maxWidth: .infinity).scaleEffect(x: w)
                    }
                }
                .blur(radius: 5)
                .padding(.horizontal, 30)
                VStack(spacing: 4) {
                    Text("today's ayah is waiting")
                        .font(.system(size: large ? 20 : 16, weight: .light, design: .rounded))
                        .foregroundStyle(ink)
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap")
                        Text("tap to reveal")
                    }
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
#Preview("Zikr", as: .systemMedium) { ZikrTasksWidget() } timeline: { ZikrTasksProvider.sample }
#Preview("Zikr small", as: .systemSmall) { ZikrTasksWidget() } timeline: { ZikrTasksProvider.sample }
#Preview("Name", as: .systemSmall) { NameOfTheDayWidget() } timeline: { NameOfTheDayEntry(date: .now, name: NamesOfAllah.all[5]) }
#Preview("Ayah", as: .systemMedium) { DailyAyahWidget() } timeline: {
    DailyAyahEntry(date: .now, ayah: DailyAyahProvider.sample)
    DailyAyahEntry(date: .now, ayah: nil)
}
#endif


// MARK: - Controls (Control Center, the Lock Screen's bottom buttons, the Action button)

/// Qibla: straight to the qibla map (the same one-shot flag the Prayers widget's compass uses).
struct QiblaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "betternorms.shukr.control.qibla") {
            ControlWidgetButton(action: OpenCompassIntent()) {
                Label("Qibla", systemImage: "location.north.line.fill")
            }
        }
        .displayName("Qibla")
        .description("Open shukr's qibla map.")
    }
}

/// Tasbeeh: straight to the Zikr page.
struct TasbeehControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "betternorms.shukr.control.tasbeeh") {
            ControlWidgetButton(action: OpenTasbeehIntent()) {
                Label("Tasbeeh", systemImage: "circle.hexagonpath")
            }
        }
        .displayName("Tasbeeh")
        .description("Open shukr's zikr page.")
    }
}
