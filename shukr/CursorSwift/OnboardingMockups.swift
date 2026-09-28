//
//  OnboardingMockups.swift
//  shukr
//
//  DEBUG-only mockups of the new first-run setup (notes #18 + #6, owner-approved 2026-09-28 as
//  mockups only). Not wired into the real launch; reads the saved location / method to show real
//  times but never writes a setting or asks for a permission.
//  `-demoOnboarding location|method|madhab|review` opens a step; Continue walks through them.
//  `-demoOnboardingBismillah ring|sweep` picks the Bismillah look on the review.
//
//  The look follows the everyday opening (WelcomeAnimation.swift): the plain background, the sage
//  ring, light rounded type. The ring stays at the top as the progress (a quarter per step: where
//  you pray, reminders, Fajr, masjid), with the step's symbol inside.
//

#if DEBUG
import SwiftUI
import Adhan
import CoreLocation

enum OnboardingMockStep: String, CaseIterable, Identifiable {
    case location, method, madhab, review
    var id: String { rawValue }
}

struct OnboardingMockView: View {
    @State var step: OnboardingMockStep
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var method: MockMethod = .automatic
    @State private var hanafi = UserDefaults(suiteName: SharedStore.appGroup)?.integer(forKey: "school") == 1

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SetupRing(progress: step == .review ? 1 : 0.25, symbol: step == .review ? "checkmark" : "location.fill")
                .padding(.top, 4)
            Group {
                switch step {
                case .location: LocationStep(next: { go(.method) })
                case .method: MethodStep(method: $method, hanafi: hanafi, next: { go(.madhab) })
                case .madhab: MadhabStep(method: method, hanafi: $hanafi, next: { go(.review) })
                case .review: ReviewStep(method: method, hanafi: hanafi, done: { dismiss() })
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
        }
        .fontDesign(.rounded)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Button {
                if let i = OnboardingMockStep.allCases.firstIndex(of: step), i > 0 {
                    go(OnboardingMockStep.allCases[i - 1])
                } else { dismiss() }
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
/// a quarter per step, the step's symbol inside.
struct SetupRing: View {
    let progress: Double
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.sage.opacity(0.18), lineWidth: 1.2)
            Circle()
                .trim(from: 0, to: drawn || reduceMotion ? progress : 0)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.sage)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 76, height: 76)
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

// MARK: - Step 2a: location

private struct LocationStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            StepTitle(title: "Where do you pray?",
                      subtitle: "shukr works out your prayer times from where you are.")
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 22) {
                why("clock", "Accurate times, wherever you are",
                    "They follow you when you travel — no city to update.")
                why("mappin.and.ellipse", "Your prayers, pinned where you prayed",
                    "Even the ones you mark from the widget or your watch.")
                why("lock", "It stays on your phone",
                    "No account, nothing sent anywhere.")
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 28)
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

// MARK: - Step 2b: method

enum MockMethod: String, CaseIterable, Identifiable {
    case automatic, isna, mwl, ummAlQura, egyptian, karachi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .isna: "ISNA"
        case .mwl: "Muslim World League"
        case .ummAlQura: "Umm al-Qura"
        case .egyptian: "Egyptian"
        case .karachi: "Karachi"
        }
    }
    var region: String {
        switch self {
        case .automatic: "Follows where you are · ISNA here"
        case .isna: "North America"
        case .mwl: "Europe, the Far East"
        case .ummAlQura: "Saudi Arabia"
        case .egyptian: "Africa, the Levant"
        case .karachi: "Pakistan, India, Bangladesh"
        }
    }
    /// Automatic resolves to the region's method (mocked: ISNA for the sim's New York).
    var adhan: CalculationMethod {
        switch self {
        case .automatic, .isna: .northAmerica
        case .mwl: .muslimWorldLeague
        case .ummAlQura: .ummAlQura
        case .egyptian: .egyptian
        case .karachi: .karachi
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
            Spacer(minLength: 16)
            StepTitle(title: "Your calculation method",
                      subtitle: "Picked for where you are. Match your masjid if its times differ.")
            Spacer(minLength: 14)
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
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if m != MockMethod.allCases.last { Divider().padding(.leading, 0) }
                }
                Text("More methods…")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 20)
            TodayStrip(method: method, hanafi: hanafi)
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

// MARK: - Step 2c: madhab

private struct MadhabStep: View {
    let method: MockMethod
    @Binding var hanafi: Bool
    let next: () -> Void

    var body: some View {
        let shafiAsr = MockTimes.today(method, hanafi: false)?.asr
        let hanafiAsr = MockTimes.today(method, hanafi: true)?.asr
        let gap = (shafiAsr != nil && hanafiAsr != nil) ? Int(hanafiAsr!.timeIntervalSince(shafiAsr!) / 60) : nil
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            StepTitle(title: "When does Asr begin for you?",
                      subtitle: "The madhab only changes Asr. The other four prayers stay the same.")
            Spacer(minLength: 24)
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

// MARK: - Step 6: review

private struct ReviewStep: View {
    let method: MockMethod
    let hanafi: Bool
    let done: () -> Void
    private var look: String { UserDefaults.standard.string(forKey: "demoOnboardingBismillah") ?? "ring" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    StepTitle(title: "You're all set",
                              subtitle: "Tap anything to change it. It's all in Settings later, too.")
                        .padding(.top, 14)
                        .padding(.bottom, 22)
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
                    }
                    .padding(.horizontal, 20)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Group {
                if look == "sweep" { BismillahSweep(action: done) } else { BismillahRing(action: done) }
            }
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

// MARK: - Bismillah, two looks

/// Look 1: the app's circle. A sage ring draws round بِسْمِ اللَّهِ and breathes softly; "Bismillah"
/// small beneath. The circle is the button.
private struct BismillahRing: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var breathe = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.sage.opacity(0.08))
                    Circle()
                        .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                        .stroke(Color.sage.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.sage.opacity(breathe ? 0.55 : 0.15), radius: breathe ? 12 : 4)
                    Text("بِسْمِ اللَّهِ")
                        .font(.custom("KFGQPCUthmanTahaNaskh", size: 30))
                        .foregroundStyle(.primary)
                        .offset(y: 3)
                }
                .frame(width: 112, height: 112)
                Text("Bismillah")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sage)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).delay(0.3)) { drawn = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(1.5)) { breathe = true }
        }
        .accessibilityLabel("Bismillah, begin")
    }
}

/// Look 2: a wide capsule, بِسْمِ اللَّهِ with "Bismillah" under it, and the welcome's slow sage
/// light sweeping across it every few seconds.
private struct BismillahSweep: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(spacing: 1) {
                Text("بِسْمِ اللَّهِ")
                    .font(.custom("KFGQPCUthmanTahaNaskh", size: 28))
                    .foregroundStyle(.primary)
                Text("Bismillah")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sage)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(Capsule().fill(Color.sage.opacity(0.10)))
            .overlay {
                // The light passing over, like the welcome's across "shukr".
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.sage.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: sweep ? geo.size.width * 1.05 : -geo.size.width * 0.4)
                }
                .clipShape(Capsule())
                .opacity(reduceMotion ? 0 : 1)
                .allowsHitTesting(false)
            }
            .overlay(Capsule().stroke(Color.sage.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).delay(0.6).repeatForever(autoreverses: false).delay(1.6)) { sweep = true }
        }
        .accessibilityLabel("Bismillah, begin")
    }
}

#Preview("Where you pray") { OnboardingMockView(step: .location) }
#Preview("Madhab") { OnboardingMockView(step: .madhab) }
#Preview("Review") { OnboardingMockView(step: .review) }
#endif
