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
    /// Today as it is, or pretend a prayer is on (the ones before it marked) — so the lab has rows at any hour.
    @State private var moment = "Asr"
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var real: [PrayerModel] {
        viewModel.orderedPrayerNames.compactMap { name in viewModel.todaysPrayers.first { $0.name == name } }
    }
    private var pretendIndex: Int? { real.firstIndex { $0.name == moment } }
    private var now: Date {
        guard let i = pretendIndex else { return clock }
        return real[i].startTime.addingTimeInterval(real[i].endTime.timeIntervalSince(real[i].startTime) * 0.4)
    }
    private var rows: [LabPrayer] {
        real.enumerated().map { i, p in
            guard let at = pretendIndex else { return LabPrayer(p) }
            let scores: [Double] = [100, 88, 72, 95, 64]
            return LabPrayer(p, completed: i < at, scoreColor: PrayerScoring.color(for: scores[i % scores.count]))
        }
    }
    /// The ring's prayer: the one on now, else the next to come, else the day's last.
    private var ringPrayer: LabPrayer? { rows.first { !$0.isCompleted && $0.endTime > now } ?? rows.last }
    private var doneCount: Int { rows.filter { $0.isCompleted && $0.startTime <= now }.count }
    private var shownRows: [LabPrayer] { showDone ? rows : rows.filter { !($0.isCompleted && $0.startTime <= now) } }

    var body: some View {
        VStack(spacing: 0) {
            LabPlace(city: viewModel.cityName ?? "Finding…")
            Spacer(minLength: 24)
            if let prayer = ringPrayer { LabRingFace(prayer: prayer, now: now) }
            Spacer(minLength: 24)
            VStack(spacing: theme.rowSpacing) {
                ForEach(shownRows, id: \.name) { LabPrayerRow(prayer: $0, now: now) }
            }
            .modifier(SalahLookCard())
            .frame(width: 290)
            if doneCount > 0 { LabDoneFooter(count: doneCount, open: $showDone).padding(.top, 8) }
            Spacer(minLength: 24)
            // The lab's own control (not part of the copy).
            Picker("Moment", selection: $moment) {
                Text("Live").tag("Live")
                ForEach(real.map(\.name), id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.medium)).padding(12) }
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .onReceive(Self.ticker) { clock = $0 }
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
    init(_ p: PrayerModel, completed: Bool? = nil, scoreColor: Color? = nil) {
        name = p.name
        displayName = p.displayName
        startTime = p.startTime
        endTime = p.endTime
        isCompleted = completed ?? p.isCompleted
        self.scoreColor = scoreColor ?? p.getColorForPrayerScore()
        atMasjid = completed == nil && p.atMasjid
    }
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

            if look.raisesNow && isCurrentPrayer {
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
