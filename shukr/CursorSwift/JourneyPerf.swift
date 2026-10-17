import SwiftUI
import QuartzCore

/// Journey's perf log (the perf round, owner 2026-10-17: "throw logs on [my phone]"): what a move costs, measured — each
/// thing you do on Journey (a tap, a hold, the rail, a month turned, the year) starts a window that ends at the next one
/// or after a quiet spell, and its line says how the frames went (late ones, hitch time, the worst gap, the main thread's
/// longest busy spell), how many times each heavy view's body ran, and what each timed piece of work took.
/// Library/Caches/journey-perf.log on the phone, and the console. On in DEBUG, and in any build launched with `-journeyPerf`
/// (the Release perf run, scheme shukrPerf — FrameMonitor's way); off, every call is one check of a constant.
@MainActor enum JourneyPerf {
    static let on: Bool = {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.arguments.contains("-journeyPerf")
        #endif
    }()

    /// Something the user did (or a transition began): the last window is written, a new one opens under this name.
    @inline(__always) static func began(_ event: String) {
        if on { JourneyPerfLog.shared.began(event) }
    }

    /// A scroll is moving (`true` from its first move, `false` once it rests): its window stays open meanwhile, however smooth —
    /// a quiet spell only ends a window once nothing moves.
    @inline(__always) static func scrolling(_ moving: Bool) {
        if on { JourneyPerfLog.shared.scrolling = moving }
    }

    /// A view's body ran (`let _ = JourneyPerf.body("card")`).
    @inline(__always) static func body(_ name: StaticString) {
        if on { JourneyPerfLog.shared.body(name.description) }
    }

    /// A piece of main-thread work, timed.
    @inline(__always) static func time<T>(_ name: StaticString, _ work: () -> T) -> T {
        guard on else { return work() }
        let t = CACurrentMediaTime()
        let r = work()
        JourneyPerfLog.shared.took(name.description, CACurrentMediaTime() - t)
        return r
    }

    /// Work timed elsewhere (an off-main load, from its start to its result).
    @inline(__always) static func took(_ name: StaticString, since start: CFTimeInterval) {
        if on { JourneyPerfLog.shared.took(name.description, CACurrentMediaTime() - start) }
    }

    static var now: CFTimeInterval { CACurrentMediaTime() }
}

@MainActor final class JourneyPerfLog: NSObject {
    static let shared = JourneyPerfLog()

    private var bodies: [String: Int] = [:]
    private var times: [String: (n: Int, total: Double, worst: Double)] = [:]
    private var event = ""
    private var began: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var hitch: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0
    private var expected: CFTimeInterval = 1 / 120.0
    private var observer: CFRunLoopObserver?
    private var wokeAt: CFTimeInterval = 0
    private var busy: CFTimeInterval = 0
    /// When the window last saw a late frame or a body (quiet for `idle` s: it's written and the link sleeps).
    private var lastActivity: CFTimeInterval = 0
    fileprivate var scrolling = false
    private static let idle: CFTimeInterval = 2.5
    private var started = false

    func began(_ e: String) {
        flush()
        if !started {
            started = true
            write("— \(BuildInfo.line) · \(UIScreen.main.bounds.width)×\(UIScreen.main.bounds.height) —")
        }
        event = e
        began = CACurrentMediaTime(); last = began; lastActivity = began
        // busy: the main thread's pass under way (this move's own handler is in it) counts for this window, from when it woke.
        frames = 0; late = 0; hitch = 0; worst = 0; busy = 0
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }
        if observer == nil {
            let o = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = CACurrentMediaTime()
                    // Every wake is noted, a window open or not: noted only while one was open, the first pass after a
                    // quiet spell measured from a wake seconds old (busy read 10–13 s on the sim).
                    if activity == .afterWaiting { self.wokeAt = now }
                    else if self.link != nil { self.busy = max(self.busy, now - self.wokeAt) }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
            observer = o
            wokeAt = began
        }
    }

    /// A body counts as something happening: a window with views redrawing doesn't go quiet.
    fileprivate func body(_ name: String) {
        bodies[name, default: 0] += 1
        if link != nil { lastActivity = CACurrentMediaTime() }
    }

    func took(_ name: String, _ s: CFTimeInterval) {
        var t = times[name] ?? (0, 0, 0)
        t.n += 1; t.total += s; t.worst = max(t.worst, s)
        times[name] = t
        lastActivity = CACurrentMediaTime()
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        expected = max(l.targetTimestamp - l.timestamp, 1 / 120.0)
        if frames > 0 {
            let gap = now - last
            worst = max(worst, gap)
            if gap > expected * 1.5 { late += 1; hitch += gap - expected; lastActivity = now }
        }
        frames += 1
        last = now
        if scrolling { lastActivity = now }
        if now - lastActivity > Self.idle { flush(); l.invalidate(); link = nil }
    }

    /// The window's line: "tap tile · 0.62 s · 74 fr @120 · 3 late · hitch 41 ms · worst 25 ms · busy 31 ms · card 2 row 18 ·
    /// extras 12 ms".
    private func flush() {
        guard !event.isEmpty else { bodies = [:]; times = [:]; return }
        let s = CACurrentMediaTime() - began
        var parts = [event, String(format: "%.2f s", s)]
        parts.append(String(format: "%d fr @%.0f · %d late · hitch %.0f ms · worst %.0f ms · busy %.0f ms",
                            frames, 1 / expected, late, hitch * 1000, worst * 1000, busy * 1000))
        if !bodies.isEmpty { parts.append(bodies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " ")) }
        if !times.isEmpty {
            parts.append(times.sorted { $0.key < $1.key }.map { k, t in
                t.n == 1 ? String(format: "%@ %.1f ms", k, t.total * 1000)
                    : String(format: "%@ %d× %.1f ms (worst %.1f)", k, t.n, t.total * 1000, t.worst * 1000)
            }.joined(separator: ", "))
        }
        write(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()) + " " + parts.joined(separator: " · "))
        event = ""; bodies = [:]; times = [:]
    }

    /// Off the main thread, in order (a write at the tap would land in that move's first frame).
    private static let disk = DispatchQueue(label: "journey-perf.log", qos: .utility)

    private func write(_ line: String) {
        print("⏱️ \(line)")
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("journey-perf.log")
        let data = Data((line + "\n").utf8)
        Self.disk.async {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
        }
    }
}
