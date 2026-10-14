//
//  ListDragSandbox.swift
//  shukr
//
//  Settings → My Dev Stuff → Prayer list drag (sandbox) (owner, 2026-10-14: "perfect the interaction of swiping up the
//  prayer list … reacting with our finger … the same way it feels smooth when we scroll to the right or left"). A mock
//  of the three pages — Zikr · Salah · Settings — away from the real pager, so nothing in the app can break. The pieces
//  are the real ones where that's safe (owner: "using those components"): the prayer list (BottomSharedView), the Zikr
//  page and its task ring (ZikrPageView), Settings, the top bar's titles and the bottom bar — none taking a touch but
//  the bar, all on its own SharedStateClass. The Salah circle is the real track + arc (MainCircleView writes for real).
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

    /// Its own page state, so the bar's buttons and the wheel never move the real pager underneath.
    @State private var sandboxState = SharedStateClass()
    @Environment(\.circleTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bottomInset = geo.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                // The real backdrop's colours: the theme's page for Zikr and Salah, the grouped grey for Settings.
                HStack(spacing: 0) {
                    theme.backdrop.frame(width: w)
                    theme.backdrop.frame(width: w)
                    Color(scheme == .light ? .secondarySystemBackground : .systemBackground).frame(width: w)
                }
                .offset(x: -pager.value * w)
                .frame(width: w, alignment: .leading)
                .ignoresSafeArea()
                HStack(spacing: 0) {
                    zikrPage.frame(width: w, height: h)
                    salahPage(w: w, h: h, bottomInset: bottomInset).frame(width: w, height: h)
                    settingsPage.frame(width: w, height: h)
                }
                .offset(x: -pager.value * w)
                .frame(width: w, alignment: .leading)
                chrome(h: h).frame(width: w, height: h)
            }
            .contentShape(Rectangle())
            .gesture(drag(w: w, travel: CircleMotion.listTravel * 1.4))
        }
        .environment(sandboxState)
        .circleThemeRoot()
        .onAppear { applyTuning() }
        .onChange(of: response) { _, _ in applyTuning() }
        .onChange(of: damping) { _, _ in applyTuning() }
        // The real bottom bar's buttons set the page: the sandbox pager follows (and lands the same way).
        .onChange(of: sandboxState.horizontalPage) { _, page in
            let i = Self.index(page)
            if Double(i) != pager.value.rounded() || abs(pager.value - Double(i)) > 0.01 { pager.animate(to: Double(i), velocity: 0) }
        }
        .sheet(isPresented: $tuning) { tuner.presentationDetents([.medium]) }
    }

    private static func index(_ p: SharedStateClass.HorizontalPage) -> Int { p == .zikr ? 0 : p == .main ? 1 : 2 }
    private static func page(_ i: Int) -> SharedStateClass.HorizontalPage { i <= 0 ? .zikr : i == 1 ? .main : .settings }

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
                    let landed = Self.page(Int(target))
                    if sandboxState.horizontalPage != landed { sandboxState.horizontalPage = landed }
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

    // MARK: Pages (the real views where they're safe; never taking a touch — their buttons would really run)

    /// The real page's geometry (PrayerTimesView.poppingBody): closed, the 200 pt ring in the middle of the page above a
    /// 34 pt reserve; open, it rises ~150 pt and the list (290 pt wide) sits under it, above the bottom bar's 86 + 44 pt.
    /// The ring only moves, never scales; the list comes in from 200 pt below, fading (theme.listEntrance).
    private func salahPage(w: CGFloat, h: CGFloat, bottomInset: CGFloat) -> some View {
        let p = list.value
        let closedY = (h - 34) / 2, openY = (h - 34) / 2 - 150
        let listTop = openY + 100 + 26
        let listRoom = max(h + bottomInset - 130 - listTop, 120)
        return ZStack(alignment: .top) {
            SandboxRing()
                .position(x: w / 2, y: closedY + (openY - closedY) * p)
            PrayerTimesView.BottomSharedView(showDailyAyahView: .constant(false))
                .frame(maxHeight: listRoom, alignment: .top)
                .frame(width: w)
                .offset(y: listTop + (1 - p) * CircleMotion.listTravel)
                .opacity(min(max(p, 0) * 2, 1))
                .allowsHitTesting(false)
        }
    }

    private var zikrPage: some View {
        NavigationStack {
            ZikrPageView(showMantraSheetFromHomePage: .constant(false), showTasbeehPage: .constant(false))
                .toolbar(.hidden, for: .navigationBar)
                .background(theme.backdrop)
        }
        .allowsHitTesting(false)
    }

    private var settingsPage: some View {
        SettingsView(refetchOnLeave: false)
            .allowsHitTesting(false)
    }

    /// The real page's chrome (PagerChromeView, faded as ChromeFollow does): the top bar's two titles crossfading with the
    /// Zikr page, the chevron while the Salah list is closed, the bottom bar while it's open or on Zikr. ✕ and ⚙ sit where
    /// ☰ and the doors are.
    private func chrome(h: CGFloat) -> some View {
        let zikr = min(max(1 - pager.value, 0), 1)
        let open = min(max(list.value, 0), 1)
        let onSettings = min(max(pager.value - 1, 0), 1)
        return ZStack(alignment: .top) {
            ZStack {
                PrayerTimesView.ZikrPageTitle().opacity(zikr).offset(x: (1 - zikr) * -150)
                TopBar().opacity((1 - zikr) * (1 - onSettings)).offset(x: zikr * 150)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            HStack {
                corner("xmark") { dismiss() }
                Spacer()
                corner("slider.horizontal.3") { tuning = true }
            }
            .padding(.horizontal, 12).padding(.top, 10)
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
                    .opacity((1 - open) * (1 - zikr) * (1 - onSettings))
                    .padding(.bottom, 40)
            }
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                PrayerTimesView.CustomBottomBar()
                    .opacity(max(open * (1 - onSettings), zikr))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func corner(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
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

/// The Salah circle's look at its real size: the app's own soft track (`NeuRingTrack`, 200 pt) and a 6 pt arc, the name
/// and time as the circle sets them. Not MainCircleView itself: that needs the live prayers and really marks one on a
/// hold, plays the circle's moments (stealing them from the real circle) and starts location updates.
private struct SandboxRing: View {
    var body: some View {
        ZStack {
            NeuRingTrack()
            Circle().trim(from: 0, to: 0.42)
                .stroke(Color(red: 0.96, green: 0.77, blue: 0.20), style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
            VStack(spacing: 2) {
                Image(systemName: "sun.haze").font(.system(size: 20, weight: .light))
                Text("Asr").font(.system(size: 34, weight: .light, design: .rounded))
                Text("ends 7:40 PM").font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 230, height: 230)
        .allowsHitTesting(false)
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
