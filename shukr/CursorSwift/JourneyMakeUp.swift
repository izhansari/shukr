import SwiftUI
import SwiftData

// To make up (Journey phase 2; spec screen 8, mock-up Missed5; decision journey-past-marks A): the prayers left unmarked
// on days shukr was used — an active day, one with a mark — so a break never lists its prayers. Made up = Qaza now.
// Round 2 (owner, 484 of them): the total and each prayer's count on top (a prayer filters the list), months as pinned
// headings with their totals ("12 left · 3 made up"), a month scrubber down the right edge; Made up keeps the row in place
// as "✓ Made up · Undo" for 3 s (decision makeup-made-feedback A), then it leaves the list — made-up prayers are out of the
// way like Reminders' completed ones: "✓ N made up · Show" under the total puts them back in their months, greyed (owner,
// round 3: not folded under each month); a month with nothing left drops out; a cleared list says "All caught up".
// Round 4 (owner, 2026-10-17): always all months (no "October | All months"); the top stays in view as the list scrolls —
// the total missed, "✓ N made up · Show" with the share left at its end, a bar of made up over missed, the prayers' chips.
// Round 5 (owner, 2026-10-17, from Frank's visual audit): a row's dot is its control, like a to-do (no "Made up" capsule
// on every row, no sage); a row no longer opens its prayer sheet ("lets just get rid of that functionality here"), so the
// hint about it is gone too; the five chips fit across in equal columns, name over count; the scrubber names the month on
// top and marks where a year starts, a cleared month's dot in Journey's green.

struct JourneyMakeUpPage: View {
    /// The month Journey was showing (the caught-up line's; the page always shows every month).
    let month: Date
    /// Opened from Prayer scores' "N to make up ›": that prayer only, over all months (Frank's check: it opened on the
    /// month with "1 prayer" while the row said 103).
    var startOnly: String? = nil
    @State private var started = false
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @State private var open: [Entry] = JourneyMakeUpPage.last?.open ?? []
    @State private var madeUp: [Entry] = JourneyMakeUpPage.last?.madeUp ?? []
    /// One prayer only (a tap on its count).
    @State private var only: String?
    /// The top's folded height and how far it folds (JourneyMakeUpHead measures it): the list's top margin and the
    /// empty room at its start.
    @State private var topFolded: CGFloat = 0
    @State private var foldBy: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    /// Just made up: still in place with Undo until its 3 s run out (the token tells a later tap from this one).
    @State private var settling: [PersistentIdentifier: UUID] = [:]
    /// Bumps when the last one is cleared here (the "All caught up" moment plays).
    @State private var cleared = 0
    /// The month at the top of the list, for the scrubber only: the page itself never reads it, so a scroll redraws nothing
    /// but the scrubber's dots, and only when the top month changes (it was the page's state, set by every heading on every
    /// frame: the whole page rebuilt as it scrolled — Izhan: "it lags a lot on my phone when i scroll or use the scrubber").
    @State private var scroll = JourneyMakeUpScroll()

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
        /// "Tuesday, Sep 8", written once off the main thread (it was formatted in every row on every redraw).
        let dayLine: String

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
            dayLine = dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    /// The entry's row, for an action (the sheet, Made up, Undo).
    private func model(_ e: Entry) -> PrayerModel? { context.model(for: e.id) as? PrayerModel }

    // MARK: What's shown

    /// Every month, always (owner, 2026-10-17: "Get rid of the switcher … and just always display all months").
    private let all = true
    private func inScope(_ e: Entry) -> Bool { all || e.month == month }
    private func isSettling(_ e: Entry) -> Bool { settling[e.id] != nil }

    /// What the page shows, worked out in one pass per redraw: the months, their rows and totals, each prayer's count.
    /// Every count used to refilter all the entries (484 on his phone) — each heading twice, each scrubber dot once.
    private struct Shown {
        /// Newest first.
        var months: [Date] = []
        /// A month's rows, newest first: what's left (just-made-up ones in place, with Undo).
        var rows: [Date: [Entry]] = [:]
        var monthLeft: [Date: Int] = [:]
        var monthMade: [Date: Int] = [:]
        /// The made up, at the bottom: newest made up first, whatever the prayer's own day.
        var madeRows: [Entry] = []
        /// Each prayer's count left, for the chips (not narrowed by the chip that's on).
        var counts: [(String, Int)] = []
        /// Left under the chip that's on; made up (a just-made-up one, still showing Undo, counts as made up).
        var left = 0
        var made = 0
        var anySettling = false
    }

    private func shown() -> Shown {
        var s = Shown()
        var perPrayer: [String: Int] = [:]
        for e in open where inScope(e) {
            let justMade = isSettling(e)
            if !justMade { perPrayer[e.name, default: 0] += 1 }
            guard only == nil || e.name == only else { continue }
            s.rows[e.month, default: []].append(e)
            if justMade {
                s.monthMade[e.month, default: 0] += 1
                s.made += 1
                s.anySettling = true
            } else {
                s.monthLeft[e.month, default: 0] += 1
                s.left += 1
            }
        }
        s.madeRows = madeUp.filter { inScope($0) && (only == nil || $0.name == only) }
        s.made += s.madeRows.count
        s.months = s.rows.keys.sorted(by: >)
        s.counts = JourneyLog.names.compactMap { name in perPrayer[name].map { (name, $0) } }
        return s
    }

    /// The made-up section's id (for "N made up" to scroll to).
    private static let madeID = "madeUp"

    var body: some View {
        let shown = shown()
        let months = shown.months
        let scrubber = months.count > 3
        // The top stays in view and the list scrolls under it (owner, 2026-10-17: "Make this top area always stay in view
        // as user scrolls"), and it folds as the list scrolls (owner, 2026-10-17, option 1: "the top is way too big, but I
        // really want to keep all of that content"): the title and its line fold away, the number shrinks, the made-up line,
        // the bar and the chips stay as they are. The list runs under the top from the screen's top; its first `foldBy`
        // points are empty room the top folds into, so the rows follow the finger 1:1 while it folds.
        ScrollViewReader { proxy in
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: foldBy)
                    if shown.left == 0 && !shown.anySettling {
                        JourneyCaughtUp(cleared: cleared, line: caughtUpLine)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .transition(.opacity)
                    }
                    ForEach(months, id: \.self) { m in
                        Section {
                            ForEach(shown.rows[m] ?? []) { entry in
                                row(entry)
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
                            }
                        } header: {
                            monthHeader(m, left: shown.monthLeft[m] ?? 0, made: shown.monthMade[m] ?? 0).id(m)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("makeUp")).minY } action: { [scroll] in
                                    scroll.report(m, y: $0)
                                }
                                .onDisappear { [scroll] in scroll.forget(m) }
                        }
                    }
                    // Made up: all at the bottom, newest first, out of their months (owner, 2026-10-17: "if we made it up,
                    // I just want to move it all the way to the bottom of the page. Then we don't even need to show and
                    // hide … listed in the order we completed it, with the newest at the top of that section").
                    if !shown.madeRows.isEmpty {
                        Section {
                            ForEach(shown.madeRows) { entry in
                                madeRow(entry).transition(.opacity)
                            }
                        } header: {
                            madeHeader(shown.madeRows.count).id(Self.madeID)
                        }
                    }
                }
                .padding(.leading, 20)
                // The scrubber's gutter: its dots and, beside them, the month on top and the year marks.
                .padding(.trailing, scrubber ? 56 : 20)
                .padding(.bottom, 30)
            }
            .contentMargins(.top, topFolded, for: .scrollContent)
            .coordinateSpace(.named("makeUp"))
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { [scroll] _, y in
                scroll.scrolled(y)
            }
            .overlay(alignment: .trailing) {
                if scrubber {
                    JourneyMakeUpScrubber(months: months, cleared: Set(months.filter { shown.monthLeft[$0] == nil }),
                                          scroll: scroll, proxy: proxy)
                        .padding(.trailing, 4)
                        .padding(.top, topFolded + foldBy)
                }
            }
            summary(shown, proxy: proxy)
                .padding(.horizontal, 20)
                .background(theme.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [scroll] height in
                    scroll.topHeight = height
                    settleTop()
                }
        }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { JourneyMakeUpNavTitle(scroll: scroll) }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let startOnly { only = startOnly }
        }
        .task { await reload() }
    }

    /// The top's folded height, whatever the fold now: the room it takes minus what is still to fold (page state only
    /// when it really changes — a fold frame leaves it as it is).
    private func settleTop() {
        guard scroll.topHeight > 0 else { return }
        let folded = (scroll.topHeight - foldBy * (1 - scroll.fold)).rounded()
        if abs(folded - topFolded) > 0.5 { topFolded = folded }
        scroll.topLine = folded + 24
    }

    private var caughtUpLine: String {
        if let only { return "No \(only) left to make up." }
        return all ? "Every prayer on the days you used shukr is marked." : "Nothing left from \(monthName(month))."
    }

    // MARK: The top: the total, each prayer's count, the switch

    private func summary(_ shown: Shown, proxy: ScrollViewProxy) -> some View {
        let counts = shown.counts
        // Following the chip that's on: its prayer's numbers. A just-made-up one (still showing Undo) counts as made up.
        let made = shown.made
        let missed = shown.left + made
        let share = missed == 0 ? 0 : Double(made) / Double(missed)
        let leftPct = missed == 0 ? 0 : Int(((1 - share) * 100).rounded())
        let green = JourneyTileColor.of(.metGoal, dark: scheme == .dark)
        return VStack(alignment: .leading, spacing: 0) {
            JourneyMakeUpHead(missed: missed,
                              words: missed == 1 ? "\(only ?? "prayer") missed" : "\(only.map { "\($0)s" } ?? "prayers") missed",
                              scroll: scroll) { by in
                if abs(by - foldBy) > 0.5 {
                    foldBy = by
                    scroll.foldDistance = by
                    settleTop()
                }
            }
            // "✓ N made up" over the bar's green start, in that green (owner, 2026-10-17: "the green that fills that
            // progress track is related to that text"), and at its end the share still to make up. A tap goes to the made
            // up at the bottom.
            HStack(alignment: .firstTextBaseline) {
                if made > 0 {
                    Button {
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.madeID, anchor: .top) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .regular))
                            Text("\(made) made up")
                                .contentTransition(.numericText(value: Double(made)))
                        }
                        .foregroundStyle(green)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(made) made up")
                    .accessibilityHint("Goes to the made up, at the bottom")
                } else {
                    Text("None made up yet").padding(.vertical, 4)
                }
                Spacer(minLength: 8)
                Text(missed == 0 ? "" : "\(leftPct)% left")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(leftPct)))
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .animation(.snappy, value: made)
            // Made up over missed.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    // Journey's green, as the scrubber's cleared months (owner: "use that same green color").
                    Capsule().fill(green).frame(width: max(share > 0 ? 6 : 0, g.size.width * share))
                }
            }
            .frame(height: 6)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.35), value: share)
            .accessibilityElement()
            .accessibilityLabel("\(made) of \(missed) made up")
            if counts.count > 1 || only != nil {
                // Each prayer's count; a tap shows only that prayer ("work through my Fajrs"). Five equal columns across,
                // name over count (owner, 2026-10-17: Isha was cut off at the edge); one with none left stays, faint.
                let left = Dictionary(uniqueKeysWithValues: counts)
                HStack(spacing: 7) {
                    ForEach(JourneyLog.names, id: \.self) { name in
                        let n = left[name] ?? 0
                        let on = only == name
                        // Prayer scores' grade tiles (owner, 2026-10-17: "those are the perfect kind of buttons that we could
                        // use for the makeup page to replace the prayer selector"): raised, the count large over the name;
                        // the one on pressed in, the rest stepping back. The prayer's symbol where those have a grade dot.
                        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                        Button {
                            triggerSomeVibration(type: .light)
                            withAnimation(.easeInOut(duration: 0.25)) { only = on ? nil : name }
                        } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: prayerIcon(for: name))
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                    Text("\(n)")
                                        .font(.system(size: 18, weight: .light, design: .rounded))
                                        .monospacedDigit()
                                        .contentTransition(.numericText(value: Double(n)))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                Text(name)
                                    .font(.system(size: 12, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background {
                                if on { NeuPressed(shape: shape, radius: 3, offset: 2) }
                                else { NeuRaised(shape: shape, radius: 3.5, offset: 1.8) }
                            }
                            .opacity(only != nil && !on ? 0.55 : 1)
                            .contentShape(shape)
                        }
                        .buttonStyle(.plain)
                        .disabled(n == 0 && !on)
                        .opacity(n == 0 && !on ? 0.4 : 1)
                        .accessibilityLabel("\(name), \(n) left")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .animation(.snappy, value: counts.map(\.1))
                .padding(.top, 14)
            }
        }
        // Room under the chips before the line (owner: "theyre like kissing it rn").
        .padding(.bottom, 16)
    }

    // MARK: A month

    /// Pinned while its rows scroll under it: the month and its totals.
    private func monthHeader(_ m: Date, left: Int, made: Int) -> some View {
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

    /// The made-up section's heading, pinned like a month's: "MADE UP" and how many.
    private func madeHeader(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("MADE UP")
                .font(.system(size: 12, weight: .medium, design: .rounded)).tracking(0.8)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 30).padding(.bottom, 6)
        .background(theme.surface)
        .animation(.snappy, value: count)
    }

    /// A prayer left: its dot is the control, like a to-do (owner, 2026-10-17: "yeah lets do this") — a tap fills it with a
    /// ✓ and the row says "Made up · Undo" for 3 s (a tap on the filled dot undoes it too), then it leaves. The row itself
    /// no longer opens the prayer's sheet (owner: "lets just get rid of that functionality here").
    @ViewBuilder private func row(_ entry: Entry) -> some View {
        let justMade = isSettling(entry)
        HStack(spacing: 12) {
            Button {
                if justMade {
                    undo(entry)
                } else {
                    triggerSomeVibration(type: .light)
                    makeUp(entry)
                }
            } label: {
                JourneyMakeUpCheck(done: justMade)
                    .padding(11)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -11)
            .padding(.trailing, -11)
            .accessibilityLabel(justMade ? "Made up. Undo" : "Make up \(entry.displayName), \(entry.dayLine)")
            .accessibilityHint(justMade ? "" : "Marks it as made up now: Qaza")
            nameAndDay(entry).opacity(justMade ? 0.55 : 1)
            Spacer(minLength: 8)
            if justMade {
                // In place for 3 s: what happened, and the way back (owner: "where did it go?").
                HStack(spacing: 6) {
                    Text("Made up").foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    Button {
                        undo(entry)
                    } label: {
                        Text("Undo").padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 14, weight: .light, design: .rounded))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private func nameAndDay(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.displayName).font(.system(size: 17, weight: .light, design: .rounded))
            Text(e.dayLine)
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// A made-up prayer, in the section at the bottom: greyed, its ring filled, its own day and when it was made up.
    private func madeRow(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            JourneyMakeUpCheck(done: true)
            nameAndDay(entry)
            Spacer(minLength: 8)
            Text(madeUpWhen(entry))
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .opacity(0.55)
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// "Qaza · today" / "Qaza · Oct 12".
    private func madeUpWhen(_ e: Entry) -> String {
        guard let at = e.timeAtComplete else { return "Qaza" }
        return "Qaza · " + (Calendar.current.isDateInToday(at) ? "today" : at.formatted(.dateTime.month(.abbreviated).day()))
    }

    // MARK: Making up

    private func makeUp(_ entry: Entry) {
        guard let row = model(entry), viewModel.markFromJourney(row, at: Date()) else { return }
        let id = entry.id, token = UUID()
        withAnimation(.easeInOut(duration: 0.25)) { settling[id] = token }
        JourneyChange.post()
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
        JourneyChange.post()
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
        // A fresh start that cleared them: the list starts on its day, made up ones too (nothing is deleted; Undo brings
        // the rest back).
        let from = FreshStart.makeUpFromKey
        for row in rows where JourneyLog.names.contains(row.name) && from.map({ row.dayKey >= $0 }) ?? true {
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

/// Where the month headings sit as the list scrolls. Every heading reports on every frame into `y`, which nothing
/// observes; `top` changes only when another month reaches the top, and only the scrubber reads it.
@Observable final class JourneyMakeUpScroll {
    /// The month whose heading is at (or pinned to) the top of the list: the scrubber's big dot.
    var top: Date?
    /// How far the top has folded: 0 open … 1 folded. Only the top's head and the bar's small title read it, so the fold
    /// redraws those two and nothing else.
    var fold: CGFloat = 0
    /// How many points of scrolling fold the top (what it folds by).
    @ObservationIgnored var foldDistance: CGFloat = 1
    /// A heading at or above this line (in the list's space) is the one on top: just under the folded top.
    @ObservationIgnored var topLine: CGFloat = 80
    /// The top's height now (it shrinks as it folds).
    @ObservationIgnored var topHeight: CGFloat = 0
    @ObservationIgnored private var y: [Date: CGFloat] = [:]

    func scrolled(_ offset: CGFloat) {
        let now = min(max(offset / max(foldDistance, 1), 0), 1)
        if now != fold { fold = now }
    }

    func report(_ month: Date, y value: CGFloat) {
        y[month] = value
        settle()
    }

    /// A heading the list let go of (scrolled far off): its last place would otherwise stay, and after a scrub a month
    /// passed on the way kept the big dot at the "top" (seen on the sim: the 8th dot big under September).
    func forget(_ month: Date) {
        y[month] = nil
        settle()
    }

    private func settle() {
        let now = y.filter { $0.value <= topLine }.max { $0.value < $1.value }?.key
        if now != top { top = now }
    }
}

/// The top's part that folds (owner, 2026-10-17, option 1): the title and its line fold away and the number shrinks
/// (44 → 24 pt) as the list scrolls; the made-up line, the bar and the chips under it never move. Everything here folds
/// in step with the fold, so the top's bottom edge moves up exactly as far as the list scrolls (`by` reports how far).
private struct JourneyMakeUpHead: View {
    let missed: Int
    let words: String
    let scroll: JourneyMakeUpScroll
    /// How far it folds, in points: the title block, what the number loses, and the gap above it.
    let folds: (_ by: CGFloat) -> Void
    @State private var titles: CGFloat?
    @State private var number: CGSize?

    private static let size: CGFloat = 44
    private static let smallest: CGFloat = 24
    private static let gap: CGFloat = 14
    private static let gapFolded: CGFloat = 4
    /// The thin 44 pt number's descent, so the shrunk number keeps "prayers missed" on its baseline.
    private static let descent = abs(UIFont.systemFont(ofSize: size, weight: .thin).descender)

    var body: some View {
        let f = scroll.fold
        let scale = 1 - (1 - Self.smallest / Self.size) * f
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("To make up").font(.system(size: 34, weight: .light, design: .rounded))
                Text("Prayers left unmarked on days you used shukr.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titles = $0; report() }
            .opacity(max(0, 1 - f * 1.6))
            .frame(height: titles.map { $0 * (1 - f) }, alignment: .top)
            .clipped()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(missed)")
                    .font(.system(size: Self.size, weight: .thin, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(missed)))
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { number = $0; report() }
                    .scaleEffect(scale, anchor: .bottomLeading)
                    .frame(width: number.map { $0.width * scale }, height: number.map { $0.height * scale },
                           alignment: .bottomLeading)
                    .alignmentGuide(.firstTextBaseline) { d in d.height - Self.descent * scale }
                Text(words)
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Self.gap - (Self.gap - Self.gapFolded) * f)
            .animation(.snappy, value: missed)
        }
        .accessibilityElement(children: .combine)
    }

    private func report() {
        guard let titles, let number else { return }
        folds(titles + number.height * (1 - Self.smallest / Self.size) + Self.gap - Self.gapFolded)
    }
}

/// The bar's small "To make up", coming in as the big title folds away.
private struct JourneyMakeUpNavTitle: View {
    let scroll: JourneyMakeUpScroll

    var body: some View {
        Text("To make up")
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .opacity(max(0, scroll.fold - 0.5) * 2)
            .accessibilityHidden(scroll.fold < 0.5)
    }
}

/// The Zikr wheel's scrubber (owner: copy it, not the soft look): one dot per month down the right edge, the month at
/// the top of the list bigger, a month with nothing left in Journey's green (owner, 2026-10-17: "make it a green dot"); a
/// finger on them drags through the months (a tick each), a pill beside it naming the month. At rest the month on top is
/// named beside its dot ("Sep") and a year's first dot carries the year ("2025"). Its own view, so a drag redraws the dots
/// and not the page.
private struct JourneyMakeUpScrubber: View {
    let months: [Date]
    /// Months with nothing left.
    let cleared: Set<Date>
    let scroll: JourneyMakeUpScroll
    let proxy: ScrollViewProxy
    /// The month under the finger (its name shows beside it).
    @State private var scrubbing: Date?
    @Environment(\.colorScheme) private var scheme

    private let dotSlot: CGFloat = 14
    private let scrubberPad: CGFloat = 10

    var body: some View {
        let current = scrubbing ?? scroll.top ?? months.first
        VStack(spacing: 0) {
            ForEach(months.indices, id: \.self) { i in
                let m = months[i]
                let here = m == current
                Circle()
                    .fill(cleared.contains(m) ? JourneyTileColor.of(.metGoal, dark: scheme == .dark)
                          : Color.primary.opacity(here ? 0.55 : 0.18))
                    .frame(width: here ? 7 : 5, height: here ? 7 : 5)
                    .frame(width: 24, height: dotSlot)
                    .overlay(alignment: .trailing) {
                        if scrubbing == nil, let mark = mark(i, here: here) {
                            Text(mark)
                                .font(.system(size: 10, weight: here ? .regular : .light, design: .rounded))
                                .foregroundStyle(here ? .primary : .secondary)
                                .fixedSize()
                                .offset(x: -19)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
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

    /// Beside a dot at rest: the month on top ("Sep"), else the year where one starts ("2025"; the newest month's year
    /// only when it isn't this one).
    private func mark(_ i: Int, here: Bool) -> String? {
        let m = months[i]
        if here { return m.formatted(.dateTime.month(.abbreviated)) }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: m)
        let newer = i == 0 ? calendar.component(.year, from: Date()) : calendar.component(.year, from: months[i - 1])
        return year != newer ? String(year) : nil
    }
}

/// A row's control: an empty ring to tap; made up, it fills in ink with a ✓ (no sage on Journey).
private struct JourneyMakeUpCheck: View {
    let done: Bool
    @Environment(\.circleTheme) private var theme

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.primary.opacity(done ? 0 : 0.35), lineWidth: 1.3)
            Circle().fill(Color.primary.opacity(0.8))
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.surface)
                .scaleEffect(done ? 1 : 0.5)
                .opacity(done ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        .animation(.snappy(duration: 0.25), value: done)
    }
}

/// The list cleared: an ink check (no sage on Journey) that draws itself in, "All caught up", one line. Plays again each
/// time the last one is cleared here (`cleared` bumps); opening an already-empty list shows it at rest.
private struct JourneyCaughtUp: View {
    let cleared: Int
    let line: String
    @State private var drawn: CGFloat = 1
    @State private var pop: CGFloat = 1

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2)
                Circle().trim(from: 0, to: drawn).stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.8))
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
