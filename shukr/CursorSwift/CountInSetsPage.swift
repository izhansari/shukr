import SwiftUI

/// Count in sets' own page (decisions sets-place A, sets-tap — owner: a full page like the continuous and sleep ones,
/// not a pop-up): the set size for this zikr, − N +. Off below 2 (one per tap is what tapping already does). Opened from
/// the pause screen's sets switch: a tap with no size set, or a hold any time.
struct CountInSetsPage: View {
    @Binding var step: Int
    /// "Alhamdulillah" — saved with this zikr.
    let zikrName: String?
    let onDone: () -> Void

    var body: some View {
        ChipIntroPage(
            symbol: "square.stack", title: "Count in sets",
            subtitle: zikrName.map { "for \($0)" } ?? "for sessions with no zikr",
            points: [],
            primary: "Done", onPrimary: onDone,
            extra: AnyView(stepper))
    }

    private var on: Bool { step > 1 }

    private var stepper: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("each tap counts")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    RepeatRoundButton(symbol: "minus") { n in change(by: -n) }
                    Text(on ? "\(step)" : "1")
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 90)
                    RepeatRoundButton(symbol: "plus") { n in change(by: n) }
                }
                Text(on ? "Recite \(step), tap once." : "Off: one per tap.")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(on ? Color.sage : Color.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))

            Text("Saved with this zikr. While counting, the +\(on ? "\(step)" : "N") at the top turns sets on and off.")
                .font(.footnote).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .animation(.snappy(duration: 0.2), value: step)
    }

    /// 1 is skipped both ways: off ⇄ 2.
    private func change(by delta: Int) {
        let current = on ? step : 1
        var next = min(max(current + delta, 1), QuickAddSteps.range.upperBound)
        if next == 1 && delta > 0 { next = 2 }
        step = next <= 1 ? 0 : next
    }
}
