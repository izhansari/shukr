//
//  WelcomeAnimation.swift
//  shukr
//
//  A short welcome when the app starts fresh (owner, 2026-09-25): "shukr" writes itself in the
//  middle of the page while a thin ring draws round it — the same size and place as the Salah
//  page's circle, so it fades onto the real one — two soft taps like a heartbeat as it settles,
//  holds, then fades away. About 2.5 s.
//  Plays on a cold launch, and again only after the app has been in the background for more than
//  five minutes (not on a quick hop to another app and back).
//

import SwiftUI

extension View {
    /// Shows `WelcomeOverlay` on launch and after a long time away.
    func welcomeOnLaunch() -> some View { modifier(WelcomeGate()) }
}

struct WelcomeGate: ViewModifier {
    /// How long the app must have been in the background to be welcomed again.
    static let awayThreshold: TimeInterval = 5 * 60

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

/// The welcome itself: letters fade up out of a blur one after another, a thin sage ring draws
/// round them, a light sweeps across the word, it holds, then the whole thing fades.
struct WelcomeOverlay: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lettersIn = false
    @State private var ringDrawn = false
    @State private var shine = false
    @State private var leaving = false

    private let word = Array("shukr")
    /// The Salah page's circle (mainCircle.swift: 200 pt, its track centred on it), so on a launch
    /// onto that page the ring lands on the real one as the welcome fades.
    private let ringSize: CGFloat = 200

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            // The ring: a hairline that draws itself, with a faint glow.
            Circle()
                .trim(from: 0, to: ringDrawn || reduceMotion ? 1 : 0)
                .stroke(Color.sage.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.sage.opacity(ringDrawn ? 0.45 : 0), radius: 8)
                .frame(width: ringSize, height: ringSize)
                .opacity(reduceMotion ? 0 : 1)

            HStack(spacing: 0) {
                ForEach(word.indices, id: \.self) { i in
                    Text(String(word[i]))
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
                        ForEach(word.indices, id: \.self) { i in Text(String(word[i])) }
                    }
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                }
                .opacity(reduceMotion ? 0 : 1)
            }
        }
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(!leaving)
        .task { await play() }
    }

    private func play() async {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.prepare()
        lettersIn = true
        withAnimation(.easeInOut(duration: 0.9).delay(0.1)) { ringDrawn = true }

        try? await Task.sleep(for: .milliseconds(560))
        soft.impactOccurred(intensity: 0.55)          // lub…
        withAnimation(.easeInOut(duration: 0.6)) { shine = true }
        try? await Task.sleep(for: .milliseconds(170))
        soft.impactOccurred(intensity: 1.0)           // …dub, as the ring closes

        // Hold on the finished word a beat longer (owner: "a little longer"), then just fade.
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.easeInOut(duration: 0.7)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(720))
        onFinish()
    }
}

#Preview {
    WelcomeOverlay {}
}
