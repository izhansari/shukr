import SwiftUI

// The "Prayer circle" card: the setup welcome's graphic (FirstRunSetup's WelcomeRingDemo, with its Play demo) and Your goal's
// hero (PrayerGoalPage) draw the same card and ring (Design's Your goal v7, owner 2026-10-19: "Let's try using the graphic
// that we have in the onboarding setup with that demo of the prayer ring … as the display of our goal that we choose").

/// The window's three parts, as `PrayerScoring` grades a 150-minute window: Perfect for the first 30 minutes (0.2),
/// Middle for the first half of the rest (to 0.6), then Closing.
enum WelcomeWindow {
    static func part(_ gone: Double) -> Int { gone < 0.2 ? 0 : gone < 0.6 ? 1 : 2 }
    static let colours: [Color] = [.green, .yellow, .red]
}

/// The card: "Prayer circle" (and, on the welcome, its Play demo) on the sage gradient, and in it the page's own soft
/// surface with the ring, so the raised band reads as it does on the Salah page.
struct PrayerCircleCard<Accessory: View, Ring: View>: View {
    var ringSize: CGFloat
    var ringPadding: CGFloat
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var ring: () -> Ring
    @Environment(\.circleTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Prayer circle")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                accessory()
            }
            .padding(.leading, 4)
            ring()
                .frame(width: ringSize, height: ringSize)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ringPadding)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.surface))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color.sage.opacity(0.55), Color.sage.opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

extension PrayerCircleCard where Accessory == EmptyView {
    init(ringSize: CGFloat, ringPadding: CGFloat, @ViewBuilder ring: @escaping () -> Ring) {
        self.init(ringSize: ringSize, ringPadding: ringPadding, accessory: { EmptyView() }, ring: ring)
    }
}

/// The Salah page's ring in its soft look: the raised band, and on it the arc filled to what's gone, from the top,
/// clockwise, in the colour of where it is (the theme's arc width, round cap and glow). Drawn at the Salah ring's 200 pt
/// (its band and glow as they are there) and shown at `size`.
struct WelcomeSweep: View, Animatable {
    var gone: Double
    /// Only the arc fades (the welcome's replay); the band stays.
    var arcOpacity: Double = 1
    /// Toward Qaza's grey (Your goal: Qaza is after the window).
    var grey: Double = 0
    /// A one-off swell of the arc (Your goal's Save): its width and glow grow, then settle.
    var swell: Double = 0
    var size: CGFloat = 112
    /// Your goal: each goal's end (0.2, 0.6, 1.0) is its own pure colour; the colour blends only just past a boundary while
    /// it sweeps. The welcome blends either side of each boundary as its ring fills.
    var endsPure = false
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(gone, arcOpacity), AnimatablePair(grey, swell)) }
        set { gone = newValue.first.first; arcOpacity = newValue.first.second; grey = newValue.second.first; swell = newValue.second.second }
    }
    @Environment(\.circleTheme) private var theme

    /// Blended across each boundary (a short crossfade), so the colour turns rather than snaps.
    private var colour: Color {
        let band = 0.035
        let base: Color
        if endsPure {
            func past(_ a: Color, _ b: Color, at edge: Double) -> Color? {
                guard gone > edge, gone < edge + 2 * band else { return nil }
                return a.mix(with: b, by: (gone - edge) / (2 * band))
            }
            base = past(.green, .yellow, at: 0.2) ?? past(.yellow, .red, at: 0.6)
                ?? WelcomeWindow.colours[gone <= 0.2 ? 0 : gone <= 0.6 ? 1 : 2]
        } else {
            func mix(_ a: Color, _ b: Color, at edge: Double) -> Color? {
                guard abs(gone - edge) < band else { return nil }
                return a.mix(with: b, by: (gone - edge + band) / (2 * band))
            }
            base = mix(.green, .yellow, at: 0.2) ?? mix(.yellow, .red, at: 0.6)
                ?? WelcomeWindow.colours[WelcomeWindow.part(gone)]
        }
        return grey > 0 ? base.mix(with: PrayerScoring.color(for: PrayerScoring.qaza), by: min(grey, 1)) : base
    }

    var body: some View {
        let colour = self.colour
        ZStack {
            NeuRingTrack()
            Circle()
                .trim(from: 0, to: max(gone, 0.002))
                .stroke(colour, style: StrokeStyle(lineWidth: theme.arc.width * (1 + 0.65 * swell), lineCap: theme.arc.cap))
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
                .shadow(color: colour.opacity(min(theme.arc.glow + 0.4 * swell, 1)), radius: 6 + 6 * swell)
                .opacity(arcOpacity)
        }
        .scaleEffect(size / 200)
        .frame(width: size, height: size)
    }
}
