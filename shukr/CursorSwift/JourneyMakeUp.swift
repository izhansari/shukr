import SwiftUI
import SwiftData

// To make up (Journey phase 2; spec screen 8, mock-up Missed5; decision journey-past-marks A): the prayers left unmarked
// on days shukr was used — an active day, one with a mark — so a break never lists its prayers. By month, newest first;
// <month> | All; Made up = Qaza now. A row opens its prayer sheet (prayed it in time after all? set the time there).
// Cleared like an inbox (owner): a prayer made up leaves the list for a folded "Made up · N" row at the bottom, and an
// empty list says so with a small moment.

struct JourneyMakeUpPage: View {
    /// The month Journey was showing ("This month" side).
    let month: Date
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @AppStorage("journey.makeUpAll") private var showAll = false
    @State private var open: [Entry] = []
    @State private var madeUp: [Entry] = []
    @State private var showMadeUp = false
    @State private var sheetRow: PrayerModel?
    /// Bumps when the last one is cleared here (the "All caught up" moment plays).
    @State private var cleared = 0

    struct Entry: Identifiable {
        let row: PrayerModel
        let month: Date
        var id: PersistentIdentifier { row.persistentModelID }
    }

    var body: some View {
        let openMonth = open.filter { $0.month == month }
        let madeMonth = madeUp.filter { $0.month == month }
        let shown = showAll ? open : openMonth
        let done = showAll ? madeUp : madeMonth
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To make up").font(.system(size: 34, weight: .light, design: .rounded))
                    Text("Prayers left unmarked on days you used shukr. Tap Made up once you've prayed one, and it counts as Qaza.")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                JourneySwitch(options: [(monthName(month) + " · \(openMonth.count)", "month"), ("All · \(open.count)", "all")],
                              selection: Binding(get: { showAll ? "all" : "month" }, set: { showAll = $0 == "all" }))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                if shown.isEmpty {
                    JourneyCaughtUp(cleared: cleared, line: showAll ? "Every prayer on the days you used shukr is marked."
                                                                    : "Nothing left from \(monthName(month)).")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                        .transition(.opacity)
                } else {
                    ForEach(groups(shown), id: \.0) { start, list in
                        Text(monthHeading(start))
                            .font(.system(size: 12, design: .rounded)).tracking(0.8).foregroundStyle(.secondary)
                            .padding(.top, 22)
                        VStack(spacing: 0) {
                            ForEach(list) { entry in
                                row(entry)
                                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                            }
                        }
                        .padding(.top, 4)
                    }
                    Text("Prayed on time but forgot to mark? Tap the prayer and set the time.")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                if !done.isEmpty { madeUpSection(done).padding(.top, 30) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetRow, onDismiss: { withAnimation(.easeInOut(duration: 0.35)) { load(celebrate: true) } }) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .task { load() }
    }

    // MARK: A row

    private func row(_ entry: Entry) -> some View {
        let row = entry.row
        return HStack(spacing: 12) {
            Button {
                triggerSomeVibration(type: .light)
                sheetRow = row
            } label: {
                HStack(spacing: 12) {
                    Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3).frame(width: 8, height: 8)
                    nameAndDay(row)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                makeUp(row)
            } label: {
                Text("Made up")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().strokeBorder(Color.sage, lineWidth: 1.2))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Marks \(row.displayName) as made up now: Qaza")
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private func nameAndDay(_ row: PrayerModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.displayName).font(.system(size: 17, weight: .light, design: .rounded))
            Text(row.dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Made up, folded at the bottom

    private func madeUpSection(_ list: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(.easeInOut(duration: 0.3)) { showMadeUp.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 15, weight: .light))
                    Text("Made up · \(list.count)")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .contentTransition(.numericText(value: Double(list.count)))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showMadeUp ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            if showMadeUp {
                VStack(spacing: 0) {
                    ForEach(list) { entry in
                        Button {
                            triggerSomeVibration(type: .light)
                            sheetRow = entry.row
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(PrayerScoring.color(for: entry.row.numberScore)).frame(width: 8, height: 8)
                                nameAndDay(entry.row).opacity(0.6)
                                Spacer(minLength: 8)
                                Text(madeUpWhen(entry.row))
                                    .font(.system(size: 13, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// "Qaza · today" / "Qaza · Oct 12".
    private func madeUpWhen(_ row: PrayerModel) -> String {
        guard let at = row.timeAtComplete else { return "Qaza" }
        return "Qaza · " + (Calendar.current.isDateInToday(at) ? "today" : at.formatted(.dateTime.month(.abbreviated).day()))
    }

    private func makeUp(_ row: PrayerModel) {
        guard viewModel.markFromJourney(row, at: Date()) else { return }
        withAnimation(.easeInOut(duration: 0.35)) { load(celebrate: true) }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
    }

    // MARK: Data

    private func groups(_ list: [Entry]) -> [(Date, [Entry])] {
        var out: [(Date, [Entry])] = []
        for e in list {
            if out.last?.0 == e.month { out[out.count - 1].1.append(e) } else { out.append((e.month, [e])) }
        }
        return out
    }

    private func monthName(_ start: Date) -> String {
        start.formatted(.dateTime.month(.wide))
    }

    private func monthHeading(_ start: Date) -> String {
        let sameYear = Calendar.current.isDate(start, equalTo: Date(), toGranularity: .year)
        return (sameYear ? start.formatted(.dateTime.month(.wide)) : start.formatted(.dateTime.month(.wide).year())).uppercased()
    }

    /// `celebrate`: the side shown just went empty here — the caught-up moment plays (with a success buzz).
    private func load(celebrate: Bool = false) {
        let before = (showAll ? open : open.filter { $0.month == month }).count
        (open, madeUp) = Self.entries(context)
        let after = (showAll ? open : open.filter { $0.month == month }).count
        if celebrate, before > 0, after == 0 {
            cleared += 1
            triggerSomeVibration(type: .success)
        }
    }

    /// Open: unmarked prayers whose window has ended, on active days only, never an excused one. Made up: marked on a
    /// later prayer day than its own (the Made up button, or the sheet's default) — newest made up first.
    @MainActor static func entries(_ context: ModelContext, now: Date = Date()) -> (open: [Entry], madeUp: [Entry]) {
        guard let rows = try? context.fetch(FetchDescriptor<PrayerModel>()) else { return ([], []) }
        var kept: [String: PrayerModel] = [:]
        var active: Set<String> = []
        for row in rows where JourneyLog.names.contains(row.name) {
            let id = row.dayKey + row.name
            if row.isCompleted { active.insert(row.dayKey) }
            if let k = kept[id], k.isCompleted, !row.isCompleted { continue }
            kept[id] = row
        }
        let ranges = Excused.ranges
        let entry = { (row: PrayerModel) in Entry(row: row, month: JourneyLog.monthStart(row.dayStart)) }
        let open = kept.values
            .filter { active.contains($0.dayKey) && !$0.isCompleted && $0.endTime <= now
                && !Excused.covers(start: $0.startTime, end: $0.endTime, in: ranges) }
            .sorted { $0.startTime > $1.startTime }
            .map(entry)
        let madeUp = kept.values
            .filter { row in
                guard row.isCompleted, let at = row.timeAtComplete else { return false }
                return PrayerNotificationID.dayKey(PrayerDay.start(for: at)) > row.dayKey
            }
            .sorted { ($0.timeAtComplete ?? .distantPast) > ($1.timeAtComplete ?? .distantPast) }
            .map(entry)
        return (open, madeUp)
    }
}

/// The list cleared: a sage check that draws itself in, "All caught up", one line. Plays again each time the last one is
/// cleared here (`cleared` bumps); opening an already-empty list shows it at rest.
private struct JourneyCaughtUp: View {
    let cleared: Int
    let line: String
    @State private var drawn: CGFloat = 1
    @State private var pop: CGFloat = 1

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.sage.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: drawn).stroke(Color.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.sage)
                    .opacity(drawn)
            }
            .frame(width: 58, height: 58)
            .scaleEffect(pop)
            Text("All caught up").font(.system(size: 20, weight: .light, design: .rounded))
            Text(line)
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        // It comes in as the last row leaves (inserted after the bump), so it plays on appearing too.
        .onAppear { if cleared > 0 { play() } }
        .onChange(of: cleared) { play() }
    }

    private func play() {
        drawn = 0
        pop = 0.85
        withAnimation(.easeOut(duration: 0.7).delay(0.15)) { drawn = 1 }
        withAnimation(.spring(duration: 0.5, bounce: 0.35).delay(0.15)) { pop = 1 }
    }
}
