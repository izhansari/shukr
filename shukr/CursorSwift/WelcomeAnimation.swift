//
//  WelcomeAnimation.swift
//  shukr
//
//  A short welcome when the app starts fresh (owner, 2026-09-25/26): "shukr" writes itself inside
//  a thin sage ring that sits exactly on the Salah page's circle (`WelcomeTarget`), two soft taps
//  like a heartbeat, a hold — then the ring *becomes* the circle: it thickens into the circle's
//  gray track and dissolves onto it while the word lifts away and the page shows through. It
//  always lands on the Salah page (list closed) so there's a circle to land on. About 2.6 s.
//  Plays on a cold launch, and again only after the app has been in the background for more than
//  five minutes (not on a quick hop to another app and back).
//

import SwiftUI

extension View {
    /// Shows `WelcomeOverlay` on launch and after a long time away.
    func welcomeOnLaunch() -> some View { modifier(WelcomeGate()) }
}

/// Where the Salah page's main circle is on screen (global coordinates), written by
/// MainCircleView; and whether the welcome may land on it (PrayerTimesView says no while a tasbeeh
/// session covers the app).
enum WelcomeTarget {
    static var circleFrame: CGRect?
    static var canLand = true
}

struct WelcomeGate: ViewModifier {
    /// How long the app must have been in the background to be welcomed again.
    static let awayThreshold: TimeInterval = 5 * 60
    /// Posted just before the welcome shows: PrayerTimesView brings the Salah page up under it.
    static let willShow = Notification.Name("welcomeWillShow")

    @Environment(\.scenePhase) private var scenePhase
    @State private var showing = WelcomeGate.shouldShowOnLaunch
    @State private var run = 0
    @State private var wentAway: Date?

    private static var shouldShowOnLaunch: Bool {
        #if DEBUG
        // Demo launch args drive screenshots / automation — don't cover them.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") })
            && !ProcessInfo.processInfo.arguments.contains("-demoWelcome") { return false }
        #endif
        return true
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if showing {
                    WelcomeOverlay { showing = false }
                        .id(run)
                        .transition(.identity)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    wentAway = Date()
                case .active:
                    if let away = wentAway, Date().timeIntervalSince(away) > Self.awayThreshold {
                        NotificationCenter.default.post(name: Self.willShow, object: nil)
                        run += 1
                        showing = true
                    }
                    wentAway = nil
                default:
                    break
                }
            }
    }
}

/// A ring drawn as a filled annulus, so its thickness animates (a stroke's line width doesn't).
private struct WelcomeRing: Shape {
    var width: CGFloat
    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect).strokedPath(StrokeStyle(lineWidth: width))
    }
}

/// The welcome itself: letters fade up out of a blur one after another while a thin sage ring
/// draws round them, a light sweeps the word, it holds — then the ring thickens into the Salah
/// circle's track and dissolves onto it as the rest lifts away.
struct WelcomeOverlay: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lettersIn = false
    @State private var ringDrawn = false
    @State private var shine = false
    @State private var morph = false
    @State private var target: CGPoint?

    private let word = Array("shukr")
    /// The Salah page's circle: 200 pt with a 12 pt track centred on it (mainCircle.swift).
    private let ringSize: CGFloat = 200

    var body: some View {
        // No GeometryReader here: one in this overlay left the whole app laid out off screen
        // (blank page) after the welcome — so the overlay fills the screen and the ring is
        // offset from the screen's centre to the circle's (global) centre.
        let screen = UIScreen.main.bounds
        let shift = target.map { CGSize(width: $0.x - screen.midX, height: $0.y - screen.midY) } ?? .zero
        ZStack {
            Color(.systemBackground)
                .opacity(morph ? 0 : 1)
            ZStack {
                // The ring: drawn as a hairline, then grown into the circle's track.
                WelcomeRing(width: morph ? 12 : 1.2)
                    .fill(morph ? Color(.secondarySystemFill) : Color.sage.opacity(0.6))
                    .mask {
                        Circle()
                            .trim(from: 0, to: ringDrawn || reduceMotion ? 1 : 0)
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .shadow(color: Color.sage.opacity(ringDrawn && !morph ? 0.45 : 0), radius: 8)
                    .frame(width: ringSize, height: ringSize)
                    .opacity(reduceMotion ? 0 : (morph ? 0 : 1))
                wordmark
                    .scaleEffect(morph ? 0.94 : 1)
                    .blur(radius: morph ? 6 : 0)
                    .opacity(morph ? 0 : 1)
            }
            .offset(shift)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!morph)
        .task { await play() }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            ForEach(self.word.indices, id: \.self) { i in
                Text(String(self.word[i]))
                    .opacity(lettersIn ? 1 : 0)
                    .blur(radius: lettersIn || reduceMotion ? 0 : 6)
                    .offset(y: lettersIn || reduceMotion ? 0 : 8)
                    .animation(.easeOut(duration: 0.5).delay(0.08 * Double(i)), value: lettersIn)
            }
        }
        .font(.system(size: 44, weight: .thin, design: .rounded))
        .foregroundStyle(.primary)
        .overlay {
            // A soft light passing over the letters once they're in.
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Color.sage.opacity(0.9), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: shine ? geo.size.width * 1.1 : -geo.size.width * 0.6)
            }
            .mask {
                HStack(spacing: 0) {
                    ForEach(self.word.indices, id: \.self) { i in Text(String(self.word[i])) }
                }
                .font(.system(size: 44, weight: .thin, design: .rounded))
            }
            .opacity(reduceMotion ? 0 : 1)
        }
    }

    /// The real circle's centre, if the welcome may land there and it's on screen.
    private func circleCentre() -> CGPoint? {
        guard WelcomeTarget.canLand, let f = WelcomeTarget.circleFrame,
              f.width > 100, UIScreen.main.bounds.insetBy(dx: -1, dy: -1).contains(f) else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
    }

    private func play() async {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.prepare()
        // Sit on the circle from the start: on a cold launch it lays out a beat after the welcome
        // appears, so wait for it (up to ~0.4 s, the page is blank anyway); if it's still not
        // there, start centred and glide the few points onto it later.
        for _ in 0..<8 where circleCentre() == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        target = circleCentre()
        lettersIn = true
        withAnimation(.easeInOut(duration: 0.9).delay(0.1)) { ringDrawn = true }

        try? await Task.sleep(for: .milliseconds(560))
        soft.impactOccurred(intensity: 0.55)          // lub…
        withAnimation(.easeInOut(duration: 0.6)) { shine = true }
        try? await Task.sleep(for: .milliseconds(170))
        soft.impactOccurred(intensity: 1.0)           // …dub, as the ring closes

        try? await Task.sleep(for: .milliseconds(500))
        if let c = circleCentre(), c != target {
            withAnimation(.easeInOut(duration: 0.5)) { target = c }
        }
        try? await Task.sleep(for: .milliseconds(600))
        // Become the circle: the hairline thickens into the gray track while it, the word and the
        // page fade — what's left is the real circle, in the same place.
        withAnimation(.easeInOut(duration: 0.8)) { morph = true }
        try? await Task.sleep(for: .milliseconds(820))
        onFinish()
    }
}

#Preview {
    WelcomeOverlay {}
}
