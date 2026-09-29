//
//  MapLayerSheet.swift
//  shukr
//
//  The map's one sheet (owner, map-one-sheet, 2026-09-29 — "Option A"): while prayer spots or
//  mosques are showing, one sheet stays up. The user drags it between small / medium / large and
//  it keeps that height; a pin tap swaps what's inside with a quick cross-fade instead of closing
//  and reopening a sheet. Every page in it wears the same header (`MapSheetHeader`).
//

import SwiftUI
import MapKit

/// The sheet's height as it is on screen right now, for the controls that float above it. Its own
/// @Observable so only they re-render while the sheet is dragged, not the whole map screen.
@Observable final class SheetMetrics {
    var height: CGFloat = 0
}

/// Map controls that sit just above the layer sheet (Apple Maps style), or at the bottom when
/// there's none. At the large height they'd be off the top of what's left, so they fade.
struct AboveSheet<Content: View>: View {
    let metrics: SheetMetrics
    let sheetUp: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let h = sheetUp ? metrics.height : 0
        let screen = UIScreen.main.bounds.height
        VStack {
            Spacer()
            content
                .padding(.bottom, h > 0 ? max(h - 20, 0) : 0)   // the sheet stands on the safe area
                .opacity(h > screen * 0.6 ? 0 : 1)
        }
        .animation(.smooth(duration: 0.25), value: h > screen * 0.6)
    }
}

/// One header for every page in the map's sheet (prayer spots, a cluster, a prayer, mosques, a
/// mosque — owner: "ideally all sheets share the same header look"): an optional ‹ on the left,
/// the title in the app's light rounded type with one quiet line under it, the page's own
/// accessories, then ✕ (leave the layer, back to the qibla) on the far right.
struct MapSheetHeader<Leading: View, Trailing: View>: View {
    var back: (() -> Void)? = nil
    let title: String
    var subtitle: String? = nil
    var close: (() -> Void)? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let back {
                MapSheetCircleButton(symbol: "chevron.left", label: "Back", action: back)
            }
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            if let close {
                MapSheetCircleButton(symbol: "xmark", label: "Back to the qibla", action: close)
            }
        }
    }
}

extension MapSheetHeader where Leading == EmptyView {
    init(back: (() -> Void)? = nil, title: String, subtitle: String? = nil, close: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(back: back, title: title, subtitle: subtitle, close: close, leading: { EmptyView() }, trailing: trailing)
    }
}

extension MapSheetHeader where Leading == EmptyView, Trailing == EmptyView {
    init(back: (() -> Void)? = nil, title: String, subtitle: String? = nil, close: (() -> Void)? = nil) {
        self.init(back: back, title: title, subtitle: subtitle, close: close, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// The header's round buttons (‹, ✕, ☆): 36 pt, a faint fill.
struct MapSheetCircleButton: View {
    let symbol: String
    let label: String
    var tint: Color = .secondary
    var fill: Color = Color.primary.opacity(0.06)
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// How the content of the one sheet changes: the old page leaves quickly and the new one comes in
/// a beat later (a plain crossfade ghosted the two).
extension AnyTransition {
    static var layerPage: AnyTransition { .sheetContent(offset: 0) }
}

// MARK: - Prayer spots

/// Prayer spots' filters, in the sheet (they were a glass bar on the map): the range menu and the
/// five prayers as chips. With all shown none is lit; tap one = only it; tap more to add; tap the
/// last lit one = all again.
struct PrayerFilterRow: View {
    @ObservedObject var viewModel: LocationViewModel
    let custom: () -> Void

    private let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private var showingAll: Bool { viewModel.selectedPrayerNames == viewModel.defaultPrayerNames }

    private func toggle(_ name: String) {
        triggerSomeVibration(type: .light)
        var names = viewModel.selectedPrayerNames
        if showingAll { names = [name] }
        else if names.contains(name) { names.remove(name) }
        else { names.insert(name) }
        if names.isEmpty || names == viewModel.defaultPrayerNames { names = viewModel.defaultPrayerNames }
        withAnimation(.snappy(duration: 0.2)) { viewModel.selectedPrayerNames = names }
    }

    private var rangeTitle: String {
        switch viewModel.quickRange {
        case .allTime: "All time"
        case .thisWeek: "This week"
        case .last30: "30 days"
        case .thisYear: "This year"
        case .lastYear: "12 months"
        case .custom: "Custom"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Toggle(isOn: $viewModel.onlyAtMasjid) {
                    Label("Only at a masjid", systemImage: "building.columns")
                }
                Divider()
                ForEach(LocationViewModel.QuickRange.allCases) { range in
                    Button {
                        if range == .custom { custom() } else { viewModel.apply(range) }
                    } label: {
                        Label(range == .custom ? "Custom…" : range.rawValue, systemImage: range.symbol)
                    }
                }
            } label: {
                let lit = viewModel.quickRange != .allTime || viewModel.onlyAtMasjid
                HStack(spacing: 3) {
                    Text(rangeTitle).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(lit ? Color.green : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(lit ? Color.green.opacity(0.14) : Color.primary.opacity(0.06)))
                .contentShape(Capsule())
            }
            Spacer(minLength: 0)
            ForEach(order, id: \.self) { name in
                let lit = !showingAll && viewModel.selectedPrayerNames.contains(name)
                Button { toggle(name) } label: {
                    Image(systemName: prayerSymbol(name))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(lit ? Color.green : Color.primary.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(lit ? Color.green.opacity(0.16) : Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lit ? "\(name), shown" : name)
            }
        }
    }
}

/// The prayer-spots sheet's home: the header, the filters, and the prayers on the map right now,
/// newest first by day — the same list idea as the mosques'. A row opens that prayer's page.
struct PrayerSpotsHome: View {
    @ObservedObject var viewModel: LocationViewModel
    let collapsed: Bool
    let custom: () -> Void
    let close: () -> Void

    private var subtitle: String {
        let n = viewModel.visiblePrayerCount
        let count = n == 1 ? "1 in view" : "\(n) in view"
        guard viewModel.filtersActive else { return count }
        let filter = viewModel.filterSentence
            .replacingOccurrences(of: "Showing ", with: "")
            .replacingOccurrences(of: "prayers from ", with: "")
        return "\(count) · \(filter)"
    }

    private var days: [(date: Date, prayers: [PrayerModel])] {
        let cal = Calendar.current
        var order: [Date] = []; var byDay: [Date: [PrayerModel]] = [:]
        let newest = viewModel.visiblePrayers
            .sorted { ($0.timeAtComplete ?? $0.startTime) > ($1.timeAtComplete ?? $1.startTime) }
            .prefix(80)
        for p in newest {
            let day = cal.startOfDay(for: p.timeAtComplete ?? p.startTime)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(p)
        }
        return order.map { (date: $0, prayers: byDay[$0] ?? []) }
    }

    private func daySection(_ date: Date, _ prayers: [PrayerModel]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(zikrDayLabel(date))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(prayers.enumerated()), id: \.offset) { i, prayer in
                    row(prayer)
                    if i < prayers.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 14)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }

    private func row(_ prayer: PrayerModel) -> some View {
        Button { viewModel.open(prayer) } label: {
            HStack {
                PrayerSpotRow(prayer: prayer)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MapSheetHeader(title: "Prayer spots", subtitle: subtitle, close: close)
                        .id("top")
                    // Small is the header alone (like the mosques'); the filters would be cut in half.
                    PrayerFilterRow(viewModel: viewModel, custom: custom)
                        .opacity(collapsed ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: collapsed)
                    if days.isEmpty {
                        Text(viewModel.prayers.isEmpty
                             ? "Prayers you mark show up here, pinned where you prayed them."
                             : "No prayers in view. Move the map, or change the filters.")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 24)
                    }
                    ForEach(days, id: \.date) { day in
                        daySection(day.date, day.prayers)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            // Small: just the header, never rows sliding under it (as the mosques' sheet).
            .scrollDisabled(collapsed)
            .onChange(of: collapsed) { _, small in
                if small { withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        .fontDesign(.rounded)
    }
}
