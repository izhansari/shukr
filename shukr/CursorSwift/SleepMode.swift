//
//  SleepMode.swift
//  shukr
//
//  Tasbeeh sleep mode (owner, 2026-09-30, ideas F3BR + 4WTV, ask sleep-mode):
//  - `SleepIntroView`: the first time the sleep chip is turned on, a full-page sheet explains it;
//    "Turn on sleep mode" turns it on and never shows the sheet again, "Not now" leaves it off and
//    shows it again next time (decision sleep-intro A, no (i)).
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

struct SleepIntroView: View {
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().stroke(Color(.secondarySystemFill), lineWidth: 10).frame(width: 120, height: 120)
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.sage)
                    }
                    .padding(.top, 40)
                    Text("Sleep mode")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .padding(.top, 22)
                    Text("for counting in bed")
                        .font(.subheadline).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 18) {
                        point("sun.min", "The screen dims",
                              "Gentle in the dark. Drag the dimmer on the pause screen.")
                        point("hand.tap", "Fall asleep counting?",
                              "After 45 seconds without a tap, a quiet 10-second countdown — then shukr saves the session, ending at your last tap.")
                        point("lock", "Your phone locks as usual",
                              "Once it's saved, the screen turns off by itself. Locking it yourself while counting saves it the same way.")
                        point("sunrise", "In the morning",
                              "shukr shows what you counted and about when you fell asleep.")
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    Button(action: onTurnOn) {
                        Text("Turn on sleep mode")
                            .font(.headline).fontDesign(.rounded)
                            .foregroundStyle(Color.sage)
                            .frame(maxWidth: 280).frame(height: 50)
                            .background(Capsule().fill(Color.sage.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.sage.opacity(0.5), lineWidth: 1))
                    }
                    Button(action: onNotNow) {
                        Text("Not now")
                            .font(.subheadline).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
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

    private func point(_ symbol: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.sage)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline.weight(.medium)).fontDesign(.rounded)
                Text(line).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            Color(.systemBackground)
                .opacity(pageIn ? 1 : 0)
                .contentShape(Rectangle())
            // The Salah circle's own ring, with the count in it.
            ZStack {
                // The Salah circle's own track as it is right now (dashed for a prayer still to
                // come), so the page leaves exactly that circle behind.
                if WelcomeTarget.trackDashed {
                    Circle().stroke(Color.secondary.opacity(UpcomingTrack.opacity), style: UpcomingTrack.style)
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
        withAnimation(.easeInOut(duration: 0.45)) { shown = false; pageIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { go() }
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
