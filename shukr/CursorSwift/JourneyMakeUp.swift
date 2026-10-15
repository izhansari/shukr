import SwiftUI
import SwiftData

// To make up (Journey phase 2; spec screen 8, mock-up Missed5; decision journey-past-marks A): the prayers left unmarked
// on days shukr was used — an active day, one with a mark — so a break never lists its prayers. Made up = Qaza now. A row
// opens its prayer sheet (prayed it in time after all? set the time there; decision makeup-row-tap: kept for now).
// Round 2 (owner, 484 of them): the total and each prayer's count on top (a prayer filters the list), months as pinned
// headings with their totals ("12 left · 3 made up"), a month scrubber down the right edge; Made up keeps the row in place
// as "✓ Made up · Undo" for 3 s, then it folds into its own month's "Made up · N" (decision makeup-made-feedback A); a
// cleared list says "All caught up".

struct JourneyMakeUpPage: View {
    /// The month Journey was showing (the switch's left side).
    let month: Date
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @AppStorage("journey.makeUpAll") private var showAll = false
    @State private var open: [Entry] = []
    @State private var madeUp: [Entry] = []
    /// One prayer only (a tap on its count).
    @State private var only: String?
    /// Months whose "Made up · N" row is open.
    @State private var expanded: Set<Date> = []
    /// Just made up: still in place with Undo until its 3 s run out (the token tells a later tap from this one).
    @State private var settling: [PersistentIdentifier: UUID] = [:]
    @State private var sheetRow: PrayerModel?
    /// Bumps when the last one is cleared here (the "All caught up" moment plays).
    @State private var cleared = 0
    /// The month under the finger on the scrubber (its name shows beside it).
    @State private var scrubbing: Date?

    struct Entry: Identifiable {
        let row: PrayerModel
        let month: Date
        var id: PersistentIdentifier { row.persistentModelID }
    }

    // MARK: What's shown

    private func inScope(_ e: Entry) -> Bool { showAll || e.month == month }
    private func isSettling(_ e: Entry) -> Bool { settling[e.id] != nil }
    /// Open in the switch's scope (just-made-up ones included, in place).
    private var scopedOpen: [Entry] { open.filter(inScope) }
    private var shownOpen: [Entry] { scopedOpen.filter { only == nil || $0.row.name == only } }
    private var shownMade: [Entry] { madeUp.filter { inScope($0) && (only == nil || $0.row.name == only) } }
    /// The months on the page, newest first.
    private var months: [Date] {
        Array(Set(shownOpen.map(\.month) + shownMade.map(\.month))).sorted(by: >)
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
                            ForEach(shownOpen.filter { $0.month == m }) { entry in
                                row(entry)
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
                            }
                            madeUpRow(m)
                        } header: {
                            monthHeader(m).id(m)
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
                .padding(.trailing, scrubber ? 40 : 20)
                .padding(.bottom, 30)
            }
            .overlay(alignment: .trailing) {
                if scrubber { monthScrubber(months, proxy: proxy).padding(.trailing, 6) }
            }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetRow, onDismiss: { withAnimation(.easeInOut(duration: 0.35)) { load(celebrate: true) } }) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .onChange(of: showAll) { only = nil }
        .task { load() }
    }

    private var caughtUpLine: String {
        if let only { return "No \(only) left to make up." }
        return showAll ? "Every prayer on the days you used shukr is marked." : "Nothing left from \(monthName(month))."
    }

    // MARK: The top: the total, each prayer's count, the switch

    private func summary(_ left: [Entry]) -> some View {
        let counts = JourneyLog.names.map { name in (name, left.filter { $0.row.name == name }.count) }.filter { $0.1 > 0 }
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
                .padding(.top, 8)
            }
            JourneySwitch(options: [(monthName(month), "month"), ("All months", "all")],
                          selection: Binding(get: { showAll ? "all" : "month" }, set: { showAll = $0 == "all" }))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
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
        let row = entry.row
        let justMade = isSettling(entry)
        HStack(spacing: 12) {
            Button {
                triggerSomeVibration(type: .light)
                sheetRow = row
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if justMade {
                            Circle().fill(PrayerScoring.color(for: row.numberScore))
                        } else {
                            Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                        }
                    }
                    .frame(width: 8, height: 8)
                    nameAndDay(row).opacity(justMade ? 0.55 : 1)
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
                        undo(row)
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
                .transition(.opacity)
            }
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

    /// The month's made-up prayers, folded under its open ones (never at the page's bottom — owner).
    @ViewBuilder private func madeUpRow(_ m: Date) -> some View {
        let list = shownMade.filter { $0.month == m }
        if !list.isEmpty {
            let isOpen = expanded.contains(m)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isOpen { expanded.remove(m) } else { expanded.insert(m) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.system(size: 14, weight: .light))
                        Text("Made up · \(list.count)")
                            .font(.system(size: 14, weight: .light, design: .rounded))
                            .contentTransition(.numericText(value: Double(list.count)))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isOpen {
                    ForEach(list) { entry in
                        Button {
                            triggerSomeVibration(type: .light)
                            sheetRow = entry.row
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(PrayerScoring.color(for: entry.row.numberScore)).frame(width: 8, height: 8)
                                nameAndDay(entry.row).opacity(0.55)
                                Spacer(minLength: 8)
                                Text(madeUpWhen(entry.row))
                                    .font(.system(size: 13, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        }
    }

    /// "Qaza · today" / "Qaza · Oct 12".
    private func madeUpWhen(_ row: PrayerModel) -> String {
        guard let at = row.timeAtComplete else { return "Qaza" }
        return "Qaza · " + (Calendar.current.isDateInToday(at) ? "today" : at.formatted(.dateTime.month(.abbreviated).day()))
    }

    // MARK: The scrubber

    /// The months down the right edge, as Contacts' letters: a drag jumps month by month (a tick each), the month's name
    /// beside the finger.
    private func monthScrubber(_ months: [Date], proxy: ScrollViewProxy) -> some View {
        let step: CGFloat = months.count > 30 ? 11 : 16
        return VStack(spacing: 0) {
            ForEach(months, id: \.self) { m in
                Text(months.count > 30 ? "•" : m.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10, weight: scrubbing == m ? .bold : .medium, design: .rounded))
                    .foregroundStyle(scrubbing == m ? .primary : .secondary)
                    .frame(width: 30, height: step)
            }
        }
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(scrubbing == nil ? 0.03 : 0.07)))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let i = min(max(Int((value.location.y - 6) / step), 0), months.count - 1)
                    let m = months[i]
                    guard m != scrubbing else { return }
                    triggerSomeVibration(type: .light)
                    scrubbing = m
                    proxy.scrollTo(m, anchor: .top)
                }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrubbing = nil } }
        )
        .overlay(alignment: .topLeading) {
            // Beside the finger: the month in full, with its year.
            if let scrubbing, let i = months.firstIndex(of: scrubbing) {
                Text(scrubbing.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(.regularMaterial))
                    .fixedSize()
                    .alignmentGuide(.leading) { $0[.trailing] + 10 }
                    .alignmentGuide(.top) { _ in -(6 + step * (CGFloat(i) + 0.5) - 15) }
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Making up

    private func makeUp(_ row: PrayerModel) {
        guard viewModel.markFromJourney(row, at: Date()) else { return }
        let id = row.persistentModelID, token = UUID()
        withAnimation(.easeInOut(duration: 0.25)) { settling[id] = token }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard settling[id] == token else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                settling[id] = nil
                load(celebrate: true)
            }
        }
    }

    private func undo(_ row: PrayerModel) {
        triggerSomeVibration(type: .light)
        viewModel.unmarkFromJourney(row)
        withAnimation(.easeInOut(duration: 0.25)) {
            settling[row.persistentModelID] = nil
            load()
        }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
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

    /// `celebrate`: the side shown just went empty here — the caught-up moment plays (with a success buzz).
    private func load(celebrate: Bool = false) {
        let leftNow = { (list: [Entry]) in list.filter { self.inScope($0) && !self.isSettling($0) }.count }
        let before = leftNow(open)
        (open, madeUp) = Self.entries(context, keeping: Set(settling.keys))
        if celebrate, before > 0, leftNow(open) == 0, settling.isEmpty {
            cleared += 1
            triggerSomeVibration(type: .success)
        }
    }

    /// Open: unmarked prayers whose window has ended, on active days only, never an excused one — plus `keeping`, just made
    /// up and still shown in place. Made up: marked on a later prayer day than its own (the Made up button, or the sheet's
    /// default) — newest made up first.
    @MainActor static func entries(_ context: ModelContext, keeping: Set<PersistentIdentifier> = [], now: Date = Date())
        -> (open: [Entry], madeUp: [Entry]) {
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
