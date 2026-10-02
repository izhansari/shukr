//
//  SleepMode.swift
//  shukr
//
//  Tasbeeh sleep mode (owner, 2026-09-30, ideas F3BR + 4WTV, ask sleep-mode):
//  - `SleepIntroView`: the first time the sleep chip is turned on, a full-page sheet explains it;
//    "Turn on sleep mode" turns it on and never shows the sheet again, "Not now" leaves it off and
//    shows it again next time (decision sleep-intro A). The sleep chip's (i) opens it any time (owner,
//    2026-09-30); with sleep already on it has just "Done".
//  - `MorningCardView`: when sleep mode ended a session, the next open plays the welcome (from black
//    after a warm lock — `WelcomeGate`'s curtain) and its ring lands on the card's ring, drawn on the
//    Salah circle; "Good morning" fades the page away round it, leaving the Salah page (decisions
//    sleep-morning-card A, sleep-morning-open).
//

import SwiftUI
import SwiftData

/// The session sleep mode ended, waiting to be shown the next time the Salah page is up.
enum SleepMorning {
    static let pendingKey = "sleepMorningSession"
    static let introConfirmedKey = "sleepIntroConfirmed"

    /// When the last tap was (the clock time; the session's own seconds leave pauses out).
    static let endedAtKey = "sleepMorningEndedAt"
    /// Set once the app has been in the background since: the card waits for the next open — never
    /// in the same stretch he fell asleep in (owner, sleep-mode-fixes).
    static let armedKey = "sleepMorningArmed"
    /// Older than this and it's no longer "this morning": dropped without a word.
    static let expiresAfter: TimeInterval = 16 * 3600

    static func remember(_ session: SessionDataModel, endedAt: Date, armed: Bool) {
        let d = UserDefaults.standard
        d.set(session.id.uuidString, forKey: pendingKey)
        d.set(endedAt.timeIntervalSince1970, forKey: endedAtKey)
        d.set(armed, forKey: armedKey)
    }
    static var pendingID: UUID? {
        UserDefaults.standard.string(forKey: pendingKey).flatMap(UUID.init(uuidString:))
    }
    static var endedAt: Date? {
        let t = UserDefaults.standard.double(forKey: endedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static var isArmed: Bool { UserDefaults.standard.bool(forKey: armedKey) }
    /// The app went to the background with a card waiting: show it on the next open.
    static func armIfPending() { if pendingID != nil { UserDefaults.standard.set(true, forKey: armedKey) } }
    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: pendingKey); d.removeObject(forKey: endedAtKey); d.removeObject(forKey: armedKey)
    }

    /// The session to show, if it still exists and ended within `expiresAfter` (else the keys go).
    @MainActor static func pending(in context: ModelContext) -> SessionDataModel? {
        guard let id = pendingID else { return nil }
        if let endedAt, Date().timeIntervalSince(endedAt) > expiresAfter { clear(); return nil }
        let found = try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.id == id })).first
        if found == nil { clear() }
        return found
    }
}

// MARK: - The intro

/// The pause screen's explainer pages (sleep mode, stops at goal): one layout, so an (i) always
/// opens the same kind of page (owner, goal-info B: "keep that pattern").
struct ChipIntroPage: View {
    struct Point: Identifiable {
        let symbol: String, title: String, line: String
        var id: String { title }
    }
    let symbol: String
    let title: String
    let subtitle: String
    let points: [Point]
    let primary: String
    let onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: () -> Void = {}
    /// Under the points (or instead of them): the goal page's two cards.
    var extra: AnyView? = nil

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().stroke(Color(.secondarySystemFill), lineWidth: 10).frame(width: 120, height: 120)
                        Image(systemName: symbol)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.sage)
                    }
                    .padding(.top, 40)
                    Text(title)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                    Text(subtitle)
                        .font(.subheadline).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: point.symbol)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.sage)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title).font(.headline.weight(.medium)).fontDesign(.rounded)
                                    Text(point.line).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, points.isEmpty ? 0 : 30)
                    if let extra {
                        extra
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    Button(action: onPrimary) {
                        Text(primary)
                            .font(.headline).fontDesign(.rounded)
                            .foregroundStyle(Color.sage)
                            .frame(maxWidth: 280).frame(height: 50)
                            .background(Capsule().fill(Color.sage.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.sage.opacity(0.5), lineWidth: 1))
                    }
                    if let secondary {
                        Button(action: onSecondary) {
                            Text(secondary)
                                .font(.subheadline).fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
}

struct SleepIntroView: View {
    /// Opened from the chip's (i) with sleep already on: just "Done".
    var isOn = false
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ChipIntroPage(
            symbol: "moon.zzz.fill", title: "Sleep mode", subtitle: "for counting in bed",
            points: [
                .init(symbol: "sun.min", title: "The screen dims",
                      line: "Gentle in the dark. Drag the dimmer on the pause screen."),
                .init(symbol: "hand.tap", title: "Fall asleep counting?",
                      line: "After 45 seconds without a tap, a quiet 10-second countdown — then shukr saves the session, ending at your last tap."),
                .init(symbol: "lock", title: "Your phone locks as usual",
                      line: "Once it's saved, the screen turns off by itself. Locking it yourself while counting saves it the same way."),
                .init(symbol: "sunrise", title: "In the morning",
                      line: "shukr shows what you counted and about when you fell asleep."),
            ],
            primary: isOn ? "Done" : "Turn on sleep mode", onPrimary: isOn ? onNotNow : onTurnOn,
            secondary: isOn ? nil : "Not now", onSecondary: onNotNow)
    }
}

/// The "stops at goal" chip's (i) (owner: "the flexibility to read more than the task at hand, so
/// they don't get stopped at the goal and have to start a new session"). Made from this session:
/// its goal and where it stands, and the two settings as cards side by side — the current one
/// picked, tap the other to switch — each saying how this session would go (owner: no generic
/// lines that could alarm on the default).
struct GoalIntroView: View {
    @Binding var autoStop: Bool
    /// Past the goal on keeps going: switching back is locked (it would end the session at once).
    let locked: Bool
    /// "33" or "10 min" (in the cards' lines; the subtitle carries it too).
    let goal: String
    /// "Alhamdulillah · 12 of 33 so far" — whatever the session knows.
    let subtitle: String
    let onDone: () -> Void

    var body: some View {
        ChipIntroPage(
            symbol: "flag.checkered", title: "How should this session end?", subtitle: subtitle,
            points: [],
            primary: "Done", onPrimary: onDone,
            extra: AnyView(cards))
    }

    private var cards: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                card(stops: true, symbol: "flag.checkered", title: "Stops at goal", kind: "Auto stop",
                     line: "Ends and saves by itself at \(goal).")
                card(stops: false, symbol: "arrow.clockwise", title: "Keeps going", kind: "Manual stop",
                     line: "Carries on past \(goal) — finish with \u{201C}goal reached\u{201D} at the bottom.")
            }
            Text(locked
                 ? "You're past \(goal), so this session keeps going. Finish it from \u{201C}goal reached\u{201D} or the pause screen."
                 : "Tap one to switch. It's for this session only.")
                .font(.footnote).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }

    private func card(stops: Bool, symbol: String, title: String, kind: String, line: String) -> some View {
        let picked = autoStop == stops
        let disabled = locked && stops
        return Button {
            guard !disabled, !picked else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.snappy(duration: 0.2)) { autoStop = stops }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(picked ? Color.sage : Color.primary.opacity(0.7))
                    Spacer()
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(picked ? Color.sage : Color.primary.opacity(0.25))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.weight(.medium)).fontDesign(.rounded)
                        .foregroundStyle(.primary)
                    // What the switch does, in two words (owner).
                    Text(kind)
                        .font(.subheadline.weight(.medium)).fontDesign(.rounded)
                        .foregroundStyle(picked ? Color.sage : Color.secondary)
                }
                Text(line)
                    .font(.footnote).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? Color.sage.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(picked ? Color.sage.opacity(0.6) : Color.clear, lineWidth: 1.2)
            )
            .opacity(disabled ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: - The morning card

/// Drawn over the whole screen (ignoring the safe area, so its coordinates are the screen's): the
/// ring sits exactly on the Salah circle (`WelcomeTarget.circleFrame`), the words above and below it.
struct MorningCardView: View {
    let session: SessionDataModel
    let onDone: () -> Void
    let onHistory: () -> Void
    /// The page (opaque at once under the welcome, which lands on this ring) and, after, its words.
    @State private var pageIn = false
    @State private var shown = false
    /// The Salah look prototype (SalahLook.swift): the soft page and band, like the circle it leaves behind.
    @AppStorage(SalahLook.key) private var lookRaw = SalahLook.today.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = false

    /// The last tap's clock time (stored when it ended); older builds' sessions: start + active time.
    private var ended: Date { SleepMorning.endedAt ?? session.startTime.addingTimeInterval(session.secondsPassed) }
    private var name: String {
        if let m = session.mantra?.name { return m }
        return session.title == "Untitled" || session.title.isEmpty ? "Freestyle" : session.title
    }

    var body: some View {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds
            ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let circle = WelcomeTarget.circleFrame
            ?? CGRect(x: screen.midX - 100, y: screen.midY - 100, width: 200, height: 200)
        ZStack(alignment: .topLeading) {
            Group {
                if SalahLook.tinted(lookRaw, softRing: softRing) { NeuSurface() } else { Color(.systemBackground) }
            }
                .opacity(pageIn ? 1 : 0)
                .contentShape(Rectangle())
            // The Salah circle's own ring, with the count in it.
            ZStack {
                // The Salah circle's own track as it is right now (dashed for a prayer still to
                // come), so the page leaves exactly that circle behind.
                if WelcomeTarget.trackDashed {
                    Circle().stroke(Color.secondary.opacity(UpcomingTrack.opacity), style: UpcomingTrack.style)
                } else if softRing {
                    // Fades with the page: the circle's own band and arc are right under it. Opaque to the end, it
                    // covered the prayer's arc, which then popped in when the card went (owner: "doesnt bring in
                    // the prayer progress right").
                    NeuRingTrack().opacity(pageIn ? 1 : 0)
                } else {
                    Circle().stroke(Color(.secondarySystemFill), lineWidth: 12)
                }
                Circle().stroke(Color.sage.opacity(0.9), lineWidth: 2.5).padding(4.75)
                    .opacity(shown ? 1 : 0)
                VStack(spacing: 2) {
                    Text("\(session.totalCount)")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(name).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 18)
                .opacity(shown ? 1 : 0)
            }
            .frame(width: circle.width, height: circle.height)
            .position(x: circle.midX, y: circle.midY)

            // Above the circle.
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sage)
                Text("You fell asleep counting")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                Text("shukr saved your session")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
            .frame(width: screen.width)
            .position(x: screen.midX, y: circle.minY - 70)
            .opacity(shown ? 1 : 0)

            // Under it: when it ended, the numbers, then the way out.
            VStack(spacing: 0) {
                Text("ended around \(ended.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 17, design: .rounded))
                Text("after your last tap · \(zikrDurationString(session.secondsPassed)) counting")
                    .font(.footnote).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                HStack(spacing: 10) {
                    tile("\(session.totalCount)", "counted")
                    tile(zikrDurationString(session.secondsPassed), "time")
                    tile(session.secondsPerCount.map { String(format: "%.1fs", $0) } ?? "–", "per count")
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                Spacer(minLength: 16)
                Button {
                    triggerSomeVibration(type: .light)
                    finish(then: onDone)
                } label: {
                    Text("Good morning")
                        .font(.headline).fontDesign(.rounded)
                        .foregroundStyle(Color.sage)
                        .frame(width: 210, height: 48)
                        .background(Capsule().fill(Color.sage.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.sage.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    finish(then: onHistory)
                } label: {
                    Text("View in Zikr History")
                        .font(.footnote).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(width: screen.width, height: max(screen.maxY - circle.maxY - 28 - 34, 200))
            .position(x: screen.midX, y: (circle.maxY + 28 + screen.maxY - 34) / 2)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
        .ignoresSafeArea()
        .onAppear {
            CircleCover.set("morningCard", true)
            guard WelcomeTarget.playing || WelcomeGate.curtainUp else {
                withAnimation(.easeOut(duration: 0.5)) { pageIn = true; shown = true }
                return
            }
            pageIn = true   // under the welcome: its ring lands on this one, then the words come in
        }
        .task {
            guard !shown else { return }
            // From the moment the welcome's ring lands: its page fades out as the words fade in.
            while (WelcomeTarget.playing && !WelcomeTarget.landed) || WelcomeGate.curtainUp {
                try? await Task.sleep(for: .milliseconds(50))
            }
            withAnimation(.easeOut(duration: 0.5)) { pageIn = true; shown = true }
        }
        .onDisappear { CircleCover.set("morningCard", false) }
    }

    /// The words and the page fade from round the ring, which stays: what's left is the Salah
    /// circle in the same place (the welcome's landing, backwards).
    private func finish(then go: @escaping () -> Void) {
        // The words and the sage ring first, then the page: the prayer comes in on an empty circle — together, "3 /
        // Freestyle" sat over "Isha / ends …" mid-fade (Sami's audit, finding 5), as the welcome already avoids.
        withAnimation(.easeOut(duration: 0.22)) { shown = false }
        withAnimation(.easeInOut(duration: 0.4).delay(0.18)) { pageIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { go() }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).fontDesign(.rounded).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
