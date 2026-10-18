#if DEBUG
import SwiftUI

// The Salah page's type, in a lab (owner, 2026-10-18: "i want to quickly mock up the view in swift visuals with a copy of
// our code in its own page … we dont have fear of breaking the current code. but we have context of what will have to be
// modified cuz of the view changes we made").
//
// A copy of the parts the type refresh touches — the ring's face (MainCircleView), the list's rows (PrayerButton), the
// "N done" fold (SoftDoneFooter) and the top bar's place (TopBar) — drawn from today's real prayers, with none of their
// moments, gestures or state. The first commit of this file is the copy as it was; every later change is a design change,
// so `git diff <first commit> -- shukr/CursorSwift/DevLabs/SalahTypeLab.swift` is what the real build has to change. The shapes the
// refresh doesn't touch (the track, the arc, the dots, the raised band, the card) are the real views, reused.
// Settings → My Dev Stuff → Salah type lab; DEBUG `-demoSalahTypeLab`. Delete this file once the real build lands.

struct SalahTypeLab: View {
    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.circleTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showDone = false
    @State private var clock = Date()
    /// Today as it is, pretend a prayer is on (the ones before it marked), or the day's page (all five marked) — so the lab
    /// has rows at any hour.
    @State private var moment = UserDefaults.standard.string(forKey: "labMoment") ?? "Asr"   // `-labMoment Day`
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var real: [PrayerModel] {
        viewModel.orderedPrayerNames.compactMap { name in viewModel.todaysPrayers.first { $0.name == name } }
    }
    private var pretendIndex: Int? { moment == "Day" ? real.count : real.firstIndex { $0.name == moment } }
    private var now: Date {
        guard let i = pretendIndex else { return clock }
        if i >= real.count { return real.last.map { $0.endTime.addingTimeInterval(-60) } ?? clock }
        return real[i].startTime.addingTimeInterval(real[i].endTime.timeIntervalSince(real[i].startTime) * 0.4)
    }
    private var rows: [LabPrayer] {
        real.enumerated().map { i, p in
            guard let at = pretendIndex else { return LabPrayer(p) }
            // Pretend marks: where in each window, and its score (0…1, as PrayerScoring).
            let shares: [Double] = [0.1, 1.3, 0.75, 1.4, 0.05]
            let at_ = p.startTime.addingTimeInterval(p.endTime.timeIntervalSince(p.startTime) * shares[i % shares.count])
            let score = PrayerScoring.score(start: p.startTime, end: p.endTime, markedAt: at_)
            return LabPrayer(p, completed: i < at, prayedAt: at_, score: score)
        }
    }
    /// The ring's prayer: the one on now, else the next to come, else the day's last.
    private var ringPrayer: LabPrayer? { rows.first { !$0.isCompleted && $0.endTime > now } ?? rows.last }
    private var doneCount: Int { rows.filter { $0.isCompleted && $0.startTime <= now }.count }
    private var shownRows: [LabPrayer] { showDone || dayDone ? rows : rows.filter { !($0.isCompleted && $0.startTime <= now) } }
    /// All five marked: the day's page (the ring holds the day, every row shows when it was prayed).
    private var dayDone: Bool { !rows.isEmpty && rows.allSatisfy(\.isCompleted) }
    private var dayScore: Double {
        guard pretendIndex != nil else { return viewModel.todaysScore }
        return rows.compactMap(\.score).reduce(0, +) / Double(max(rows.count, 1))
    }

    /// The list up (the real page's `navPosition == .bottom`): a swipe up opens it, a swipe down closes it.
    @State private var open = true
    /// The real page's numbers (PrayerTimesView): the bar's 86 pt, the soft looks' 44 pt for "N done" over it, the closed
    /// page's home-indicator reserve, 12 pt at least between the ring and the list, 16…44 pt under the list.
    private let bottomChromeHeight: CGFloat = 86
    private let closedBottomReserve: CGFloat = 34
    private let ringListMin: CGFloat = 12
    private let listBottomGap: ClosedRange<CGFloat> = 16...44

    private var momentTitle: String {
        moment == "Live" ? "Live" : moment == "Day" ? "Day ring" : "\(moment) on"
    }

    var body: some View {
        page
            .coordinateSpace(.named("lab"))
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)   // the pager ignores the bottom safe area, as the real page
            .background(theme.surface.ignoresSafeArea())
            // The chrome: the top bar's place, "N done" over the bottom bar, the bar.
            .overlay(alignment: .top) { LabPlace(city: viewModel.cityName ?? "Finding…") }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Over the bar, as the chrome's ZStack(alignment: .bottom) puts them.
                    if open && doneCount > 0 && !dayDone {
                        LabDoneFooter(count: doneCount, open: $showDone)
                    } else if open && dayDone {
                        LabJourneyLink()
                    }
                    Color.clear.frame(height: 13)   // measured: the real footer sits 13 pt over the bar's line
                    LabBottomBar().frame(height: bottomChromeHeight)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.medium)).padding(12) }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            // The lab's own control (not part of the copy): which state to show.
            .overlay(alignment: .topTrailing) {
                Menu {
                    Picker("State", selection: $moment) {
                        Text("Live").tag("Live")
                        ForEach(real.map(\.name), id: \.self) { Text("\($0) on").tag($0) }
                        Text("Day ring").tag("Day")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(momentTitle)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .foregroundStyle(.primary)
                .padding(.trailing, 12)
                .padding(.top, 6)
            }
            .contentShape(Rectangle())
            // The real page's swipe: past 30 pt up opens the list, down closes it (the pop — the finger never drags it).
            .gesture(DragGesture(minimumDistance: 6).onEnded { value in
                withAnimation(CircleMotion.page) {
                    if value.translation.height < -30, !open { open = true; triggerSomeVibration(type: .light) }
                    if value.translation.height > 30, open { open = false; triggerSomeVibration(type: .light) }
                }
            })
            .onReceive(Self.ticker) { clock = $0 }
    }

    /// PrayerTimesView's `poppingBody` (whose layout the real page's resting places are measured from, `restGhosts`): the
    /// page runs from the top safe area to the screen's bottom (the top bar is drawn over it). Closed: the ring centred
    /// over the home indicator's 34 pt. Open: three spacers over the ring (its 200 pt box), two under it (12 pt at least
    /// each), the list, a gap that gives a quarter of every point the list grows past two rows (16…44 pt), then the bar's
    /// 86 pt + 44 pt for "N done" / the Journey link.
    private var page: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if open {
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            face
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("lab")).midY } action: { ringMidY = $0 }
            Spacer(minLength: open ? ringListMin : 0)
            if open {
                Spacer(minLength: ringListMin)
                VStack(spacing: theme.rowSpacing) {
                    ForEach(shownRows, id: \.name) { LabPrayerRow(prayer: $0, now: now, dayPage: dayDone) }
                }
                .modifier(SalahLookCard())
                .frame(width: 290)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("lab")) } action: { listFrame = $0 }
                .transition(theme.listEntrance)
                Color.clear.frame(height: listGap)
            }
            Color.clear.frame(height: open ? bottomChromeHeight + theme.listFooterRoom : closedBottomReserve)
        }
        .animation(CircleMotion.page, value: open)
        .animation(CircleMotion.spring, value: showDone)
    }

    @State private var ringMidY: CGFloat = 0
    @State private var lineHeight: CGFloat = 17
    @State private var listFrame: CGRect = .zero
    /// The gap under the open list: 44 pt with two rows, giving up a quarter of every point the list grows, never below 16.
    private var listGap: CGFloat {
        let grown = max(listFrame.height - 2 * SalahLook.raisedRowHeight, 0)
        return min(max(listBottomGap.upperBound - grown * 0.25, listBottomGap.lowerBound), listBottomGap.upperBound)
    }

    @ViewBuilder private var face: some View {
        if dayDone && open {
            // The day's page: the score side (all five marked, the list open).
            LabDayFace(day: rows.map(\.dayPrayer), score: dayScore)
                .overlay(alignment: .top) {
                    // The day's line (DayInsight's; a sample here), drawn over the layout: centred in the room between
                    // the ring and the list (106 = the ring's radius + band), 12 pt under the ring at least.
                    let gap = listFrame.minY - ringMidY - 106
                    Text("This week: 31 of 35 prayers in their time.")
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
                        .frame(width: 310)
                        .offset(y: 206 + max((max(gap, 0) - lineHeight) / 2, 12))
                }
        } else if let prayer = ringPrayer {
            LabRingFace(prayer: prayer, now: now)
        }
    }
}

/// MemoriesFooterLink at rest: the day page's "Journey ›" in "N done"'s place.
private struct LabJourneyLink: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                .font(.system(size: 12, weight: .light))
            Text("Journey")
                .font(.system(size: 13, weight: .light, design: .rounded))
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).opacity(0.6))
        .padding(.vertical, 2)
    }
}

/// The bottom bar (PagerChromeView's): Zikr · Salah · Journey, a hairline over it. A stand-in for where it sits.
private struct LabBottomBar: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            HStack {
                ForEach(["Zikr", "Salah", "Journey"], id: \.self) { name in
                    Text(name)
                        .font(.caption).fontDesign(.rounded)
                        .foregroundStyle(name == "Salah" ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
    }
}

/// A prayer as the lab draws it: the real row's values, or a pretend mark.
struct LabPrayer {
    let name: String
    let displayName: String
    let startTime: Date
    let endTime: Date
    let isCompleted: Bool
    let scoreColor: Color
    let atMasjid: Bool
    let prayedAt: Date?
    let score: Double?
    init(_ p: PrayerModel, completed: Bool? = nil, prayedAt: Date? = nil, score: Double? = nil) {
        name = p.name
        displayName = p.displayName
        startTime = p.startTime
        endTime = p.endTime
        isCompleted = completed ?? p.isCompleted
        self.scoreColor = score.map { PrayerScoring.color(for: $0) } ?? p.getColorForPrayerScore()
        atMasjid = completed == nil && p.atMasjid
        self.prayedAt = isCompleted ? (prayedAt ?? p.timeAtComplete) : nil
        self.score = isCompleted ? (score ?? p.numberScore) : nil
    }
    var dayPrayer: DayPrayer { DayPrayer(name: name, start: startTime, end: endTime, markedAt: prayedAt, score: score) }
    /// "Perfect · 100" (the row's dayRowSummary).
    var summary: String { score.map { PrayerScoring.summary(for: $0) } ?? "Missed" }
}

// MARK: - The ring's face (MainCircleView's inner content, its `shownPrayer` branch)

private struct LabRingFace: View {
    let prayer: LabPrayer
    let now: Date
    @Environment(\.circleTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var upcoming: Bool { prayer.startTime > now }
    private var current: Bool { !upcoming && !prayer.isCompleted && prayer.endTime > now }
    private var progress: Double {
        if upcoming { return 0 }
        guard current else { return 1 }
        return max(now.timeIntervalSince(prayer.startTime) / prayer.endTime.timeIntervalSince(prayer.startTime), 0)
    }
    private var score: Double { PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: now) }
    private var progressColor: Color { progress >= 1 ? .clear : PrayerScoring.color(for: score) }

    var body: some View {
        ZStack {
            if theme.track.lifted { NeuRingTrack(solid: upcoming ? 0 : 1) }
            CircleTrack(solid: upcoming ? 0 : 1, band: !theme.track.lifted)
            let perfectNow = theme.arc.alivePerfect && progress > 0 && progress < 1 && PrayerScoring.grade(for: score) == .perfect
            if perfectNow {
                AliveRingFill(dark: colorScheme == .dark, tuning: .fine, tag: "salah type lab")
                    .frame(width: 230, height: 230)
                    .mask {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                    }
                    .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 6)
            }
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap))
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
                .shadow(color: progressColor.opacity(theme.arc.glow), radius: 6)
                .opacity(perfectNow ? 0 : 1)

            VStack {
                // Same type as the Insights ring: large, light, rounded.
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: prayerIcon(for: prayer.name))
                        .font(.system(size: 22, weight: .light))
                    Text(prayer.name)
                        .font(.system(size: 32, weight: .light, design: .rounded))
                }
                .foregroundStyle(upcoming ? Color.primary.opacity(0.55) : Color.primary)
                .overlay(alignment: .top) { NextTag(shown: upcoming, label: "next") }
                if current {
                    LabTimeLine(end: prayer.endTime, now: now)
                } else if upcoming {
                    Text("at \(shortTimePM(prayer.startTime))")
                        .font(.subheadline)
                        .fontDesign(.rounded)
                        .fontWeight(.thin)
                        .foregroundStyle(.secondary)
                } else {
                    Text("missed")
                        .font(.subheadline)
                        .fontDesign(.rounded)
                        .fontWeight(.thin)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 200, height: 200)
    }
}

/// The day's page in the ring (summaryCircle's score side): the raised disc, the score, the day's fifths.
private struct LabDayFace: View {
    let day: [DayPrayer]
    let score: Double
    @Environment(\.circleTheme) private var theme
    var body: some View {
        ZStack {
            if theme.track.lifted {
                NeuLiftCard(shape: Circle(), lift: 1)
                    .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
                    .frame(width: 200, height: 200)
            }
            DayCentre(day: day, score: score, picked: nil, yesterday: false)
            DayRing(day: day, picked: nil) { _ in }
        }
        .frame(width: 200, height: 200)
    }
}

/// PrayerTimeLine at rest: "ends 4:12 PM", the time left in its last hour.
private struct LabTimeLine: View {
    let end: Date
    let now: Date
    private var lastHour: Bool { end.timeIntervalSince(now) <= 60 * 60 }

    var body: some View {
        Text(lastHour ? timeLeftString(from: end.timeIntervalSince(now)) : "ends \(shortTimePM(end))")
            .font(.subheadline)
            .fontDesign(.rounded)
            // The last hour's time left in the prayer name's colour and weight (light), not thin grey.
            .fontWeight(lastHour ? .light : .thin)
            .foregroundStyle(lastHour ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
    }
}

// MARK: - The list's row (PrayerButton's body, at rest)

private struct LabPrayerRow: View {
    let prayer: LabPrayer
    let now: Date
    /// The day's page: a marked row shows when it was prayed and its score (DayRowTime).
    var dayPage = false
    @Environment(\.circleTheme) private var theme
    @AppStorage(PrayerDotStyle.key) private var dotStyleRaw = PrayerDotStyle.muted.rawValue

    private var look: SalahLook { theme.list }
    private var isFuturePrayer: Bool { prayer.startTime > now }
    private var isCurrentPrayer: Bool { !isFuturePrayer && !prayer.isCompleted && prayer.endTime > now }

    private var nameFont: Font {
        switch look {
        case .dayNow: .body
        case .nowLeads: isCurrentPrayer ? .title3 : .subheadline
        default: .callout
        }
    }
    private var nameWeight: Font.Weight { look == .prayedAt && !prayer.isCompleted ? .regular : .light }
    private var timeFontSize: Font { .footnote }
    private var statusBasedOpacity: Double {
        if isFuturePrayer { return 0.6 }
        if [.now, .dayNow, .nowLeads].contains(look) && prayer.isCompleted { return 0.55 }
        return 1
    }

    var body: some View {
        HStack {
            PrayerStatusDot(style: PrayerDotStyle(rawValue: dotStyleRaw) ?? .muted,
                            done: prayer.isCompleted && !isFuturePrayer,
                            future: isFuturePrayer,
                            scoreColor: prayer.scoreColor,
                            pulse: 0,
                            excused: Excused.covers(start: prayer.startTime, end: prayer.endTime))
                .frame(width: 24, height: 24, alignment: .leading)

            Text(prayer.displayName)
                .fixedSize()
                .layoutPriority(1)
                .font(nameFont)
                .foregroundStyle(theme.emphasisesCurrentRow && isCurrentPrayer ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(statusBasedOpacity)))
                .fontDesign(.rounded)
                .fontWeight(nameWeight)
            if prayer.atMasjid {
                Image(systemName: "building.columns")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.sage)
            }

            Spacer()

            if dayPage, let prayedAt = prayer.prayedAt {
                LabDayRowTime(prayedAt: prayedAt, summary: prayer.summary)
            } else if look.raisesNow && isCurrentPrayer {
                LabTimeLeft(end: prayer.endTime, now: now)
            } else {
                Text(shortTimePM(prayer.startTime))
                    .font(timeFontSize)
                    .foregroundColor(isCurrentPrayer ? .secondary : .secondary.opacity(statusBasedOpacity))
                    .fontDesign(.rounded)
                    .fontWeight(.light)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, theme.rowVerticalPadding)
        .frame(minHeight: look == .raised ? SalahLook.raisedRowHeight : nil)
        .background { if isCurrentPrayer { SalahRowRaise(look: look) } }
    }
}

/// DayRowTime: "@ 6:39 AM" over "Perfect · 100".
private struct LabDayRowTime: View {
    let prayedAt: Date
    let summary: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("@ \(shortTimePM(prayedAt))")
                .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.caption2).fontDesign(.rounded).fontWeight(.light)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .monospacedDigit()
    }
}

/// NowTimeLeft: grey, red from "30 min left" on.
private struct LabTimeLeft: View {
    let end: Date
    let now: Date
    var body: some View {
        Text(NowTimeLeft.left(until: end, from: now))
            .font(.footnote).fontDesign(.rounded).fontWeight(.light)
            .foregroundStyle(end.timeIntervalSince(now) < 31 * 60
                             ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(Color.secondary))
            .monospacedDigit()
    }
}

// MARK: - "N done" (SoftDoneFooter) and the top bar's place (TopBar)

private struct LabDoneFooter: View {
    let count: Int
    @Binding var open: Bool
    var body: some View {
        Button {
            withAnimation(CircleMotion.spring) { open.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                Text("\(count) done")
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.light)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LabPlace: View {
    let city: String
    var body: some View {
        HStack {
            Image(systemName: "location.fill")
                .foregroundColor(.secondary)
            Text(city)
        }
        .frame(height: 24, alignment: .center)
        .font(.caption)
        .fontDesign(.rounded)
        .fontWeight(.thin)
        .padding()
    }
}
#endif
