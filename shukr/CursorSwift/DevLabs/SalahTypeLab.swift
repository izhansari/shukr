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
// The tuner (Aa, top right; up when the lab opens) moves the copy's type live; Copy puts the values on the clipboard. Once
// he picks, the values are written into the copy as plain numbers (no SalahType.v), so the diff reads as the design.
// Settings → My Dev Stuff → Salah type lab; DEBUG `-demoSalahTypeLab`. Delete this file once the real build lands.

struct SalahTypeLab: View {
    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.circleTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showDone = false
    /// The tuner's sheet, up when the lab opens.
    @State private var tuning = true
    @State private var detent: PresentationDetent = .fraction(0.42)
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

    /// The page moves up above the tuner's sheet, so the ring and the list stay in view while tuning.
    private func sheetHeight(_ screen: CGFloat) -> CGFloat {
        guard tuning else { return 0 }
        return detent == .height(64) ? 64 : detent == .large ? 0 : screen * 0.42
    }

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            LabPlace(city: viewModel.cityName ?? "Finding…")
            Spacer(minLength: 24)
            if let prayer = ringPrayer { LabRingFace(prayer: prayer, now: now) }
            Spacer(minLength: 24)
            VStack(spacing: theme.rowSpacing) {
                ForEach(shownRows, id: \.name) { LabPrayerRow(prayer: $0, now: now) }
            }
            .modifier(SalahLookCard())
            .frame(width: SalahType.v.listWidth)
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
        .padding(.bottom, max(sheetHeight(geo.size.height + geo.safeAreaInsets.bottom) - geo.safeAreaInsets.bottom - 24, 0))
        .animation(.smooth(duration: 0.3), value: sheetHeight(geo.size.height))
        .frame(maxWidth: .infinity)
        }
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.medium)).padding(12) }
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button { tuning = true } label: { Image(systemName: "textformat.size").font(.body.weight(.medium)).padding(12) }
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .sheet(isPresented: $tuning) { SalahTypeTunerSheet(detent: $detent) }
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
                        .font(.system(size: SalahType.v.ringIcon, weight: .light))
                    Text(prayer.name)
                        .salahType(SalahType.v.ringName, SalahType.v.ringNameWeight)
                }
                .foregroundStyle(upcoming ? Color.primary.opacity(0.55) : Color.primary)
                .overlay(alignment: .top) { NextTag(shown: upcoming, label: "next") }
                if current {
                    LabTimeLine(end: prayer.endTime, now: now)
                } else if upcoming {
                    Text("at \(shortTimePM(prayer.startTime))")
                        .salahType(SalahType.v.ringLine, SalahType.v.ringLineWeight, style: .subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("missed")
                        .salahType(SalahType.v.ringLine, SalahType.v.ringLineWeight, style: .subheadline)
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
            // The last hour's time left in the prayer name's colour and weight (light), not thin grey.
            .salahType(SalahType.v.ringLine, lastHour && SalahType.v.ringLineWeight == .thin ? .light : SalahType.v.ringLineWeight,
                       style: .subheadline)
            .foregroundStyle(lastHour ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
    }
}

// MARK: - The list's row (PrayerButton's body, at rest)

private struct LabPrayerRow: View {
    let prayer: LabPrayer
    let now: Date
    @Environment(\.circleTheme) private var theme
    @AppStorage(PrayerDotStyle.key) private var dotStyleRaw = PrayerDotStyle.muted.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var look: SalahLook { theme.list }
    private var isFuturePrayer: Bool { prayer.startTime > now }
    private var isCurrentPrayer: Bool { !isFuturePrayer && !prayer.isCompleted && prayer.endTime > now }

    private var nameFont: Font {
        switch look {
        case .dayNow: .body
        case .nowLeads: isCurrentPrayer ? .title3 : .subheadline
        default: .system(size: SalahType.scaled(SalahType.v.listName, .callout, dynamicTypeSize))
        }
    }
    private var nameWeight: Font.Weight { look == .prayedAt && !prayer.isCompleted ? .regular : SalahType.v.listNameWeight.value }
    private var timeFontSize: Font { .system(size: SalahType.scaled(SalahType.v.listTime, .footnote, dynamicTypeSize)) }
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
                .foregroundStyle(theme.emphasisesCurrentRow && isCurrentPrayer ? AnyShapeStyle(Color.primary)
                                 : AnyShapeStyle((SalahType.v.rowsInk ? Color.primary : Color.secondary).opacity(statusBasedOpacity * SalahType.v.restOpacity)))
                .fontDesign(SalahType.v.design.value)
                .fontWeight(nameWeight)
            if prayer.atMasjid {
                Image(systemName: "building.columns")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.sage)
            }

            Spacer()

            if look.raisesNow && isCurrentPrayer {
                LabTimeLeft(end: prayer.endTime, now: now, font: timeFontSize)
            } else {
                Text(shortTimePM(prayer.startTime))
                    .font(timeFontSize)
                    .foregroundColor(isCurrentPrayer ? .secondary : .secondary.opacity(statusBasedOpacity))
                    .fontDesign(SalahType.v.design.value)
                    .fontWeight(SalahType.v.listTimeWeight.value)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, theme.rowVerticalPadding + SalahType.v.rowExtra)
        // Journey's rows have hairlines between them.
        .overlay(alignment: .bottom) {
            if SalahType.v.hairlines && prayer.name != "Isha" {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 48).padding(.trailing, 16)
            }
        }
        .fontWidth(SalahType.v.width.value)
        .tracking(SalahType.v.tracking)
        .frame(minHeight: look == .raised ? SalahLook.raisedRowHeight : nil)
        .background { if isCurrentPrayer { SalahRowRaise(look: look) } }
    }
}

/// NowTimeLeft: grey, red from "30 min left" on.
private struct LabTimeLeft: View {
    let end: Date
    let now: Date
    var font: Font = .footnote
    var body: some View {
        Text(NowTimeLeft.left(until: end, from: now))
            .font(font).fontDesign(SalahType.v.design.value).fontWeight(SalahType.v.listTimeWeight.value)
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
        .salahType(SalahType.v.barSize, SalahType.v.barWeight, style: .caption1)
        .padding()
    }
}

// MARK: - The tuner (the lab only: what each knob moves is the design question)

/// The page's type values: the defaults are exactly today's look.
struct SalahTypeValues: Codable, Equatable {
    enum Design: String, Codable, CaseIterable {
        case rounded, standard, serif, mono
        var value: Font.Design {
            switch self {
            case .rounded: .rounded
            case .standard: .default
            case .serif: .serif
            case .mono: .monospaced
            }
        }
        var label: String { self == .standard ? "SF Pro" : self == .rounded ? "Rounded" : self == .serif ? "New York" : "Mono" }
    }
    enum Width: String, Codable, CaseIterable {
        case standard, condensed, expanded
        var value: Font.Width { self == .condensed ? .condensed : self == .expanded ? .expanded : .standard }
        var label: String { rawValue.capitalized }
    }
    enum Weight: String, Codable, CaseIterable {
        case thin, light, regular, medium, semibold
        var value: Font.Weight {
            switch self {
            case .thin: .thin
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
        var label: String { self == .regular ? "Reg" : self == .medium ? "Med" : self == .semibold ? "Semi" : rawValue.capitalized }
    }

    var design = Design.rounded
    var width = Width.standard
    var tracking: CGFloat = 0
    // The top bar's place ("Cary"): caption, thin.
    var barSize: CGFloat = 12
    var barWeight = Weight.thin
    // The ring: the prayer's name and symbol, the line under it ("ends 11:59 PM"; thin, light in its last hour).
    var ringName: CGFloat = 32
    var ringNameWeight = Weight.light
    var ringIcon: CGFloat = 22
    var ringLine: CGFloat = 15
    var ringLineWeight = Weight.thin
    // The list: names (callout), times (footnote), the rows not on now in grey or ink, the card's width, row air.
    var listName: CGFloat = 16
    var listNameWeight = Weight.light
    var listTime: CGFloat = 13
    var listTimeWeight = Weight.light
    var rowsInk = false
    var restOpacity: Double = 1
    var listWidth: CGFloat = 290
    var rowExtra: CGFloat = 0
    var hairlines = false

    static let now = SalahTypeValues()
    /// Today's, with the rows in ink (owner: "i think ink is good tho").
    static var ink: SalahTypeValues { var v = now; v.rowsInk = true; v.restOpacity = 0.6; return v }
    /// Journey's scale: 17 to read, 15 for times, 34 / 17 in the ring, light everywhere, Journey's 16 pt edges, hairlines.
    static var journey: SalahTypeValues {
        var v = ink
        v.barSize = 15; v.barWeight = .light
        v.ringName = 34; v.ringLine = 17; v.ringLineWeight = .light; v.ringIcon = 23
        v.listName = 17; v.listTime = 15
        v.listWidth = 370; v.rowExtra = 3; v.hairlines = true
        return v
    }
}

/// What the lab reads: the tuner's values.
@MainActor enum SalahType {
    static var v: SalahTypeValues { SalahTypeTuner.shared.v }
}

extension SalahType {
    /// A size set against a text style grows with the phone's text size as that style does (the page used `.subheadline`,
    /// `.callout`, `.footnote`, `.caption`: at the default size these are 15, 16, 13, 12); nil = a fixed size.
    static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle?, _ dts: DynamicTypeSize) -> CGFloat {
        guard let style else { return size }
        return UIFontMetrics(forTextStyle: style)
            .scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dts)))
    }
}

/// A size and weight in the page's typeface (the tuner's design, width and tracking), scaled as `style` scales.
struct SalahTypeText: ViewModifier {
    let size: CGFloat
    let weight: SalahTypeValues.Weight
    let style: UIFont.TextStyle?
    @Environment(\.dynamicTypeSize) private var dts
    func body(content: Content) -> some View {
        let v = SalahType.v
        content
            .font(.system(size: SalahType.scaled(size, style, dts), weight: weight.value, design: v.design.value))
            .fontWidth(v.width.value)
            .tracking(v.tracking)
    }
}

extension View {
    func salahType(_ size: CGFloat, _ weight: SalahTypeValues.Weight, style: UIFont.TextStyle? = nil) -> some View {
        modifier(SalahTypeText(size: size, weight: weight, style: style))
    }
}

@MainActor @Observable final class SalahTypeTuner {
    static let shared = SalahTypeTuner()
    private static let key = "salahTypeTuner.values"
    var v: SalahTypeValues { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(SalahTypeValues.self, from: data) { v = saved } else { v = .now }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(v) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
    /// The values as text, to paste into chat.
    var summary: String {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// The tuner's sheet: low enough to see the ring and the list while it's up (drag it down to a strip, up to tune).
struct SalahTypeTunerSheet: View {
    @Bindable private var tuner = SalahTypeTuner.shared
    @State private var copied = false
    @Binding var detent: PresentationDetent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Type").font(.headline)
                Spacer()
                preset("Now", .now)
                preset("Ink", .ink)
                preset("Journey", .journey)
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = tuner.summary
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            Form {
                Section("Typeface") {
                    Picker("Face", selection: $tuner.v.design) {
                        ForEach(SalahTypeValues.Design.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Width", selection: $tuner.v.width) {
                        ForEach(SalahTypeValues.Width.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    slider("Letter spacing", $tuner.v.tracking, -1...2, step: 0.1)
                }
                Section("Ring") {
                    slider("Name", $tuner.v.ringName, 24...44)
                    weight($tuner.v.ringNameWeight)
                    slider("Symbol", $tuner.v.ringIcon, 14...32)
                    slider("Line under it", $tuner.v.ringLine, 11...21)
                    weight($tuner.v.ringLineWeight)
                }
                Section("List") {
                    slider("Names", $tuner.v.listName, 13...21)
                    weight($tuner.v.listNameWeight)
                    slider("Times", $tuner.v.listTime, 11...19)
                    weight($tuner.v.listTimeWeight)
                    Toggle("Names in ink (not grey)", isOn: $tuner.v.rowsInk)
                    slider("Rows not on now", Binding(get: { CGFloat(tuner.v.restOpacity) }, set: { tuner.v.restOpacity = Double($0) }),
                           0.3...1, step: 0.05, unit: "")
                    slider("Card width", $tuner.v.listWidth, 240...380)
                    slider("Row air", $tuner.v.rowExtra, -6...16)
                    Toggle("Hairlines between rows", isOn: $tuner.v.hairlines)
                }
                Section("Top bar") {
                    slider("Place", $tuner.v.barSize, 10...17)
                    weight($tuner.v.barWeight)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .presentationDetents([.height(64), .fraction(0.42), .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled)
        .presentationBackground(.regularMaterial)
    }

    private func preset(_ title: String, _ values: SalahTypeValues) -> some View {
        Button(title) { withAnimation(.easeInOut(duration: 0.25)) { tuner.v = values } }
            .buttonStyle(.bordered).controlSize(.small)
            .tint(tuner.v == values ? .accentColor : .secondary)
    }
    private func slider(_ title: String, _ value: Binding<CGFloat>, _ range: ClosedRange<CGFloat>, step: CGFloat = 0.5,
                        unit: String = " pt") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.isEmpty ? String(format: "%.2f", value.wrappedValue) : String(format: "%g%@", value.wrappedValue, unit))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
    private func weight(_ value: Binding<SalahTypeValues.Weight>) -> some View {
        Picker("Weight", selection: value) {
            ForEach(SalahTypeValues.Weight.allCases, id: \.self) { Text($0.label).tag($0) }
        }.pickerStyle(.segmented)
    }
}
#endif
