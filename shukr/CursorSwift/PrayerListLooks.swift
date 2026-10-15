import SwiftUI

// Sami's trial looks for the prayer list (owner, 2026-10-14: "one of the most high-touched items in our app … I just
// kind of gave up on trying to make it pretty early on"), under the palette menu's "Sami list" (SalahLook.sami: B · Timeline,
// C · Now, D · Line + Now, E · Now leads, F · What happened). A · Rings went (the main ring already shows the window) and
// C's progress line went (we never show progress as a line — owner). They change only how a row looks: the row's one gesture, the "N done" fold, the
// day page's lift and the tour's targets are PrayerButton's, untouched. The well round the rows is the public look's.
// Built from docs/design-language.md: the ring holds the state, one thing leads, sage = tap, grey hierarchy.

/// B · Timeline — the day as one thin line through the five dots: lit (sage) where the day has been, faint dashes where
/// it hasn't. Each row draws the piece above its dot and the piece below it down through the gap to the next row, so
/// the rows join; folded "N done" rows leave the first visible row's line running up out of the card, as if from them.
struct TimelineSpine: View {
    /// The dot's centre in the row (PrayerButton's `dotCenter`).
    let dot: CGPoint
    /// How far the line runs past the row's bottom (the gap to the next row).
    let gapBelow: CGFloat
    let showsAbove: Bool
    let showsBelow: Bool
    let litAbove: Bool
    let litBelow: Bool
    /// Room left round the dot (the dot is 14 pt; a little air either side).
    static let clearance: CGFloat = 11

    var body: some View {
        Canvas { ctx, size in
            func piece(from y0: CGFloat, to y1: CGFloat, lit: Bool) {
                guard y1 > y0 else { return }
                var p = Path()
                p.move(to: CGPoint(x: dot.x, y: y0))
                p.addLine(to: CGPoint(x: dot.x, y: y1))
                ctx.stroke(p, with: .color(lit ? Color.sage.opacity(0.75) : Color.secondary.opacity(0.32)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: lit ? [] : [2, 4]))
            }
            if showsAbove { piece(from: 0, to: dot.y - Self.clearance, lit: litAbove) }
            if showsBelow { piece(from: dot.y + Self.clearance, to: size.height, lit: litBelow) }
        }
        .padding(.bottom, -gapBelow)
        .allowsHitTesting(false)
    }
}

/// C / D / E / F — the prayer on now, as the one raised block inside the well, with its time left (red in its last half
/// hour, as the Live Activity card).
struct NowTimeLeft: View {
    let start: Date
    let end: Date
    var font: Font = .footnote
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.left(until: end, from: context.date))
                .font(font).fontDesign(.rounded).fontWeight(.regular)
                .foregroundStyle(PrayerScoring.color(for: PrayerScoring.score(start: start, end: end, markedAt: context.date)) == .red
                                 ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(Color.secondary))
                .monospacedDigit()
        }
    }
    /// "1 hr 39 min left" · "24 min left" · "under a minute" (minutes only, as the Live Activity card says it).
    static func left(until end: Date, from now: Date) -> String {
        let minutes = Int(end.timeIntervalSince(now) / 60)
        if minutes < 1 { return "under a minute" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? (m > 0 ? "\(h) hr \(m) min left" : "\(h) hr left") : "\(m) min left"
    }
}

/// G · the moment after marking the prayer on now from the list (owner, 2026-10-14): its row stays raised and its time
/// becomes three buttons — edit, camera (while its window is open), Tasbih — in place of the post-salah pill. Closing the
/// list hands the moment to the pill (PagerChromeView); other rows' taps leave them (owner); unmarking clears them;
/// the day's last prayer keeps the pill (the day page comes). Marks from anywhere else: the pill, as always.
@MainActor @Observable final class PrayerRowActions {
    static let shared = PrayerRowActions()
    /// The prayer whose row shows the buttons.
    var name: String?
    /// The row's camera / Tasbih (PagerChromeView opens them as the pill would; object: the prayer's name).
    static let openCamera = Notification.Name("PrayerRowActions.openCamera")
    static let openTasbih = Notification.Name("PrayerRowActions.openTasbih")
}

/// The buttons where the row's time sits, in the pill's order (Tasbih, then the camera); the pencil sits right after the
/// name (owner's drawing). Neutral: grey symbols (the name's grey) in a thin grey ring, no fill (owner).
struct PrayerRowActionButtons: View {
    let showsCamera: Bool
    let onCamera: () -> Void
    let onTasbih: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            PrayerRowActionButton(symbol: "circle.hexagonpath", label: "Post-salah tasbih", action: onTasbih)   // the pill's beads
            if showsCamera { PrayerRowActionButton(symbol: "camera", label: "Add a photo", action: onCamera) }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// One of the marked row's buttons: a grey symbol in a thin grey ring.
struct PrayerRowActionButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    /// The thin ring round it (the pencil by the name has none — owner: "just the pen").
    var ringed = true
    let action: () -> Void
    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .overlay { if ringed { Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

