import UIKit

/// Late frames, written down with what the pager was doing (`-perfFrames`; off otherwise, in every build): a display
/// link notes each frame that came later than one refresh, and the pager's phase changes, into Library/Caches/frames.log
/// — pulled after a run of scripts/perf-paging.sh to see whether paging drops frames as a swipe starts, while it moves
/// or as it lands (paging lag, 2026-10-10).
@MainActor final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()
    static let on = ProcessInfo.processInfo.arguments.contains("-perfFrames")

    /// What the pager is doing, asked at each late frame (PrayerTimesView sets it).
    var context: () -> String = { "" }
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var lines: [String] = []
    private var flush: Task<Void, Never>?
    private let start = CACurrentMediaTime()
    private lazy var file: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("frames.log")
        try? FileManager.default.removeItem(at: url)
        return url
    }()

    /// `-perfToggleList`: the app opens and closes the Salah list itself every 1.5 s (the swipe's own change, the same
    /// animation), so Instruments can record it with no UI test attached (a UI test's session stops a recording).
    var toggleList: (() -> Void)?
    private var toggling: Task<Void, Never>?

    func startIfAsked() {
        // `-perfOpenMemories`: Memories opens 3 s in (the Memories swipe test, in Release builds too).
        if ProcessInfo.processInfo.arguments.contains("-perfOpenMemories"), toggling == nil {
            toggling = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                MemoriesPresenter.shared.open = true
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-perfToggleList"), toggling == nil {
            toggling = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                while !Task.isCancelled {
                    self?.toggleList?()
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        guard Self.on, link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// A moment worth a line of its own (a phase change).
    func note(_ text: String) {
        guard Self.on else { return }
        write(String(format: "%8.3f  %@", CACurrentMediaTime() - start, text))
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let gap = link.timestamp - last
        let frame = link.targetTimestamp - link.timestamp
        guard frame > 0, gap > frame * 1.5 else { return }
        write(String(format: "%8.3f  late %5.1f ms (%d frames)  %@", link.timestamp - start, gap * 1000,
                     Int((gap / frame).rounded()) - 1, context()))
    }

    private func write(_ line: String) {
        lines.append(line)
        flush?.cancel()
        flush = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let text = lines.joined(separator: "\n") + "\n"
            try? text.data(using: .utf8)?.write(to: file, options: .atomic)
        }
    }
}
