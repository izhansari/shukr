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
//  The pager is the app's own kind (a paging ScrollView); the list's vertical drag moves it with the finger and, on
//  release, springs to its rest from where it is WITH the finger's speed (`SpringDriver`, a display link integrating a
//  spring — a SwiftUI animation can't be caught mid-flight or handed a velocity in points). "Today" mode copies the app:
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
    enum Axis { case h, v }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    /// The pager's position (0 Zikr · 1 Salah · 2 Settings), mirrored from the real paging ScrollView's offset each frame
    /// (only for the chrome's fades — the scroll view moves the pages itself, as the app's does).
    @State private var pager = SpringDriver(1)
    /// The list: 0 closed · 1 open.
    @State private var list = SpringDriver(0)
    @State private var pageID: Int? = 1
    /// The drag's axis and start, in a plain object: as @State, setting them at a drag's first move rebuilt the whole
    /// Salah page — the real list included — and dropped a frame at the start of nearly every drag (his phone's log,
    /// 2026-10-14: 126 late of 1,883 drag frames, almost all the first).
    @State private var track = DragTrack()
    @State private var flickDecides = true
    @State private var mode = Mode.follow
    @State private var tuning = false
    @State private var showMeter = true
    /// The real page's rests, measured from the same layout it uses (closed ring, open ring, open list top).
    @State private var rests = Rests()
    @State private var pan = PanLock()
    @State private var meter = FrameMeter()
    /// Its own page state, so the bar's buttons and the wheel never move the real pager underneath.
    @State private var sandboxState = SharedStateClass()
    // Tuning (the sliders).
    @State private var response = 0.20
    @State private var damping = 1.0
    @State private var projection = 0.03
    @State private var stretch = 0.16
    /// How far the list moves per point of finger. Defaults = his phone's pick (2026-10-14: "interactive while being calm
    /// and not too hyper"): ratio 1.13, response 0.20, damping 1.00, throw 0.03, stretch 0.16.
    @State private var ratio = 1.13

    final class DragTrack { var axis: Axis?; var start = 0.0 }
    struct Rests: Equatable { var closedY: CGFloat = 0; var openY: CGFloat = 0; var listTop: CGFloat = 0; var height: CGFloat = 0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                // The real pager: a paging ScrollView (PrayerTimesView's), its pan switched off in UIKit while the list
                // drags (PagerPanLock: as .scrollDisabled each switch cost a frame).
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        SandboxZikrPage().frame(width: w).id(0)
                        salahPage(w: w).frame(width: w).id(1)
                        SandboxSettingsPage().equatable().frame(width: w).id(2)
                    }
                    .scrollTargetLayout()
                    .background(PanLockFinder(lock: pan))
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageID)
                .defaultScrollAnchor(.center)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Double.self) { g in
                    g.contentOffset.x / max(g.containerSize.width, 1)
                } action: { _, x in pager.set(x) }
                .ignoresSafeArea(edges: .bottom)
                .simultaneousGesture(drag)
                chrome.frame(width: w)
                if showMeter { meterView }
            }
        }
        .environment(sandboxState)
        .circleThemeRoot()
        .onAppear {
            applyTuning()
            meter.phase = { [pan, list, pager] in
                if pan.locked { return "list drag" }
                if list.isAnimating { return "list spring" }
                return pager.isMoving ? "paging" : nil
            }
            meter.start()
        }
        .onDisappear { meter.stop() }
        .onChange(of: response) { _, _ in applyTuning() }
        .onChange(of: damping) { _, _ in applyTuning() }
        // The real bottom bar's buttons set the page; the pager follows (as onChange(horizontalPage) does in the app).
        .onChange(of: sandboxState.horizontalPage) { _, page in
            let i = page == .zikr ? 0 : page == .main ? 1 : 2
            if pageID != i { withAnimation(CircleMotion.page) { pageID = i } }
        }
        .onChange(of: pageID) { _, i in
            let page: SharedStateClass.HorizontalPage = i == 0 ? .zikr : i == 2 ? .journey : .main
            if sandboxState.horizontalPage != page { sandboxState.horizontalPage = page }
        }
        .sheet(isPresented: $tuning) { tuner.presentationDetents([.medium]) }
    }

    private func applyTuning() { list.response = response; list.dampingRatio = damping }

    // MARK: The list's drag (vertical only, on Salah; the pager owns horizontal)

    /// The list's own travel: from just under the screen's bottom edge to its open top.
    private var listTravel: CGFloat { max(rests.height - rests.listTop, 1) }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { v in
                if track.axis == nil {
                    guard max(abs(v.translation.width), abs(v.translation.height)) >= 6 else { return }   // the app's 6 pt lock
                    let onSalah = pageID == 1 && abs(pager.value - 1) < 0.02
                    track.axis = abs(v.translation.height) > abs(v.translation.width) && onSalah ? .v : .h
                    if track.axis == .v { pan.locked = true; list.stop(); track.start = list.value }
                }
                guard track.axis == .v, mode == .follow else { return }
                // The list moves `ratio` × the finger; the ring follows the same progress.
                list.set(rubber(track.start - v.translation.height * ratio / listTravel))
            }
            .onEnded { v in
                defer { track.axis = nil; pan.locked = false }
                guard track.axis == .v else { return }
                if mode == .follow {
                    let speed = -v.velocity.height * ratio / listTravel
                    // A clearly fast flick decides by its direction (as an iOS sheet does); slower, where it was let go.
                    let target: Double
                    if flickDecides && abs(v.velocity.height) > 500 { target = v.velocity.height < 0 ? 1 : 0 }
                    else { target = list.value + speed * projection > 0.5 ? 1 : 0 }
                    list.animate(to: target, velocity: speed)
                } else {
                    // Today: the drag only decides; the list goes once the finger has lifted.
                    let up = v.translation.height < -30 || v.velocity.height < -300
                    let down = v.translation.height > 30 || v.velocity.height > 300
                    if up { list.animate(to: 1, velocity: 0) } else if down { list.animate(to: 0, velocity: 0) }
                }
            }
    }

    /// Past an end the list moves less and less (a scroll view's edge).
    private func rubber(_ x: Double) -> Double {
        func give(_ d: Double) -> Double { stretch * d / (d + stretch) }
        if x < 0 { return -give(-x) }
        if x > 1 { return 1 + give(x - 1) }
        return x
    }

    // MARK: The Salah page

    /// Laid out as the real page lays itself out (PrayerTimesView.poppingBody): closed, Spacer / circle / Spacer / 34;
    /// open, 3 Spacers / circle / 2 Spacers / list / Spacer / 86 + 44 — measured once by invisible copies (the real
    /// page's `restGhosts`), then the ring and list only move between those rests.
    private func salahPage(w: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ghosts
            Follows(list, offset: { p in CGSize(width: 0, height: rests.closedY + (rests.openY - rests.closedY) * p - 115) }) {
                SandboxRing().frame(maxWidth: .infinity)
            }
            Follows(list, offset: { p in CGSize(width: 0, height: rests.listTop + (1 - p) * (rests.height - rests.listTop)) }) {
                PrayerTimesView.BottomSharedView(showDailyAyahView: .constant(false))
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .compositingGroup()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.backdrop)
        .coordinateSpace(.named("salah"))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rests.height = $0 }
    }

    private var ghosts: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.clear.frame(width: 230, height: 230)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("salah")).midY } action: { rests.closedY = $0 }
                Spacer(minLength: 0)
                Color.clear.frame(height: 34)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0); Spacer(minLength: 0); Spacer(minLength: 0)
                Color.clear.frame(width: 230, height: 230)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("salah")).midY } action: { rests.openY = $0 }
                Spacer(minLength: 0); Spacer(minLength: 0)
                PrayerTimesView.BottomSharedView(showDailyAyahView: .constant(false))
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("salah")).minY } action: { rests.listTop = $0 }
                Spacer(minLength: 0)
                Color.clear.frame(height: 86 + theme.listFooterRoom)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Chrome (PagerChromeView, faded as ChromeFollow does)

    private var chrome: some View {
        ZStack(alignment: .top) {
            ZStack {
                Follows2(pager, list, offset: { pg, _ in CGSize(width: (1 - zikr(pg)) * -150, height: 0) },
                         opacity: { pg, _ in zikr(pg) }) { PrayerTimesView.ZikrPageTitle() }
                Follows2(pager, list, offset: { pg, _ in CGSize(width: zikr(pg) * 150, height: 0) },
                         opacity: { pg, _ in (1 - zikr(pg)) * (1 - onSettings(pg)) }) { TopBar() }
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
                Follows2(pager, list, opacity: { pg, p in (1 - open(p)) * (1 - zikr(pg)) * (1 - onSettings(pg)) }) {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 40)
            }
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                Follows2(pager, list, opacity: { pg, p in max(open(p) * (1 - onSettings(pg)), zikr(pg)) }) {
                    PrayerTimesView.CustomBottomBar()
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func zikr(_ pg: Double) -> Double { min(max(1 - pg, 0), 1) }
    private func onSettings(_ pg: Double) -> Double { min(max(pg - 1, 0), 1) }
    private func open(_ p: Double) -> Double { min(max(p, 0), 1) }

    private func corner(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    /// The last few gestures' frames, live (the same lines go to Library/Caches/listdrag-frames.log).
    private var meterView: some View {
        VStack {
            HStack {
                Text(meter.lines.suffix(3).joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(5).background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                Spacer()
            }
            .padding(.leading, 8).padding(.top, 52)
            Spacer()
        }
        .allowsHitTesting(false)
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
                Toggle("Fast flicks always open / close", isOn: $flickDecides)
                Toggle("Frame meter", isOn: $showMeter)
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

/// The Zikr page as the app shows it (ZikrPageView), never taking a touch; Equatable so the pager never rebuilds it.
private struct SandboxZikrPage: View, Equatable {
    static func == (a: Self, b: Self) -> Bool { true }
    @Environment(\.circleTheme) private var theme
    var body: some View {
        NavigationStack {
            ZikrPageView(showMantraSheetFromHomePage: .constant(false), showTasbeehPage: .constant(false))
                .toolbar(.hidden, for: .navigationBar)
                .background(theme.backdrop)
        }
        .allowsHitTesting(false)
    }
}

/// Settings as the app's pager shows it (its SettingsPage is Equatable for the same reason), never taking a touch.
private struct SandboxSettingsPage: View, Equatable {
    static func == (a: Self, b: Self) -> Bool { true }
    var body: some View { SettingsView(refetchOnLeave: false).allowsHitTesting(false) }
}

/// Switches the pager's own pan off in UIKit (as the app's PagerPanLock does), set directly — no SwiftUI update.
@MainActor final class PanLock {
    fileprivate weak var scrollView: UIScrollView?
    var locked = false { didSet { if locked != oldValue { scrollView?.panGestureRecognizer.isEnabled = !locked } } }
}

private struct PanLockFinder: UIViewRepresentable {
    let lock: PanLock
    func makeUIView(context: Context) -> Finder { Finder(lock: lock) }
    func updateUIView(_ view: Finder, context: Context) {}
    final class Finder: UIView {
        let lock: PanLock
        init(lock: PanLock) { self.lock = lock; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            MainActor.assumeIsolated { lock.scrollView = v as? UIScrollView }
        }
    }
}

/// Frame timing on the phone (owner: "put something on my phone so you can measure"): a display link that, while the
/// list drags or springs or the pages move, counts frames and the ones that came late (over 1.5 × the expected
/// interval), and logs one line per phase to Library/Caches/listdrag-frames.log.
@MainActor @Observable final class FrameMeter {
    private(set) var lines: [String] = []
    @ObservationIgnored var phase: () -> String? = { nil }
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var current: String?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var late = 0
    @ObservationIgnored private var worst = 0.0
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var began: Date = .now

    static var logURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "listdrag-frames.log") }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: MeterTick(self), selector: #selector(MeterTick.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        write("— sandbox opened \(Date.now.formatted(date: .omitted, time: .standard)) · \(UIScreen.main.maximumFramesPerSecond) Hz screen")
    }
    func stop() { flush(); link?.invalidate(); link = nil }

    fileprivate func tick(_ l: CADisplayLink) {
        let expected = l.targetTimestamp - l.timestamp
        let dt = last == 0 ? expected : l.timestamp - last
        last = l.timestamp
        let p = phase()
        if p != current { flush(); current = p; began = .now; frames = 0; late = 0; worst = 0 }
        guard p != nil else { return }
        frames += 1
        if dt > expected * 1.5 { late += 1 }
        worst = max(worst, dt)
    }

    private func flush() {
        guard let c = current, frames > 2 else { return }
        let ms = Date.now.timeIntervalSince(began) * 1000
        write(String(format: "%@ %4.0f ms · %3d frames · %2d late · worst %.1f ms", c, ms, frames, late, worst * 1000))
    }

    private func write(_ line: String) {
        lines.append(line)
        if lines.count > 50 { lines.removeFirst(lines.count - 50) }
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: Self.logURL) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: Self.logURL) }
    }
}

private final class MeterTick: NSObject {
    weak var meter: FrameMeter?
    init(_ m: FrameMeter) { meter = m }
    @MainActor @objc func tick(_ link: CADisplayLink) { meter?.tick(link) }
}

// MARK: - Pieces

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

/// Moves (and fades) an already-built view by a driver's value: the only views that read the drivers, so a frame
/// redraws just these modifiers, never their content (the list, Settings, the Zikr page).
private struct Follows<Content: View>: View {
    let driver: SpringDriver
    var offset: (Double) -> CGSize
    let content: Content
    init(_ driver: SpringDriver, offset: @escaping (Double) -> CGSize, @ViewBuilder content: () -> Content) {
        self.driver = driver; self.offset = offset; self.content = content()
    }
    var body: some View { content.offset(offset(driver.value)) }
}

private struct Follows2<Content: View>: View {
    let pager: SpringDriver
    let list: SpringDriver
    var offset: (Double, Double) -> CGSize = { _, _ in .zero }
    var opacity: ((Double, Double) -> Double)? = nil
    let content: Content
    init(_ pager: SpringDriver, _ list: SpringDriver, offset: @escaping (Double, Double) -> CGSize = { _, _ in .zero },
         opacity: ((Double, Double) -> Double)? = nil, @ViewBuilder content: () -> Content) {
        self.pager = pager; self.list = list; self.offset = offset; self.opacity = opacity; self.content = content()
    }
    var body: some View {
        let pg = pager.value, p = list.value
        content.offset(offset(pg, p)).opacity(opacity?(pg, p) ?? 1)
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

    var isAnimating: Bool { link != nil }
    /// Set from outside (the pager's scroll offset) within the last ~0.1 s.
    var isMoving: Bool { CACurrentMediaTime() - lastSet < 0.1 }
    @ObservationIgnored private var lastSet: CFTimeInterval = 0

    func set(_ v: Double) {
        if v != value { lastSet = CACurrentMediaTime() }
        stop(); value = v; target = v
    }
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
