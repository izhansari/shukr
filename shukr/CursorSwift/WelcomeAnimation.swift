//
//  WelcomeAnimation.swift
//  shukr
//
//  A short welcome when the app starts fresh (owner, 2026-09-25/26): "shukr" writes itself inside
//  a thin sage ring that sits exactly on the Salah page's circle (`WelcomeTarget`), two soft taps
//  like a heartbeat, a hold — then the ring *becomes* the circle: it starts snug round the word
//  (150 pt), and grows out to the circle's 200 pt while thickening from a hairline into the gray
//  track as the word fades; once it's there, the page fades in around it (owner, 2026-09-26:
//  "the circle grows into the other one"). It
//  always lands on the Salah page (list closed) so there's a circle to land on. About 2.6 s.
//  Plays only on a cold launch — when iOS had ended the app and it starts fresh (owner,
//  2026-09-27: after every 5 min away it came too often).
//

import SwiftUI

extension View {
    /// Shows `WelcomeOverlay` once per launch of the app process.
    func welcomeOnLaunch() -> some View { modifier(WelcomeGate()) }
}

/// Where the Salah page's main circle is on screen (global coordinates), written by
/// MainCircleView; and whether the welcome may land on it (PrayerTimesView says no while a tasbeeh
/// session covers the app).
enum WelcomeTarget {
    static var circleFrame: CGRect?
    static var canLand = true
    /// The circle's track is the dashed "hasn't started" ring right now (MainCircleView): the
    /// welcome lands as that instead of the solid band.
    static var trackDashed = false
}

struct WelcomeGate: ViewModifier {
    @State private var showing = WelcomeGate.shouldShowOnLaunch

    private static var shouldShowOnLaunch: Bool {
        // The first-run setup is up: it ends in this welcome itself (its Bismillah hand-off).
        if FirstRunSetup.showingAtLaunch { return false }
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
                        .transition(.identity)
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
    /// Handed off from a ring already on screen in the same place (the first-run setup's ring,
    /// OnboardingMockups): the ring is there from the first frame, only the letters write in.
    var startDrawn = false
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lettersIn = false
    @State private var ringDrawn = false
    @State private var shine = false
    @State private var grow = false      // the small ring grows into the circle
    @State private var morph = false     // then the page fades in around it
    /// Opening onto a page with no Salah circle (Daily Ayah, 99 Names, the map from a widget): the
    /// ring opens out past the edges like a doorway instead of landing on a circle.
    @State private var portal = false
    @State private var target: CGPoint? = WelcomeOverlay.handoffTarget
    /// Landing on a dashed track (a prayer that hasn't started): grow to it and become the dashes.
    @State private var dashedTarget = false

    private let word = Array("shukr")
    /// The Salah page's circle: 200 pt with a 12 pt track centred on it (mainCircle.swift).
    private let ringSize: CGFloat = 200
    /// The ring's size round the word, before it grows.
    private let startSize: CGFloat = 150
    /// Past every corner of the screen.
    private var portalSize: CGFloat { max(UIScreen.main.bounds.height, UIScreen.main.bounds.width) * 1.4 }

    var body: some View {
        // No GeometryReader here: one in this overlay left the whole app laid out off screen
        // (blank page) after the welcome — so the overlay fills the screen and the ring is
        // offset from the screen's centre to the circle's (global) centre.
        let screen = UIScreen.main.bounds
        let shift = target.map { CGSize(width: $0.x - screen.midX, height: $0.y - screen.midY) } ?? .zero
        ZStack {
            Color(.systemBackground)
            ZStack {
                // The ring: drawn as a hairline, then grown into the circle's track.
                WelcomeRing(width: grow ? (dashedTarget ? 1 : 12) : 1.2)
                    .fill(grow ? (dashedTarget ? Color.clear : Color(.secondarySystemFill)) : Color.sage.opacity(0.6))
                    .mask {
                        Circle()
                            .trim(from: 0, to: ringDrawn || reduceMotion || startDrawn ? 1 : 0)
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .shadow(color: Color.sage.opacity((ringDrawn || startDrawn) && !grow ? 0.45 : 0), radius: 8)
                    // Starts snug round the word, grows to the circle (frame, not scale, so the
                    // line keeps its own width).
                    .frame(width: portal ? portalSize : (grow ? ringSize : startSize),
                           height: portal ? portalSize : (grow ? ringSize : startSize))
                    .opacity(reduceMotion || portal ? 0 : 1)
                // The dashed track, when that's what the circle is showing.
                Circle()
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: ringSize, height: ringSize)
                    .opacity(grow && dashedTarget && !portal ? 1 : 0)
                wordmark
                    .scaleEffect(grow ? 0.9 : (portal ? 1.15 : 1))
                    .blur(radius: grow || portal ? 4 : 0)
                    .opacity(grow || portal ? 0 : 1)
            }
            .offset(shift)
        }
        .ignoresSafeArea()
        .opacity(morph ? 0 : 1)
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

    /// Where a hand-off ring already sits: the Salah circle's centre (so the first frame isn't at
    /// the screen's centre). Only read as the initial `target`; `play()` sets it again.
    private static var handoffTarget: CGPoint? {
        guard let f = WelcomeTarget.circleFrame, f.width > 100 else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
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
        if startDrawn { ringDrawn = true }
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
        try? await Task.sleep(for: .milliseconds(450))
        if !WelcomeTarget.canLand {
            // Nothing to land on: the ring opens out like a doorway (thin, fading) and the word
            // and page go with it, onto whatever page was opened.
            withAnimation(.easeIn(duration: 0.7)) { portal = true; grow = false }
            withAnimation(.easeInOut(duration: 0.6).delay(0.15)) { morph = true }
            try? await Task.sleep(for: .milliseconds(760))
            onFinish()
            return
        }
        // Become the circle: the word lets go and the ring grows out to the Salah circle,
        // thickening into its gray track — or, over a prayer that hasn't started, turning into its
        // dashed ring…
        dashedTarget = WelcomeTarget.trackDashed
        withAnimation(.spring(response: 0.75, dampingFraction: 0.9)) { grow = true }
        try? await Task.sleep(for: .milliseconds(650))
        // …and once it's there, the page fades in around it. The welcome's ring and the real track
        // are the same shape in the same place, so only the page appears.
        withAnimation(.easeInOut(duration: 0.45)) { morph = true }
        try? await Task.sleep(for: .milliseconds(470))
        onFinish()
    }
}

#Preview {
    WelcomeOverlay {}
}
