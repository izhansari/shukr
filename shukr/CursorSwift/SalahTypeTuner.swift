//
//  SalahTypeTuner.swift
//  shukr
//
//  The Salah page's type, live (owner, 2026-10-17: "i dont like any of these... lets build the tuner in the meantime. idk
//  what i dont like about the salah list. i think ink is good tho. but i wanna see in the tuner"). DEBUG only: the palette
//  menu's "Type tuner…" opens a sheet over the real page — the typeface, the ring's words, the list's names, times, ink,
//  width and rows, the top bar's place — and every change shows at once. Copy puts the numbers on the clipboard to send.
//  Release builds read `SalahType.v`, today's values (the defaults below), so nothing changes there.
//

import SwiftUI

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

/// What the page reads: the tuner's values in DEBUG, today's in Release.
@MainActor enum SalahType {
    static var v: SalahTypeValues {
        #if DEBUG
        SalahTypeTuner.shared.v
        #else
        .now
        #endif
    }
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

#if DEBUG
@MainActor @Observable final class SalahTypeTuner {
    static let shared = SalahTypeTuner()
    private static let key = "salahTypeTuner.values"
    var v: SalahTypeValues { didSet { save() } }
    var open = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(SalahTypeValues.self, from: data) { v = saved } else { v = .now }
        if ProcessInfo.processInfo.arguments.contains("-demoTypeTuner") { open = true }
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
    @State private var detent: PresentationDetent = .fraction(0.42)

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

/// Presents the tuner's sheet from the palette (DEBUG); nothing in Release.
struct SalahTypeTunerHost: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content.sheet(isPresented: Binding(get: { SalahTypeTuner.shared.open }, set: { SalahTypeTuner.shared.open = $0 })) {
            SalahTypeTunerSheet()
        }
        #else
        content
        #endif
    }
}
