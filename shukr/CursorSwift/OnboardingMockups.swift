//
//  OnboardingMockups.swift
//  shukr
//
//  DEBUG-only mockups of the new first-run setup (notes #18 + #6, owner-approved 2026-09-28 as
//  mockups only). Not wired into the real launch; reads the saved location / method to show real
//  times but never writes a setting or asks for a permission.
//  `-demoOnboarding location|method|madhab|appearance|review` opens a step; Continue walks through.
//  `-demoOnboardingAppearance light|dark|auto` sets the starting appearance (it applies live).
//
//  The look follows the everyday opening (WelcomeAnimation.swift): the plain background, the sage
//  ring, light rounded type. The ring stays at the top as the progress (a fifth per step: where
//  you pray, reminders, Fajr, masjid, appearance), with the step's symbol inside. Every step's
//  title sits at the same height under it (owner: the method page's header shifted).
//
//  Bismillah (owner's pick, round 2): the capsule, filled with the old first screen's moving
//  gradient and grain (`AnimatedWavyGradient` + `NoiseOverlay`, shukrApp.swift), "bismillah" in
//  the type that screen wrote "shukr" in. Tapping it hands off to the everyday opening: the page
//  fades, the progress ring glides to where the Salah circle is and becomes the welcome's ring,
//  then "shukr" writes itself and the ring grows into the circle as on every launch.
//

#if DEBUG
import SwiftUI
import Adhan
import CoreLocation

enum OnboardingMockStep: String, CaseIterable, Identifiable {
    case location, method, madhab, appearance, review
    var id: String { rawValue }
}

struct OnboardingMockView: View {
    @State var step: OnboardingMockStep
    var onFinish: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var method: MockMethod = .automatic
    @State private var hanafi = UserDefaults(suiteName: SharedStore.appGroup)?.integer(forKey: "school") == 1
    /// `-demoOnboardingAppearance light|dark|auto` (default Auto, the recommended pick).
    @State private var appearance: MockAppearance =
        MockAppearance(rawValue: UserDefaults.standard.string(forKey: "demoOnboardingAppearance") ?? "") ?? .auto

    /// Bismillah was tapped: the page fades, the ring glides onto the Salah circle…
    @State private var leaving = false
    /// …and becomes the welcome, which plays as on every launch.
    @State private var welcome = false
    @State private var ringCentre: CGPoint = .zero

    var body: some View {
        ZStack {
            // Gone once the welcome takes over (it has its own background), or the page stayed
            // blank between the welcome fading and this view going away.
            Color(.systemBackground).ignoresSafeArea()
                .opacity(welcome ? 0 : 1)
            VStack(spacing: 0) {
                topBar
                    .opacity(leaving ? 0 : 1)
                SetupRing(progress: progress, symbol: symbol, handoff: leaving)
                    .onGeometryChange(for: CGPoint.self) { geo in
                        let f = geo.frame(in: .global); return CGPoint(x: f.midX, y: f.midY)
                    } action: { if !leaving { ringCentre = $0 } }
                    .offset(leaving ? handoffShift : .zero)
                    .padding(.top, 4)
                    .zIndex(1)
                Group {
                    switch step {
                    case .location: LocationStep(next: { go(.method) })
                    case .method: MethodStep(method: $method, hanafi: hanafi, next: { go(.madhab) })
                    case .madhab: MadhabStep(method: method, hanafi: $hanafi, next: { go(.appearance) })
                    case .appearance: AppearanceStep(appearance: $appearance, next: { go(.review) })
                    case .review: ReviewStep(method: method, hanafi: hanafi, appearance: appearance, done: enterApp)
                    }
                }
                .padding(.top, 26)          // every title at the same height under the ring
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                .opacity(leaving ? 0 : 1)
            }
            .fontDesign(.rounded)
            .opacity(welcome ? 0 : 1)
            if welcome {
                WelcomeOverlay(startDrawn: true, onFinish: onFinish)
                    .transition(.identity)
            }
        }
        .preferredColorScheme(appearance.scheme)
        // `-demoOnboardingEnter`: press Bismillah by itself 3 s in (simulated taps don't reach it).
        .task {
            guard step == .review, ProcessInfo.processInfo.arguments.contains("-demoOnboardingEnter") else { return }
            try? await Task.sleep(for: .seconds(3))
            enterApp()
        }
    }

    private var progress: Double {
        switch step {
        case .location, .method, .madhab: 0.2
        case .appearance: 0.8
        case .review: 1
        }
    }
    private var symbol: String {
        switch step {
        case .location, .method, .madhab: "location.fill"
        case .appearance: "circle.lefthalf.filled"
        case .review: "checkmark"
        }
    }

    /// From the ring's place to the Salah circle's centre (the screen's centre if unknown).
    private var handoffShift: CGSize {
        let screen = UIScreen.main.bounds
        let target = WelcomeTarget.circleFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: screen.midX, y: screen.midY)
        return CGSize(width: target.x - ringCentre.x, height: target.y - ringCentre.y)
    }

    private func enterApp() {
        guard !leaving else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { welcome = true }
            return
        }
        // The page lets go; the ring glides onto the circle and thins into the welcome's hairline.
        withAnimation(.easeOut(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            // The welcome starts with its ring already drawn in exactly this place: only the
            // letters appear, and the rest is the everyday opening.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { welcome = true }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if let i = OnboardingMockStep.allCases.firstIndex(of: step), i > 0 {
                    go(OnboardingMockStep.allCases[i - 1])
                } else { onFinish() }
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            if step != .review {
                Button("Skip") { go(.review) }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func go(_ s: OnboardingMockStep) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) { step = s }
    }
}

// MARK: - The ring (progress + the step's symbol)

/// The opening's sage ring, small, at the top of every step: a hairline track, the sage arc filling
/// a fifth per step, the step's symbol inside. `handoff`: it becomes the welcome's ring — 150 pt,
/// a 1.2 pt sage hairline with its soft glow, empty inside.
struct SetupRing: View {
    let progress: Double
    let symbol: String
    var handoff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(Color.sage.opacity(handoff ? 0 : 0.18), lineWidth: 1.2)
                Circle()
                    .trim(from: 0, to: handoff ? 1 : (drawn || reduceMotion ? progress : 0))
                    .stroke(Color.sage.opacity(handoff ? 0.6 : 1),
                            style: StrokeStyle(lineWidth: handoff ? 1.2 : 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.sage.opacity(handoff ? 0.45 : 0), radius: 8)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.sage)
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(handoff ? 0 : 1)
            }
            // Grows inside a fixed frame, so it stays centred where it is.
            .frame(width: handoff ? 150 : 76, height: handoff ? 150 : 76)
            .opacity(handoff && reduceMotion ? 0 : 1)
        }
        .frame(width: 76, height: 76)
        .animation(.spring(response: 0.8, dampingFraction: 0.9), value: handoff)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { drawn = true } }
        .animation(.easeInOut(duration: 0.7), value: progress)
    }
}

// MARK: - Shared pieces

private struct StepTitle: View {
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
    }
}

/// The one primary button at the bottom: the app's calm style (sage text on a soft sage tint, like
/// the pause screen's Resume), not a solid fill.
private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(Color.sage.opacity(0.14)))
                .overlay(Capsule().stroke(Color.sage.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}

// MARK: - Step: location

private struct LocationStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "Where do you pray?",
                      subtitle: "shukr works out your prayer times from where you are.")
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 22) {
                why("clock", "Accurate times, wherever you are",
                    "They follow you when you travel — no city to update.")
                why("mappin.and.ellipse", "Your prayers, pinned where you prayed",
                    "Even the ones you mark from the widget or your watch.")
                why("lock", "It stays on your phone",
                    "No account, nothing sent anywhere.")
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 24)
            Text("iOS asks “While Using” first. Pick “Always” when it offers, so your times follow you.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 14)
            PrimaryButton(title: "Allow location", action: next)
            Button("Enter a city instead", action: next)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
    }

    private func why(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.sage)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .regular, design: .rounded))
                Text(detail).font(.system(size: 15, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Step: method

/// The most-used methods first (a short scroller; the rest below them).
enum MockMethod: String, CaseIterable, Identifiable {
    case automatic, isna, mwl, ummAlQura, karachi, egyptian, dubai, kuwait, qatar, singapore, turkey, tehran
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .isna: "ISNA"
        case .mwl: "Muslim World League"
        case .ummAlQura: "Umm al-Qura"
        case .karachi: "Karachi"
        case .egyptian: "Egyptian"
        case .dubai: "Dubai"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore"
        case .turkey: "Turkey (Diyanet)"
        case .tehran: "Tehran"
        }
    }
    var region: String {
        switch self {
        case .automatic: "Follows where you are · ISNA here"
        case .isna: "North America"
        case .mwl: "Europe, the Far East"
        case .ummAlQura: "Saudi Arabia"
        case .karachi: "Pakistan, India, Bangladesh"
        case .egyptian: "Africa, the Levant"
        case .dubai: "United Arab Emirates"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore, Malaysia, Indonesia"
        case .turkey: "Turkey"
        case .tehran: "Iran"
        }
    }
    /// Automatic resolves to the region's method (mocked: ISNA for the sim's New York).
    var adhan: CalculationMethod {
        switch self {
        case .automatic, .isna: .northAmerica
        case .mwl: .muslimWorldLeague
        case .ummAlQura: .ummAlQura
        case .karachi: .karachi
        case .egyptian: .egyptian
        case .dubai: .dubai
        case .kuwait: .kuwait
        case .qatar: .qatar
        case .singapore: .singapore
        case .turkey: .turkey
        case .tehran: .tehran
        }
    }
}

/// Today's times for the saved location (read only), New York if there's none.
enum MockTimes {
    static func today(_ method: MockMethod, hanafi: Bool) -> PrayerTimes? {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        let lat = store?.double(forKey: "lastLatitude") ?? 0, lon = store?.double(forKey: "lastLongitude") ?? 0
        let coords = (lat == 0 && lon == 0) ? Coordinates(latitude: 40.7128, longitude: -74.0060)
                                            : Coordinates(latitude: lat, longitude: lon)
        var params = method.adhan.params
        params.madhab = hanafi ? .hanafi : .shafi
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return PrayerTimes(coordinates: coords, date: comps, calculationParameters: params)
    }
    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }
}

private struct MethodStep: View {
    @Binding var method: MockMethod
    let hanafi: Bool
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "Your calculation method",
                      subtitle: "Picked for where you are. Match your masjid if its times differ.")
                .padding(.bottom, 16)
            // A short scroller: the popular ones show, the rest are a scroll away (the fade says so).
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(MockMethod.allCases) { m in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { method = m }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).font(.system(size: 17, weight: .regular, design: .rounded))
                                    Text(m.region).font(.system(size: 13, weight: .light, design: .rounded))
                                        .foregroundStyle(m == .automatic ? Color.sage : .secondary)
                                }
                                Spacer()
                                Image(systemName: method == m ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(method == m ? Color.sage : Color.secondary.opacity(0.4))
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if m != MockMethod.allCases.last { Divider() }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 36)
                }
            }
            TodayStrip(method: method, hanafi: hanafi)
                .padding(.top, 8)
                .padding(.bottom, 20)
            PrimaryButton(title: "Continue", action: next)
                .padding(.bottom, 8)
        }
    }
}

/// Today's five times, updating live as the method / madhab change.
private struct TodayStrip: View {
    let method: MockMethod
    let hanafi: Bool
    var highlightAsr = false

    var body: some View {
        let t = MockTimes.today(method, hanafi: hanafi)
        VStack(spacing: 8) {
            Text("today").font(.caption).tracking(2).textCase(.uppercase).foregroundStyle(.tertiary)
            HStack(spacing: 0) {
                cell("Fajr", t?.fajr)
                cell("Dhuhr", t?.dhuhr)
                cell("Asr", t?.asr, strong: highlightAsr)
                cell("Maghrib", t?.maghrib)
                cell("Isha", t?.isha)
            }
        }
        .padding(.horizontal, 20)
    }

    private func cell(_ name: String, _ date: Date?, strong: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(strong ? Color.sage : .secondary)
            Text(date.map(MockTimes.short) ?? "–")
                .font(.system(size: 15, weight: strong ? .medium : .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(strong ? Color.sage : .primary)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: date)
    }
}

// MARK: - Step: madhab

private struct MadhabStep: View {
    let method: MockMethod
    @Binding var hanafi: Bool
    let next: () -> Void

    var body: some View {
        let shafiAsr = MockTimes.today(method, hanafi: false)?.asr
        let hanafiAsr = MockTimes.today(method, hanafi: true)?.asr
        let gap = (shafiAsr != nil && hanafiAsr != nil) ? Int(hanafiAsr!.timeIntervalSince(shafiAsr!) / 60) : nil
        VStack(spacing: 0) {
            StepTitle(title: "When does Asr begin?",
                      subtitle: "The madhab only changes Asr. The other four prayers stay the same.")
            Spacer(minLength: 20)
            HStack(spacing: 14) {
                card(title: "Shafi'i", note: "Maliki, Hanbali too", rule: "when a shadow is as long as the object",
                     lengths: 1, asr: shafiAsr, selected: !hanafi) { hanafi = false }
                card(title: "Hanafi", note: nil, rule: "when a shadow is twice the object's length",
                     lengths: 2, asr: hanafiAsr, selected: hanafi) { hanafi = true }
            }
            .padding(.horizontal, 24)
            if let gap {
                Text("Hanafi Asr is \(gap) min later today.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
            }
            Text("Not sure? Go with what your masjid uses.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
            Spacer(minLength: 20)
            TodayStrip(method: method, hanafi: hanafi, highlightAsr: true)
                .padding(.bottom, 20)
            PrimaryButton(title: "Continue", action: next)
                .padding(.bottom, 8)
        }
    }

    private func card(title: String, note: String?, rule: String, lengths: CGFloat, asr: Date?,
                      selected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { pick() }
        } label: {
            VStack(spacing: 12) {
                ShadowSketch(lengths: lengths)
                    .frame(height: 64)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 19, weight: .regular, design: .rounded))
                    Text(note ?? " ").font(.caption).foregroundStyle(.tertiary)
                }
                Text(asr.map { "Asr \(MockTimes.short($0))" } ?? "Asr –")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.sage : .primary)
                Text(rule)
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(selected ? Color.sage.opacity(0.10) : Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.sage.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A post and its afternoon shadow: one length (Shafi'i) or two (Hanafi), with the sun.
private struct ShadowSketch: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            // The same scale in both cards, so the shadows compare: room for two lengths.
            let unit = min(size.height * 0.6, (size.width - 40) / 2.2)
            let groundY = size.height - 4
            let postX: CGFloat = 32
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 6, y: groundY)); p.addLine(to: CGPoint(x: size.width - 6, y: groundY)) },
                       with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX + unit * lengths, y: groundY)) },
                       with: .color(Color.sage.opacity(0.8)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX, y: groundY - unit)) },
                       with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // The sun behind the post, lower when the shadow is longer (later in the afternoon).
            let sunY = groundY - unit * (lengths == 1 ? 1.1 : 0.62)
            ctx.fill(Path(ellipseIn: CGRect(x: 8, y: sunY - 6, width: 12, height: 12)), with: .color(.orange.opacity(0.75)))
        }
    }
}

// MARK: - Step: appearance

enum MockAppearance: String, CaseIterable, Identifiable {
    case light, dark, auto
    var id: String { rawValue }
    var title: String {
        switch self { case .light: "Light"; case .dark: "Dark"; case .auto: "Auto" }
    }
    /// Auto follows the sun like the app's SunBased mode: light from Fajr to Maghrib, dark after.
    var scheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto:
            guard let t = MockTimes.today(.automatic, hanafi: false) else { return nil }
            let now = Date()
            return now >= t.fajr && now < t.maghrib ? .light : .dark
        }
    }
}

private struct AppearanceStep: View {
    @Binding var appearance: MockAppearance
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "Light or dark?",
                      subtitle: "Auto follows the sun: light from Fajr, dark after Maghrib.")
            Spacer(minLength: 24)
            HStack(spacing: 14) {
                ForEach(MockAppearance.allCases) { a in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { appearance = a }
                    } label: {
                        VStack(spacing: 10) {
                            AppearanceSwatch(kind: a)
                                .frame(height: 150)
                                .overlay(RoundedRectangle(cornerRadius: 18)
                                    .stroke(appearance == a ? Color.sage : Color.secondary.opacity(0.25),
                                            lineWidth: appearance == a ? 2 : 1))
                            Text(a.title).font(.system(size: 17, weight: .regular, design: .rounded))
                            Text(a == .auto ? "Recommended" : " ")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.sage)
                            Image(systemName: appearance == a ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(appearance == a ? Color.sage : Color.secondary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 24)
            PrimaryButton(title: "Continue", action: next)
                .padding(.bottom, 8)
        }
    }
}

/// A tiny Salah page: the circle on the page's colour. Auto is split light / dark with the sun and
/// the moon.
private struct AppearanceSwatch: View {
    let kind: MockAppearance
    var body: some View {
        ZStack {
            switch kind {
            case .light: page(.white, ink: .black)
            case .dark: page(.black, ink: .white)
            case .auto:
                ZStack {
                    page(.white, ink: .black)
                    page(.black, ink: .white)
                        .mask(Rectangle().rotationEffect(.degrees(28)).offset(x: 46).scaleEffect(2))
                }
                VStack {
                    HStack {
                        Image(systemName: "sun.max").foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "moon").foregroundStyle(.white.opacity(0.85))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(8)
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func page(_ bg: Color, ink: Color) -> some View {
        ZStack {
            bg
            Circle().stroke(ink.opacity(0.14), lineWidth: 5).frame(width: 58, height: 58)
            Circle().trim(from: 0, to: 0.62).stroke(Color.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 58, height: 58)
            Capsule().fill(ink.opacity(0.55)).frame(width: 26, height: 4)
        }
    }
}

// MARK: - Step: review

private struct ReviewStep: View {
    let method: MockMethod
    let hanafi: Bool
    let appearance: MockAppearance
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "You're all set",
                      subtitle: "Tap anything to change it. It's all in Settings later, too.")
                .padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    row("location.fill", "Location", "New York · While Using",
                        nudge: ("Turn on Always so your times follow you when you travel.", "Turn on"))
                    divider
                    row("clock", "Prayer times", "\(method == .automatic ? "Automatic (ISNA)" : method.title) · \(hanafi ? "Hanafi" : "Shafi'i")")
                    divider
                    row("bell", "Reminders", "At the start, halfway and 30 min left",
                        sell: "Not just at the start: a nudge halfway and with 30 min left, tuned per prayer.",
                        nudge: ("Notifications are off, so reminders can't reach you.", "Turn on"))
                    divider
                    row("alarm", "Fajr alarm", "20 min before Fajr",
                        sell: "A real alarm from a rule you set once. It follows Fajr all year.")
                    divider
                    row("building.columns", "Your masjid", "Assafa Islamic Center · arrival duas on",
                        sell: "A dua when you arrive and when you leave.")
                    divider
                    row("circle.lefthalf.filled", "Appearance",
                        appearance == .auto ? "Auto · follows the sun" : appearance.title)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            BismillahCapsule(action: done)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }

    private var divider: some View { Divider().padding(.leading, 44) }

    private func row(_ symbol: String, _ title: String, _ value: String, sell: String? = nil,
                     nudge: (String, String)? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.sage)
                .frame(width: 30, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 17, weight: .regular, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.medium)).foregroundStyle(.tertiary)
                }
                Text(value).font(.system(size: 15, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                if let sell {
                    Text(sell).font(.system(size: 13, weight: .light, design: .rounded)).italic()
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let nudge {
                    // Gentle, never blocking: a line and a deep link to Settings.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle").font(.caption)
                        Text(nudge.0).font(.system(size: 13, weight: .regular, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(nudge.1).font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.sage)
                    }
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Bismillah

/// The owner's pick: the capsule, with the old first screen borrowed whole — its slowly moving
/// green / black gradient and breathing grain (`AnimatedWavyGradient` + `NoiseOverlay`) — and
/// "bismillah" in the type that screen wrote "shukr" in (title, thin, rounded, white 0.8).
private struct BismillahCapsule: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noiseOpacity: Double = 0.2

    var body: some View {
        Button(action: action) {
            Text("bismillah")
                .font(.title)
                .fontWeight(.thin)
                .fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background {
                    // The screen-sized gradient seen through the capsule (it was drawn for a full
                    // screen; its radii are in points). A background, so it can't widen the layout.
                    ZStack {
                        AnimatedWavyGradient()
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height * 0.5)
                        NoiseOverlay()
                            .blendMode(.overlay)
                            .opacity(noiseOpacity)
                    }
                }
                .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.secondarySystemFill).opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { noiseOpacity = 0.3 }
        }
        .accessibilityLabel("Bismillah, begin")
    }
}

#Preview("Where you pray") { OnboardingMockView(step: .location) }
#Preview("Appearance") { OnboardingMockView(step: .appearance) }
#Preview("Review") { OnboardingMockView(step: .review) }
#endif
