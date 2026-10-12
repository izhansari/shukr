//
//  LiveActivitySetupStep.swift
//  shukr
//
//  The setup page for prayer Live Activities, built like the notifications and Fajr alarm pages: the real card in the
//  sage preview, iOS's answer checked the same way, the prayers to show as tiles once it's on. Not in the setup yet
//  (owner, 2026-10-11: "Don't actually put this page in the onboarding yet. I just want to fix it up") — DEBUG opens it
//  from Settings → My Dev Stuff → Live Activity setup page, or `-demoLiveActivityStep`. Every word is in
//  `LASetupCopy`, which the ⚙ (DEBUG) edits live, with a "Preview as" to see each state on one phone.
//
//  Before iOS 26 (scheduled starts need it) the page still shows, with the card frosted over and "Coming with iOS 26":
//  they learn it's there for when they update (owner: "it might be nice for them to know").
//

import SwiftUI
import ActivityKit

struct LiveActivitySetupStep: View {
    let next: () -> Void
    @State private var copy = LASetupCopy.shared
    @Environment(\.scenePhase) private var scenePhase
    /// iOS's switch for shukr's Live Activities (Settings → shukr → Live Activities); on unless they turned it off.
    @State private var enabled = LiveActivitySetupStep.systemEnabled
    /// Their answer on this page: nil not asked, true show them, false not.
    @State private var answer: Bool? = nil
    /// "No thanks" asks once more, as the notifications and the alarm do (owner).
    @State private var confirmSkip = false
    /// The prayer the preview shows once the tiles are up: the last tile tapped (Asr to begin).
    @State private var focus = "Asr"
    @State private var prefs: [String: Bool] = LiveActivitySetupStep.savedPrefs
    /// The page's states; `real` (only as "Preview as") follows the phone.
    enum Mode: String, CaseIterable, Identifiable {
        case real = "Real", ask = "Ask", on = "On", declined = "Said no", off = "Off in Settings", old = "Before iOS 26"
        var id: String { rawValue }
    }

    static var systemEnabled: Bool { PrayerLiveActivities.supported && ActivityAuthorizationInfo().areActivitiesEnabled }
    static var savedPrefs: [String: Bool] {
        Dictionary(uniqueKeysWithValues: LiveActivityPrefs.prayers.map { ($0, LiveActivityPrefs.isOn($0)) })
    }

    private var mode: Mode {
        if copy.preview != .real { return copy.preview }
        if !PrayerLiveActivities.supported { return .old }
        if !enabled { return .off }
        switch answer {
        case true?: return .on
        case false?: return .declined
        case nil: return .ask
        }
    }

    var body: some View {
        let m = mode
        // Laid out as the notifications page: the card in the middle of the free space while it's alone, gliding up as
        // the tiles come in under it once it's on. Scrolls only if a small screen needs it.
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        StepTitle(title: copy[.title], subtitle: copy[.subtitle])
                            .padding(.bottom, 22)
                        if m != .on { Spacer(minLength: 0) }
                        LiveActivityDemo(prayer: m == .on ? focus : "Asr", veil: m == .off ? .off : m == .old ? .old : m == .declined ? .declined : .none,
                                         copy: copy)
                            .padding(.horizontal, 24)
                        if m == .on {
                            VStack(spacing: 0) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 32, height: 3)
                                    .padding(.top, 18).padding(.bottom, 16)
                                tiles
                            }
                            .transition(.opacity.combined(with: .offset(y: 16)))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            buttons(m)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.45), value: m)
        .alert(copy[.skipTitle], isPresented: $confirmSkip) {
            Button(copy[.skipKeep], role: .cancel, action: turnOn)
            Button(copy[.skipAnyway], role: .destructive, action: turnOff)
        } message: {
            Text(copy[.skipBody])
        }
        .task { await watchSwitch() }
        // Back from Settings: their switch may have changed.
        .onChange(of: scenePhase) { _, phase in if phase == .active { enabled = Self.systemEnabled } }
    }

    @ViewBuilder private func buttons(_ m: Mode) -> some View {
        VStack(spacing: 0) {
            switch m {
            case .ask, .real:
                PrimaryButton(title: copy[.yes], outlined: true, action: turnOn)
                SecondaryButton(title: copy[.no]) { confirmSkip = true }
            case .on:
                PrimaryButton(title: "Continue", action: next)
            case .declined:
                // Said no: the card says what that means, frosted over; the way on is outlined, a change of mind quiet.
                PrimaryButton(title: copy[.declinedContinue], outlined: true, action: next)
                SecondaryButton(title: copy[.declinedUndo], action: turnOn)
            case .off:
                // iOS has them off: the card says it, frosted over; the way on is outlined, Settings the quiet way back.
                PrimaryButton(title: copy[.offContinue], outlined: true, action: next)
                SecondaryButton(title: copy[.offSettings], action: SettingsLinks.app)
            case .old:
                PrimaryButton(title: "Continue", action: next)
            }
        }
    }

    /// Which prayers show one: a tile each, on or off (the same keys as Settings → Live Activities).
    private var tiles: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(copy[.tilesHeader])
                    .font(.system(.headline, design: .rounded))
                Text(copy[.tilesBody])
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(LiveActivityPrefs.prayers, id: \.self) { p in
                    LiveActivityTile(prayer: p, isOn: prefs[p] ?? false) { set(p, on: !(prefs[p] ?? false)) }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// "Show my prayers": on, the prayers as set (Dhuhr, Asr and Maghrib unless changed), the next windows planned now —
    /// iOS asks its own "Allow Live Activities?" the first time one shows. After a "no", the tiles come back as they were.
    private func turnOn() {
        if answer == false, copy.preview == .real {
            let group = UserDefaults(suiteName: SharedStore.appGroup)
            for p in LiveActivityPrefs.prayers { group?.removeObject(forKey: LiveActivityPrefs.key(p)) }
            prefs = Self.savedPrefs
        }
        withAnimation(.easeInOut(duration: 0.45)) { answer = true }
        if copy.preview == .real { PrayerLiveActivities.plan(reason: "setup") }
    }

    /// "Skip it": every prayer off (Settings turns them back on); the page stays, frosted, until Continue.
    private func turnOff() {
        withAnimation(.easeInOut(duration: 0.45)) { answer = false }
        guard copy.preview == .real else { return }
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        for p in LiveActivityPrefs.prayers { group?.set(false, forKey: LiveActivityPrefs.key(p)) }
        prefs = Self.savedPrefs
        PrayerLiveActivities.plan(reason: "setup skipped")
    }

    private func set(_ prayer: String, on: Bool) {
        focus = prayer
        prefs[prayer] = on
        guard copy.preview == .real else { return }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(on, forKey: LiveActivityPrefs.key(prayer))
        PrayerLiveActivities.plan(reason: "setup tile")
    }

    /// iOS's switch as it changes while the page is up (it can be flipped from Control Center's Settings, or the Lock
    /// Screen's own "Don't Allow").
    private func watchSwitch() async {
        guard PrayerLiveActivities.supported else { return }
        for await on in ActivityAuthorizationInfo().activityEnablementUpdates {
            withAnimation(.easeInOut(duration: 0.45)) { enabled = on }
        }
    }
}

/// One prayer as a tile, the notifications' tile with two states (owner: "very similar to the component that we use for
/// notifications"): the name, the Lock Screen card symbol (slashed when off), On / Off — solid sage when on, grey off. A
/// tap flips it and puts that prayer in the card above.
private struct LiveActivityTile: View {
    let prayer: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            toggle()
            triggerSomeVibration(type: .light)
        } label: {
            VStack(spacing: 6) {
                Text(prayer)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: isOn ? "platter.filled.bottom.iphone" : "iphone.slash")
                    .font(.system(size: 18))
                    .contentTransition(.symbolEffect(.replace))
                Text(isOn ? "On" : "Off")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.sage : Color(.secondarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isOn ? 0 : 0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityLabel("\(prayer) on the Lock Screen")
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// The real card (the Live Activity's own `LALockCardBody`, shared with the widget) in the setup's sage card, going
/// through a prayer's life: it starts, counts down, turns red in the last half hour, and is marked (Photo / Tasbih) —
/// the step under it lit as it goes. iOS off or too old: frosted over with what that means.
struct LiveActivityDemo: View {
    let prayer: String
    enum Veil { case none, declined, off, old }
    let veil: Veil
    let copy: LASetupCopy
    /// The card's look; nil = the Card look setting (`LiveActivityLook`) for this prayer, else the phone's. Settings'
    /// Card look page passes the one being picked (Sami, 2026-10-12).
    var look: ColorScheme? = nil
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the current run began (the card's timers count from now, so the window is laid round the clock each frame).
    @State private var runStart = Date()
    private let t = LATuning.current

    private var steps: [String] { [copy[.stepStart], copy[.stepLive], copy[.stepLast], copy[.stepDone]] }

    /// ONE card living through its window (owner, 2026-10-12: "one dynamic card … progressively change", not snapshots
    /// cross-fading): a 140-minute window played in ~9 s — it starts, the ring fills and the time left counts down, turns
    /// red in the last half hour — then it's marked (a fade: the real card changes there too), and it begins again.
    private static let window = 140.0                       // minutes
    private static let run: [(at: Double, minute: Double)] = [(0, 0), (1.2, 3), (6.6, 110), (9.0, 124)]   // seconds → minute
    private static let markedFor = 3.4
    private static var cycle: Double { run.last!.at + markedFor }

    /// The window's minute at `s` seconds into the run (eased between the marks above); nil once marked.
    private static func minute(at s: Double) -> Double? {
        guard s < run.last!.at else { return nil }
        for (a, b) in zip(run, run.dropFirst()) where s < b.at {
            let x = (s - a.at) / (b.at - a.at)
            let eased = x * x * (3 - 2 * x)
            return a.minute + (b.minute - a.minute) * eased
        }
        return run.last!.minute
    }

    private func state(at now: Date, minute: Double?) -> PrayerWindowAttributes.ContentState {
        let m = 60.0, sym = prayerIcon(for: prayer)
        guard let minute else {   // marked early in its window: Perfect, its green glow
            let start = now.addingTimeInterval(-24 * m)
            return .init(label: prayer, start: start, end: start.addingTimeInterval(Self.window * m), symbol: sym,
                         markedAt: start.addingTimeInterval(22 * m))
        }
        let start = now.addingTimeInterval(-minute * m)
        return .init(label: prayer, start: start, end: start.addingTimeInterval(Self.window * m), symbol: sym)
    }

    private func step(_ minute: Double?) -> Int {
        guard let minute else { return 3 }
        return minute < 3 ? 0 : minute < Self.window - 30 ? 1 : 2
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || veil != .none)) { ctx in
            let s = reduceMotion ? 3.5 : ctx.date.timeIntervalSince(runStart).truncatingRemainder(dividingBy: Self.cycle)
            let minute = Self.minute(at: max(s, 0))
            content(state: state(at: ctx.date, minute: minute), phase: step(minute))
        }
        .overlay { veilView }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(veil == .off ? "\(copy[.offTitle]). \(copy[.offBody])"
                            : veil == .declined ? "\(copy[.declinedTitle]). \(copy[.declinedBody])"
                            : veil == .old ? "\(copy[.oldTitle]). \(copy[.oldBody])"
                            : "\(prayer) on the Lock Screen: time left in a ring, and a button to mark it prayed.")
        .task(id: prayer) { runStart = Date() }
        .animation(.snappy(duration: 0.25), value: prayer)
    }

    private func content(state: PrayerWindowAttributes.ContentState, phase: Int) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                // Which prayer this is, and where it shows — as the other pages label their card.
                HStack(spacing: 6) {
                    Text(prayer).fontWeight(.semibold)
                    Text("·")
                    Text(copy[.cardLabel])
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.7))
                .padding(.leading, 4)
                .contentTransition(.opacity)
                ZStack {
                    LALockCardBody(state: state, n: 0, ended: false, t: t)
                        .environment(\.colorScheme, look ?? LiveActivityLook.current.dark(for: prayer).map { $0 ? .dark : .light } ?? systemScheme)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .id("\(prayer)-\(state.markedAt == nil)")   // the same card all through; only marking swaps it
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.5), value: state.markedAt == nil)
                // Only a picture: its buttons would run the real intents.
                .allowsHitTesting(false)
                .padding(.bottom, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color.sage.opacity(0.55), Color.sage.opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            // The steps of a prayer's card; the one showing in sage.
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(.system(.caption, design: .rounded, weight: i == phase ? .semibold : .regular))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                        .foregroundStyle(i == phase ? Color.sage : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var veilView: some View {
            if veil != .none {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .padding(-8)
                    VStack(spacing: 6) {
                        Image(systemName: veil == .old ? "iphone.gen3" : "iphone.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        Text(copy[veil == .off ? .offTitle : veil == .declined ? .declinedTitle : .oldTitle])
                            .font(.system(.headline, design: .rounded))
                        Text(copy[veil == .off ? .offBody : veil == .declined ? .declinedBody : .oldBody])
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                }
                // Off: a tap goes where the words say (Settings → shukr). Too old: nothing to open.
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous).inset(by: -8))
                .onTapGesture { if veil == .off { SettingsLinks.app() } }
                .transition(.opacity)
            }
    }
}

/// Every word on the page, editable live from the ⚙ (owner: "add a tuner setting … so that I can go ahead and change
/// the copy"). Changes are kept on this phone (UserDefaults) until they're copied into the defaults below.
@MainActor @Observable final class LASetupCopy {
    static let shared = LASetupCopy()

    enum Key: String, CaseIterable, Identifiable {
        case title, subtitle, cardLabel, stepStart, stepLive, stepLast, stepDone
        case yes, no, tilesHeader, tilesBody
        case skipTitle, skipBody, skipKeep, skipAnyway
        case declinedTitle, declinedBody, declinedContinue, declinedUndo
        case offTitle, offBody, offContinue, offSettings
        case oldTitle, oldBody
        var id: String { rawValue }

        /// Where it shows, for the tuner's sections.
        var group: String {
            switch self {
            case .title, .subtitle: return "Top"
            case .cardLabel, .stepStart, .stepLive, .stepLast, .stepDone: return "The card"
            case .yes, .no, .tilesHeader, .tilesBody: return "Asking, then on"
            case .skipTitle, .skipBody, .skipKeep, .skipAnyway: return "No thanks (the alert)"
            case .declinedTitle, .declinedBody, .declinedContinue, .declinedUndo: return "After a no (frosted)"
            case .offTitle, .offBody, .offContinue, .offSettings: return "Off in iOS Settings"
            case .oldTitle, .oldBody: return "Before iOS 26"
            }
        }

        var name: String {
            switch self {
            case .title: return "Title"
            case .subtitle: return "Subtitle"
            case .cardLabel: return "Card label (after the prayer's name)"
            case .stepStart: return "Step 1"
            case .stepLive: return "Step 2"
            case .stepLast: return "Step 3"
            case .stepDone: return "Step 4"
            case .yes: return "Yes button"
            case .no: return "No button"
            case .tilesHeader: return "Tiles header"
            case .tilesBody: return "Tiles line"
            case .skipTitle: return "Alert title"
            case .skipBody: return "Alert message"
            case .skipKeep: return "Alert: keep"
            case .skipAnyway: return "Alert: skip"
            case .declinedTitle: return "Frost title"
            case .declinedBody: return "Frost line"
            case .declinedContinue: return "Continue button"
            case .declinedUndo: return "Change of mind"
            case .offTitle: return "Frost title"
            case .offBody: return "Frost line"
            case .offContinue: return "Continue button"
            case .offSettings: return "Settings link"
            case .oldTitle: return "Frost title"
            case .oldBody: return "Frost line"
            }
        }

        static let groups = ["Top", "The card", "Asking, then on", "No thanks (the alert)", "After a no (frosted)", "Off in iOS Settings", "Before iOS 26"]
    }

    /// The words as shipped. Kept honest about what it does (the audit, 2026-10-11): a card shows from a prayer's
    /// start until it's marked, and marking or opening shukr keeps the next ones coming.
    static let defaults: [Key: String] = [
        .title: "On your Lock Screen",
        .subtitle: "From the moment a prayer starts, see how long is left at a glance, and mark it prayed without opening shukr.",
        .cardLabel: "Lock Screen",
        .stepStart: "Starts",
        .stepLive: "Counts down",
        .stepLast: "Last 30 min",
        .stepDone: "Marked",
        .yes: "Show my prayers",
        .no: "No thanks, I’ll check the app",
        .tilesHeader: "Which prayers?",
        .tilesBody: "We show the daytime prayers, the ones a busy day pushes back. Each shows from its start until you mark it, and marking them keeps the next ones coming.",
        .skipTitle: "Go without Live Activities?",
        .skipBody: "You’d lose the countdown on your Lock Screen and marking a prayer from there. Your reminders still come either way.",
        .skipKeep: "Show my prayers",
        .skipAnyway: "Skip it",
        .declinedTitle: "No Live Activities",
        .declinedBody: "You’ll open shukr to see how long is left in a prayer. Turn them on any time in Settings.",
        .declinedContinue: "Continue without them",
        .declinedUndo: "I changed my mind",
        .offTitle: "Live Activities are off",
        .offBody: "iOS has them turned off for shukr. Turn them on in Settings any time.",
        .offContinue: "Continue without them",
        .offSettings: "I changed my mind. Open Settings",
        .oldTitle: "Coming with iOS 26",
        .oldBody: "Your iPhone needs iOS 26 for this. Once you update, it’s waiting for you in Settings.",
    ]

    private static let storeKey = "laSetupCopy.v1"
    private static let previewKey = "laSetupCopy.preview"

    /// His changes (only what differs from the defaults).
    private(set) var changed: [String: String]
    /// "Preview as": the state the page shows (Real follows the phone).
    var preview: LiveActivitySetupStep.Mode {
        didSet { UserDefaults.standard.set(preview.rawValue, forKey: Self.previewKey) }
    }

    private init() {
        changed = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: String] ?? [:]
        #if DEBUG
        preview = LiveActivitySetupStep.Mode(rawValue: UserDefaults.standard.string(forKey: Self.previewKey) ?? "") ?? .real
        #else
        preview = .real
        #endif
    }

    subscript(_ key: Key) -> String { changed[key.rawValue] ?? Self.defaults[key] ?? "" }

    func isChanged(_ key: Key) -> Bool { changed[key.rawValue] != nil }

    func set(_ key: Key, _ text: String) {
        if text == Self.defaults[key] { changed[key.rawValue] = nil } else { changed[key.rawValue] = text }
        UserDefaults.standard.set(changed, forKey: Self.storeKey)
    }

    func reset() {
        changed = [:]
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
    }

    /// Every changed line, ready to paste to the team.
    var summary: String {
        let lines = Key.allCases.compactMap { k -> String? in
            guard let v = changed[k.rawValue] else { return nil }
            return "\(k.group) · \(k.name): \(v)"
        }
        return lines.isEmpty ? "Live Activity page: no changes from the defaults." : "Live Activity page copy:\n" + lines.joined(separator: "\n")
    }
}

#if DEBUG
/// The ⚙'s sheet: every line of the page as a text field (green = changed), "Preview as" to see each state, Copy and
/// Reset. Half height, so the page stays in view and changes as he types.
struct LASetupCopyPanel: View {
    @State private var copy = LASetupCopy.shared
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Preview as", selection: Bindable(copy).preview) {
                        ForEach(LiveActivitySetupStep.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    Text("Real follows this phone. The others show that state with nothing saved or scheduled.")
                }
                ForEach(LASetupCopy.Key.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(LASetupCopy.Key.allCases.filter { $0.group == group }) { k in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(k.name)
                                    .font(.caption)
                                    .foregroundStyle(copy.isChanged(k) ? Color.sage : .secondary)
                                TextField(LASetupCopy.defaults[k] ?? "", text: Binding(get: { copy[k] }, set: { copy.set(k, $0) }),
                                          axis: .vertical)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                Section {
                    Button("Copy changes") { UIPasteboard.general.string = copy.summary; copied = true }
                    Button("Reset to defaults", role: .destructive) { copy.reset() }
                }
            }
            .navigationTitle("Live Activity page words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Copied", isPresented: $copied) { Button("OK") {} } message: { Text("Paste them to Frank.") }
        }
    }
}

/// The page on its own, for looking at it (DEBUG): ✕ closes, and so does its Continue.
struct LiveActivitySetupPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyTuner = false

    /// Where it would sit in the setup: after notifications, before the Fajr alarm (the ring between theirs).
    static let progress = (SetupStep.reminders.progress + SetupStep.fajr.progress) / 2
    static let symbol = "platter.filled.bottom.iphone"

    var body: some View {
        // The setup's own top (FirstRunSetupView): the bar (✕ where its back chevron is, the ⚙ where Skip is), then the
        // ring with the step's symbol and progress, then the step.
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
                Button { showCopyTuner = true } label: {
                    Image(systemName: "gearshape").font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Edit this page's words")
            }
            .tint(.primary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            SetupRing(progress: Self.progress, symbol: Self.symbol)
                .padding(.top, 4)
            LiveActivitySetupStep(next: { dismiss() })
        }
        .sheet(isPresented: $showCopyTuner) {
            LASetupCopyPanel()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}
#endif
