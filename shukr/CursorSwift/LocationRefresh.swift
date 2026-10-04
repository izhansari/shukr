import SwiftUI

/// A location refresh someone can see (owner: "fix the pull down on the salah page to show visually we are refreshing
/// the location"): the Salah page's pull-down runs it and the top bar's city line shows it — a spinner in place of the
/// location arrow while it works, then a ✓ (or a !) for a moment.
@MainActor @Observable final class LocationRefresh {
    static let shared = LocationRefresh()
    enum State: Equatable { case idle, working, done, failed }
    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    func run(_ viewModel: PrayerViewModel) {
        guard state != .working else { return }
        task?.cancel()
        withAnimation(CircleMotion.label) { state = .working }
        task = Task { @MainActor in
            // At least a beat of spinner: a cached answer comes back at once and the pull looked like nothing.
            async let minimum: Void = { try? await Task.sleep(for: .milliseconds(700)) }()
            let result = await viewModel.refreshLocationNow()
            await minimum
            let ok: Bool
            if case .success = result { ok = true } else { ok = false }
            withAnimation(CircleMotion.label) { state = ok ? .done : .failed }
            if ok { triggerSomeVibration(type: .success) }
            // Only a refresh that worked is "Updated just now" (Bradley's review: a failure stamped it too).
            if ok { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "locationUpdatedAt") }
            guard await CircleGate.pause(2) else { return }   // the ✓ / ! for a moment
            withAnimation(CircleMotion.label) { state = .idle }
        }
    }
}
