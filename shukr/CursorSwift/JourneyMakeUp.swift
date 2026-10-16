import SwiftUI
import SwiftData

// To make up (Journey phase 2; spec screen 8, mock-up Missed5; decision journey-past-marks A): the prayers left unmarked
// on days shukr was used — an active day, one with a mark — so a break never lists its prayers. Made up = Qaza now. A row
// opens its prayer sheet (prayed it in time after all? set the time there; decision makeup-row-tap: kept for now).
// Round 2 (owner, 484 of them): the total and each prayer's count on top (a prayer filters the list), months as pinned
// headings with their totals ("12 left · 3 made up"), a month scrubber down the right edge; Made up keeps the row in place
// as "✓ Made up · Undo" for 3 s (decision makeup-made-feedback A), then it leaves the list — made-up prayers are out of the
// way like Reminders' completed ones: "✓ N made up · Show" under the total puts them back in their months, greyed (owner,
// round 3: not folded under each month); a month with nothing left drops out; a cleared list says "All caught up".

struct JourneyMakeUpPage: View {
    /// The month Journey was showing (the switch's left side).
    let month: Date
    /// Opened from Prayer scores' "N to make up ›": that prayer only, over all months (Frank's check: it opened on the
    /// month with "1 prayer" while the row said 103). Shown so for this visit, the stored switch untouched.
    var startOnly: String? = nil
    @State private var started = false
    @State private var allThisVisit = false
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @AppStorage("journey.makeUpAll") private var showAll = false
    @State private var open: [Entry] = JourneyMakeUpPage.last?.open ?? []
    @State private var madeUp: [Entry] = JourneyMakeUpPage.last?.madeUp ?? []
    /// One prayer only (a tap on its count).
    @State private var only: String?
    /// Made-up prayers shown in their months (Reminders' Show Completed).
    @AppStorage("journey.showMadeUp") private var showMade = false
    /// Just made up: still in place with Undo until its 3 s run out (the token tells a later tap from this one).
    @State private var settling: [PersistentIdentifier: UUID] = [:]
    @State private var sheetRow: PrayerModel?
    /// Bumps when the last one is cleared here (the "All caught up" moment plays).
    @State private var cleared = 0
    /// The month under the finger on the scrubber (its name shows beside it).
    @State private var scrubbing: Date?
    /// Where each month's heading sits in the list (its pinned one stays at the top); the top one is the scrubber's big dot.
    @State private var headingY: [Date: CGFloat] = [:]
    private var topMonth: Date? {
        headingY.filter { $0.value <= 80 }.max { $0.value < $1.value }?.key
    }

    /// A prayer to make up (or made up), as plain values: read off the main thread (`entries`), the row itself looked up
    /// by id only for an action (`model`). Frank's trace, 2026-10-15: `entries` took 108–130 ms on the main thread on
    /// open, on Made up (3 s later, inside the row's leave) and on Undo (inside the tap).
    struct Entry: Identifiable, Sendable {
        let id: PersistentIdentifier
        let name: String
        let displayName: String
        let dayKey: String
        let dayStart: Date
        let startTime: Date
        let isCompleted: Bool
        let numberScore: Double?
        let timeAtComplete: Date?
        let month: Date

        init(_ row: PrayerModel) {
            id = row.persistentModelID
            name = row.name
            displayName = row.displayName
            dayKey = row.dayKey
            dayStart = row.dayStart
            startTime = row.startTime
            isCompleted = row.isCompleted
            numberScore = row.numberScore
            timeAtComplete = row.timeAtComplete
            month = JourneyLog.monthStart(dayStart)
        }
    }

    /// The entry's row, for an action (the sheet, Made up, Undo).
    private func model(_ e: Entry) -> PrayerModel? { context.model(for: e.id) as? PrayerModel }

    // MARK: What's shown

    private var all: Bool { showAll || allThisVisit }
    private func inScope(_ e: Entry) -> Bool { all || e.month == month }
    private func isSettling(_ e: Entry) -> Bool { settling[e.id] != nil }
    /// Open in the switch's scope (just-made-up ones included, in place).
    private var scopedOpen: [Entry] { open.filter(inScope) }
    private var shownOpen: [Entry] { scopedOpen.filter { only == nil || $0.name == only } }
    private var shownMade: [Entry] { madeUp.filter { inScope($0) && (only == nil || $0.name == only) } }
    /// The months on the page, newest first.
    private var months: [Date] {
        Array(Set(shownOpen.map(\.month) + (showMade ? shownMade.map(\.month) : []))).sorted(by: >)
    }

    var body: some View {
        let left = scopedOpen.filter { !isSettling($0) }
        let shownLeft = shownOpen.filter { !isSettling($0) }
        let months = months
        let scrubber = months.count > 3
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    summary(left)
                    if shownLeft.isEmpty && !shownOpen.contains(where: isSettling) {
                        JourneyCaughtUp(cleared: cleared, line: caughtUpLine)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .transition(.opacity)
                    }
                    ForEach(months, id: \.self) { m in
                        Section {
                            ForEach(monthRows(m)) { entry in
                                Group {
                                    if entry.isCompleted && !isSettling(entry) { madeRow(entry) } else { row(entry) }
                                }
                                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
                            }
                        } header: {
                            monthHeader(m).id(m)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("makeUp")).minY } action: { headingY[m] = $0 }
                        }
                    }
                    if !shownLeft.isEmpty {
                        Text("Prayed on time but forgot to mark? Tap the prayer and set the time.")
                            .font(.system(size: 13, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, scrubber ? 34 : 20)
                .padding(.bottom, 30)
            }
            .coordinateSpace(.named("makeUp"))
            .overlay(alignment: .trailing) {
                if scrubber { monthScrubber(months, proxy: proxy).padding(.trailing, 4) }
            }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        // The reload is read off the main thread first, then animated in (it ran inside the animation: a stall as the
        // sheet closed).
        .sheet(item: $sheetRow, onDismiss: { Task { await reload(celebrate: true, animation: .easeInOut(duration: 0.35)) } }) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .onChange(of: showAll) { only = nil }
        .onAppear {
            guard !started else { return }
            started = true
            if let startOnly { only = startOnly; allThisVisit = true }
        }
        .task { await reload() }
    }

    /// A month's rows, newest first: what's left, and the made-up ones among them while shown.
    private func monthRows(_ m: Date) -> [Entry] {
        let open = shownOpen.filter { $0.month == m }
        guard showMade else { return open }
        return (open + shownMade.filter { $0.month == m }).sorted { $0.startTime > $1.startTime }
    }

    private var caughtUpLine: String {
        if let only { return "No \(only) left to make up." }
        return all ? "Every prayer on the days you used shukr is marked." : "Nothing left from \(monthName(month))."
    }

    // MARK: The top: the total, each prayer's count, the switch

    private func summary(_ left: [Entry]) -> some View {
        let counts = JourneyLog.names.map { name in (name, left.filter { $0.name == name }.count) }.filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            Text("To make up").font(.system(size: 34, weight: .light, design: .rounded))
            Text("Prayers left unmarked on days you used shukr.")
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(left.count)")
                    .font(.system(size: 44, weight: .thin, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(left.count)))
                Text(left.count == 1 ? "prayer" : "prayers")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
            .animation(.snappy, value: left.count)
            let made = madeUp.filter(inScope).count
            if made > 0 {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.3)) { showMade.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .light))
                        Text("\(made) made up")
                            .contentTransition(.numericText(value: Double(made)))
                        Text("·")
                        Text(showMade ? "Hide" : "Show").foregroundStyle(.primary)
                    }
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: made)
                .accessibilityLabel(showMade ? "Hide the \(made) made up" : "Show the \(made) made up")
            }
            JourneySwitch(options: [(monthName(month), "month"), ("All months", "all")],
                          selection: Binding(get: { all ? "all" : "month" }, set: { showAll = $0 == "all"; allThisVisit = false; only = nil }))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            if counts.count > 1 || only != nil {
                // Each prayer's count; a tap shows only that prayer ("work through my Fajrs").
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(counts, id: \.0) { name, n in
                            Button {
                                triggerSomeVibration(type: .light)
                                withAnimation(.easeInOut(duration: 0.25)) { only = only == name ? nil : name }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(name)
                                    Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.system(size: 14, weight: only == name ? .regular : .light, design: .rounded))
                                .padding(.horizontal, 12).frame(height: 32)
                                .background {
                                    if only == name {
                                        NeuPressed(shape: Capsule(), radius: 3, offset: 2)
                                    } else {
                                        Capsule().fill(Color.primary.opacity(0.05))
                                    }
                                }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: A month

    /// Pinned while its rows scroll under it: the month and its totals.
    private func monthHeader(_ m: Date) -> some View {
        let rows = shownOpen.filter { $0.month == m }
        let left = rows.filter { !isSettling($0) }.count
        let made = shownMade.filter { $0.month == m }.count + rows.filter(isSettling).count
        let totals = [left > 0 ? "\(left) left" : nil, made > 0 ? "\(made) made up" : nil].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline) {
            Text(monthHeading(m))
                .font(.system(size: 12, weight: .medium, design: .rounded)).tracking(0.8)
            Spacer()
            Text(totals)
                .font(.system(size: 12, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(.secondary)
        .padding(.top, 18).padding(.bottom, 6)
        .background(theme.surface)
        .animation(.snappy, value: totals)
    }

    @ViewBuilder private func row(_ entry: Entry) -> some View {
        let justMade = isSettling(entry)
        HStack(spacing: 12) {
            Button {
                triggerSomeVibration(type: .light)
                sheetRow = model(entry)
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if justMade {
                            Circle().fill(PrayerScoring.color(for: entry.numberScore))
                        } else {
                            Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                        }
                    }
                    .frame(width: 8, height: 8)
                    nameAndDay(entry).opacity(justMade ? 0.55 : 1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if justMade {
                // In place for 3 s: what happened, and the way back (owner: "where did it go?").
                HStack(spacing: 10) {
                    Label("Made up", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Button {
                        undo(entry)
                    } label: {
                        Text("Undo")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            } else {
                Button {
                    makeUp(entry)
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
                .accessibilityHint("Marks \(entry.displayName) as made up now: Qaza")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private func nameAndDay(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.displayName).font(.system(size: 17, weight: .light, design: .rounded))
            Text(e.dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// A made-up prayer among what's left (while shown): greyed, its dot filled, when it was made up. Opens its sheet.
    private func madeRow(_ entry: Entry) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            sheetRow = model(entry)
        } label: {
            HStack(spacing: 12) {
                Circle().fill(PrayerScoring.color(for: entry.numberScore)).frame(width: 8, height: 8)
                nameAndDay(entry).opacity(0.55)
                Spacer(minLength: 8)
                Label(madeUpWhen(entry), systemImage: "checkmark")
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    /// "Qaza · today" / "Qaza · Oct 12".
    private func madeUpWhen(_ e: Entry) -> String {
        guard let at = e.timeAtComplete else { return "Qaza" }
        return "Qaza · " + (Calendar.current.isDateInToday(at) ? "today" : at.formatted(.dateTime.month(.abbreviated).day()))
    }

    // MARK: The scrubber

    private let dotSlot: CGFloat = 14
    private let scrubberPad: CGFloat = 10

    /// The Zikr wheel's scrubber (owner: copy it, not the soft look): one dot per month down the right edge, the month at
    /// the top of the list bigger, a month with nothing left sage; a finger on them drags through the months (a tick
    /// each), a pill beside it naming the month.
    private func monthScrubber(_ months: [Date], proxy: ScrollViewProxy) -> some View {
        let current = scrubbing ?? topMonth ?? months.first
        return VStack(spacing: 0) {
            ForEach(months, id: \.self) { m in
                let here = m == current
                let done = !shownOpen.contains { $0.month == m && !isSettling($0) }
                Circle()
                    .fill(done ? Color.sage : Color.primary.opacity(here ? 0.55 : 0.18))
                    .frame(width: here ? 7 : 5, height: here ? 7 : 5)
                    .frame(width: 24, height: dotSlot)
            }
        }
        .padding(.vertical, scrubberPad)
        .background(Capsule().fill(Color.primary.opacity(scrubbing != nil ? 0.07 : 0)))
        .scaleEffect(scrubbing != nil ? 1.15 : 1, anchor: .trailing)
        .overlay(alignment: .topTrailing) {
            if let scrubbing, let index = months.firstIndex(of: scrubbing) {
                Text(scrubbing.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .fixedSize()
                    .offset(x: -40, y: scrubberPad + dotSlot * CGFloat(index) - 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle().inset(by: -12))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = min(max(Int((value.location.y - scrubberPad) / dotSlot), 0), months.count - 1)
                    guard months[index] != scrubbing else { return }
                    triggerSomeVibration(type: .light)
                    withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = months[index] }
                    proxy.scrollTo(months[index], anchor: .top)
                }
                .onEnded { _ in withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = nil } }
        )
        .animation(.snappy(duration: CircleMotion.quick), value: current)
        .accessibilityHidden(true)
    }

    // MARK: Making up

    private func makeUp(_ entry: Entry) {
        guard let row = model(entry), viewModel.markFromJourney(row, at: Date()) else { return }
        let id = entry.id, token = UUID()
        withAnimation(.easeInOut(duration: 0.25)) { settling[id] = token }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard settling[id] == token else { return }
            // The fresh list is read first (off the main thread), then the row leaves with it in one animation.
            let keep = Set(settling.keys).subtracting([id])
            let result = await Self.entries(container: context.container, keeping: keep)
            guard settling[id] == token else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                settling[id] = nil
                apply(result, celebrate: true)
            }
        }
    }

    private func undo(_ entry: Entry) {
        triggerSomeVibration(type: .light)
        guard let row = model(entry) else { return }
        viewModel.unmarkFromJourney(row)
        withAnimation(.easeInOut(duration: 0.25)) { settling[entry.id] = nil }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
        Task { await reload(animation: .easeInOut(duration: 0.25)) }
    }

    // MARK: Data

    private func monthName(_ start: Date) -> String {
        Calendar.current.isDate(start, equalTo: Date(), toGranularity: .year)
            ? start.formatted(.dateTime.month(.wide)) : start.formatted(.dateTime.month(.abbreviated).year())
    }

    private func monthHeading(_ start: Date) -> String {
        let sameYear = Calendar.current.isDate(start, equalTo: Date(), toGranularity: .year)
        return (sameYear ? start.formatted(.dateTime.month(.wide)) : start.formatted(.dateTime.month(.wide).year())).uppercased()
    }

    /// The entries read off the main thread, then set — inside `animation` when given. `celebrate`: the side shown just
    /// went empty here — the caught-up moment plays (with a success buzz).
    private func reload(celebrate: Bool = false, animation: Animation? = nil) async {
        let result = await Self.entries(container: context.container, keeping: Set(settling.keys))
        if let animation {
            withAnimation(animation) { apply(result, celebrate: celebrate) }
        } else {
            apply(result, celebrate: celebrate)
        }
    }

    private func apply(_ result: (open: [Entry], madeUp: [Entry]), celebrate: Bool) {
        let leftNow = { (list: [Entry]) in list.filter { self.inScope($0) && !self.isSettling($0) }.count }
        let before = leftNow(open)
        (open, madeUp) = result
        Self.last = result
        if celebrate, before > 0, leftNow(open) == 0, settling.isEmpty {
            cleared += 1
            triggerSomeVibration(type: .success)
        }
    }

    /// The last entries read: the page opens with them while fresh ones are read.
    @MainActor static var last: (open: [Entry], madeUp: [Entry])?

    /// `entries` off the main thread, from its own context on the store. `nonisolated`, as the two below: a View's statics
    /// are main-actor isolated, and without it the detached task hopped back to the main thread to run the fetch (Frank's
    /// trace on c240064: all 147 samples of the 135 ms on Main Thread).
    nonisolated static func entries(container: ModelContainer, keeping: Set<PersistentIdentifier> = [], now: Date = Date()) async
        -> (open: [Entry], madeUp: [Entry]) {
        let ranges = await MainActor.run { Excused.ranges }
        return await Task.detached(priority: .userInitiated) {
            entries(in: ModelContext(container), keeping: keeping, ranges: ranges, now: now)
        }.value
    }

    /// How many are owed (the day page's "N to make up" pill), read off the main thread.
    nonisolated static func openCount(container: ModelContainer) async -> Int {
        await entries(container: container).open.count
    }

    /// Open: unmarked prayers whose window has ended, on active days only, never an excused one — plus `keeping`, just made
    /// up and still shown in place. Made up: marked on a later prayer day than its own (the Made up button, or the sheet's
    /// default) — newest made up first.
    nonisolated static func entries(in context: ModelContext, keeping: Set<PersistentIdentifier> = [], ranges: [ExcusedRange],
                        now: Date = Date()) -> (open: [Entry], madeUp: [Entry]) {
        guard let rows = try? context.fetch(FetchDescriptor<PrayerModel>()) else { return ([], []) }
        var kept: [String: PrayerModel] = [:]
        var active: Set<String> = []
        for row in rows where JourneyLog.names.contains(row.name) {
            let id = row.dayKey + row.name
            if row.isCompleted { active.insert(row.dayKey) }
            if let k = kept[id], k.isCompleted, !row.isCompleted { continue }
            kept[id] = row
        }
        let entry = { (row: PrayerModel) in Entry(row) }
        let open = kept.values
            .filter { row in
                if keeping.contains(row.persistentModelID) { return true }
                return active.contains(row.dayKey) && !row.isCompleted && row.endTime <= now
                    && !Excused.covers(start: row.startTime, end: row.endTime, in: ranges)
            }
            .sorted { $0.startTime > $1.startTime }
            .map(entry)
        let madeUp = kept.values
            .filter { row in
                guard row.isCompleted, !keeping.contains(row.persistentModelID), let at = row.timeAtComplete else { return false }
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
