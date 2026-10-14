//
//  ListDragSandbox.swift
//  shukr
//
//  Settings → My Dev Stuff → Prayer list drag (sandbox) (owner, 2026-10-14: "perfect the interaction of swiping up the
//  prayer list … reacting with our finger … the same way it feels smooth when we scroll to the right or left"). A mock
//  of the three pages — Zikr · Salah · Settings — away from the real pager, so nothing in the app can break.
//
//  One gesture owns both axes: the first 6 pt pick the axis (as the app's pager does). Both axes move 1 : 1 with the
//  finger and, on release, spring to their rest from where they are WITH the finger's speed (`SpringDriver`, a display
//  link integrating a spring — a SwiftUI animation can't be caught mid-flight or handed a velocity in points), so a flick
//  carries through and a slow drag settles. A touch during a spring catches it where it is. "Today" mode copies the app:
//  nothing moves while dragging, the list animates after the finger lifts. DEBUG `-demoListSandbox`.
//
//  What we learned before (2026-10-04, "vertical live dragging", What's new topic salah-sheet; owner went back to
//  "gesture completion drag": "it doesn't feel right. idk how to describe it"): fast up-and-downs stalled (the drag
//  fought the pager's ScrollView — here one gesture owns both axes); the ends were walls (here a rubber band); 1 : 1 felt
//  off, he wanted 1.5–2× (here "List per finger", 1.5 by default); SwiftUI's scroll-target behaviour cut off the
//  let-go's animation (here a display link, no SwiftUI animation); and the list must leave faster than the ring moves so
//  the two never ghost over each other (here it travels ~3× the ring's distance and fades).
//

import SwiftUI
import QuartzCore

struct ListDragSandbox: View {
    enum Mode: String, CaseIterable { case follow = "Follows finger", today = "Today (after release)" }
    private enum Axis { case h, v }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// The pager: 0 Zikr · 1 Salah · 2 Settings (continuous while dragging / springing).
    @State private var pager = SpringDriver(1)
    /// The list: 0 closed · 1 open.
    @State private var list = SpringDriver(0)
    @State private var axis: Axis?
    @State private var start = 0.0
    @State private var mode = Mode.follow
    @State private var tuning = false
    // Tuning (the sliders): the spring and how far a flick throws.
    @State private var response = 0.42
    @State private var damping = 0.86
    @State private var projection = 0.18
    @State private var stretch = 0.25
    /// How far the list moves per point of finger (owner 2026-10-04: "1:1 with my finger … off; one unit up, the list 1.5
    /// or 2 units").
    @State private var ratio = 1.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let travel = h * 0.52   // finger distance for closed → open
            ZStack(alignment: .top) {
                SandboxColors.page(scheme).ignoresSafeArea()
                HStack(spacing: 0) {
                    zikrPage.frame(width: w, height: h)
                    salahPage(h: h).frame(width: w, height: h)
                    settingsPage.frame(width: w, height: h)
                }
                .offset(x: -pager.value * w)
                .frame(width: w, alignment: .leading)
                topBar
                dots.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
            }
            .contentShape(Rectangle())
            .gesture(drag(w: w, travel: travel))
        }
        .onAppear { applyTuning() }
        .onChange(of: response) { _, _ in applyTuning() }
        .onChange(of: damping) { _, _ in applyTuning() }
        .sheet(isPresented: $tuning) { tuner.presentationDetents([.medium]) }
        .statusBarHidden(false)
    }

    private func applyTuning() {
        for d in [pager, list] { d.response = response; d.dampingRatio = damping }
    }

    // MARK: The gesture

    private func drag(w: CGFloat, travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if axis == nil {
                    // The axis, once (the app's 6 pt lock). Vertical only on the Salah page.
                    let onSalah = abs(pager.value - 1) < 0.05
                    axis = abs(v.translation.height) > abs(v.translation.width) && onSalah ? .v : .h
                    if axis == .h { pager.stop(); start = pager.value } else { list.stop(); start = list.value }
                }
                switch axis {
                case .h:
                    pager.set(rubber(start - v.translation.width / w, low: 0, high: 2))
                case .v:
                    if mode == .follow { list.set(rubber(start - v.translation.height * ratio / travel, low: 0, high: 1)) }
                case nil: break
                }
            }
            .onEnded { v in
                defer { axis = nil }
                switch axis {
                case .h:
                    // Points per second → pages per second; one page at most per flick, as the real pager.
                    let speed = -v.velocity.width / w
                    let thrown = pager.value + speed * projection
                    let target = min(max((thrown).rounded(), max(start.rounded() - 1, 0)), min(start.rounded() + 1, 2))
                    pager.animate(to: target, velocity: speed)
                case .v:
                    let speed = -v.velocity.height * ratio / travel
                    if mode == .follow {
                        let target: Double = list.value + speed * projection > 0.5 ? 1 : 0
                        list.animate(to: target, velocity: speed)
                    } else {
                        // Today: the drag only decides; the list goes after the finger has lifted.
                        let up = v.translation.height < -30 || v.velocity.height < -300
                        let down = v.translation.height > 30 || v.velocity.height > 300
                        if up { list.animate(to: 1, velocity: 0) } else if down { list.animate(to: 0, velocity: 0) }
                    }
                case nil: break
                }
            }
    }

    /// Past an end the page or list moves less and less (as a scroll view's edge).
    private func rubber(_ x: Double, low: Double, high: Double) -> Double {
        func give(_ d: Double) -> Double { stretch * d / (d + stretch) }
        if x < low { return low - give(low - x) }
        if x > high { return high + give(x - high) }
        return x
    }

    // MARK: Pages

    private func salahPage(h: CGFloat) -> some View {
        let p = list.value
        let closedY = h * 0.40, openY = h * 0.17
        return ZStack(alignment: .top) {
            // The circle rises and shrinks as the list comes up (both follow `p`, so they move as one).
            SandboxRing(progress: 0.42)
                .scaleEffect(1 - 0.42 * min(max(p, 0), 1.1))
                .position(x: UIScreen.main.bounds.width / 2, y: closedY + (openY - closedY) * p)
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
                .opacity(1 - min(max(p, 0) * 3, 1))
                .position(x: UIScreen.main.bounds.width / 2, y: h - 70)
            SandboxList()
                .frame(height: h * 0.58)
                .offset(y: h * 0.34 + (1 - p) * h * 0.66)
                .opacity(min(max(p, 0) * 2.5, 1))
        }
    }

    private var zikrPage: some View {
        VStack(spacing: 18) {
            Spacer()
            ForEach(0..<3) { i in
                Circle().stroke(Color.primary.opacity(i == 1 ? 0.5 : 0.15), lineWidth: i == 1 ? 3 : 2)
                    .frame(width: i == 1 ? 150 : 80, height: i == 1 ? 150 : 80)
                    .overlay(Text(i == 1 ? "Subhanallah" : "").font(.system(.subheadline, design: .rounded)))
            }
            Spacer()
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 110)
            ForEach(["Location", "Method", "Madhab", "Qibla", "Excused Mode"], id: \.self) { row in
                HStack { Text(row); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    .padding(.horizontal, 18).frame(height: 50)
                Divider().padding(.leading, 18)
            }
            Spacer()
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.primary.opacity(0.04)).padding(.top, 100).padding(.bottom, 300))
        .padding(.horizontal, 16)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
            Text(["Zikr", "Salah", "Settings"][Int(min(max(pager.value.rounded(), 0), 2))])
                .font(.system(.headline, design: .rounded))
            Spacer()
            Button { tuning = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle().fill(Color.primary.opacity(abs(pager.value - Double(i)) < 0.5 ? 0.8 : 0.2)).frame(width: 7, height: 7)
            }
        }
    }

    private var tuner: some View {
        NavigationStack {
            Form {
                Picker("List", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                slider("List per finger (×)", $ratio, 1...2.5)
                slider("Spring (s)", $response, 0.2...0.9)
                slider("Damping", $damping, 0.5...1.0)
                slider("Flick throw (s)", $projection, 0...0.4)
                slider("Edge stretch", $stretch, 0.05...0.6)
                Button("Copy values") {
                    UIPasteboard.general.string = String(format: "ratio %.2f · response %.2f · damping %.2f · throw %.2f · stretch %.2f",
                                                         ratio, response, damping, projection, stretch)
                }
            }
            .navigationTitle("Tuning").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func slider(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Pieces

enum SandboxColors {
    static func page(_ s: ColorScheme) -> Color { s == .dark ? Color(white: 0.10) : Color(red: 0.890, green: 0.898, blue: 0.933) }
}

private struct SandboxRing: View {
    let progress: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LiftedSoftBand(width: 6, surface: SandboxColors.page(scheme), shade: WidgetSoft.shade(scheme), light: WidgetSoft.light(scheme))
            Circle().trim(from: 0, to: progress)
                .stroke(Color(red: 0.96, green: 0.77, blue: 0.20), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: "sun.haze").font(.system(size: 22, weight: .light))
                Text("Asr").font(.system(size: 38, weight: .light, design: .rounded))
                Text("1 hr 50 min left").font(.system(size: 14, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 230, height: 230)
    }
}

private struct SandboxList: View {
    @Environment(\.colorScheme) private var scheme
    private let rows: [(String, String, Bool)] = [("Fajr", "5:30 AM", true), ("Dhuhr", "1:10 PM", true),
                                                  ("Asr", "4:50 PM", false), ("Maghrib", "7:40 PM", false), ("Isha", "9:05 PM", false)]
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 10).padding(.bottom, 8)
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 14) {
                    Image(systemName: r.2 ? "checkmark.circle.fill" : "circle").foregroundStyle(r.2 ? Color.sage : .secondary)
                    Text(r.0).font(.system(.body, design: .rounded))
                    Spacer()
                    Text(r.1).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22).frame(height: 54)
            }
            Spacer(minLength: 0)
        }
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SandboxColors.page(scheme))
            .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.15), radius: 14, y: -4))
        .padding(.horizontal, 12)
    }
}

/// A value that follows the finger (`set`) and springs to rest from wherever it is with a velocity (`animate`), stepped
/// by a display link — so it can be caught mid-flight and keeps the finger's speed (a SwiftUI animation can do neither).
@MainActor @Observable final class SpringDriver {
    private(set) var value: Double
    @ObservationIgnored var response = 0.42
    @ObservationIgnored var dampingRatio = 0.86
    @ObservationIgnored private var velocity = 0.0
    @ObservationIgnored private var target = 0.0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0

    init(_ value: Double) { self.value = value; target = value }

    func set(_ v: Double) { stop(); value = v; target = v }
    func stop() { link?.invalidate(); link = nil; last = 0; velocity = 0 }

    func animate(to t: Double, velocity v: Double) {
        target = t; velocity = v
        guard link == nil else { return }
        let l = CADisplayLink(target: SpringTick(self), selector: #selector(SpringTick.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    fileprivate func step(_ now: CFTimeInterval) {
        let dt = last == 0 ? 1.0 / 120 : min(now - last, 1.0 / 30)
        last = now
        // A damped spring (mass 1): stiffness from the response, damping from the ratio; small steps keep it stable.
        let k = pow(2 * .pi / response, 2), c = 4 * .pi * dampingRatio / response
        var x = value, v = velocity
        let n = 4, h = dt / Double(n)
        for _ in 0..<n {
            v += (-k * (x - target) - c * v) * h
            x += v * h
        }
        velocity = v
        if abs(x - target) < 0.0005 && abs(v) < 0.01 { value = target; stop() } else { value = x }
    }
}

private final class SpringTick: NSObject {
    weak var driver: SpringDriver?
    init(_ d: SpringDriver) { driver = d }
    @MainActor @objc func tick(_ link: CADisplayLink) { driver?.step(link.timestamp) }
}
