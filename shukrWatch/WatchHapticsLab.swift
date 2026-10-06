//
//  WatchHapticsLab.swift
//  shukrWatch
//
//  Every haptic watchOS lets an app play (WKHapticType — the whole list; SwiftUI's sensoryFeedback plays these same
//  ones on the watch), each a tap away, so the owner can feel them all before choosing a session's (owner, 2026-10-06:
//  "a little dev setting that lets me explore all the different kind of vibrations … then … give the user some
//  granular control on what type of haptic they want in a counting session"). Beta only (WatchBeta: DEBUG / TestFlight).
//

import SwiftUI
import WatchKit

struct WatchHapticsLab: View {
    /// Plays it five times at a quick counting pace, to feel it as counts rather than once.
    @State private var asCounts = false
    @State private var playing: String?

    private struct Haptic: Identifiable {
        let name: String
        let type: WKHapticType
        let note: String
        /// What the counter uses it for today.
        var usedFor: String? = nil
        var id: String { name }
    }

    private let haptics: [Haptic] = [
        Haptic(name: "Click", type: .click, note: "the lightest tap", usedFor: "each count · buttons"),
        Haptic(name: "Direction up", type: .directionUp, note: "a rising tap", usedFor: "each 100 · a phase · done"),
        Haptic(name: "Direction down", type: .directionDown, note: "a falling tap", usedFor: "− · undo / unmark"),
        Haptic(name: "Start", type: .start, note: "a firm single tap"),
        Haptic(name: "Stop", type: .stop, note: "a firm double tap"),
        Haptic(name: "Success", type: .success, note: "a short rising pattern", usedFor: "marked · Qibla lined up"),
        Haptic(name: "Failure", type: .failure, note: "a short falling pattern", usedFor: "a mark the phone refused"),
        Haptic(name: "Retry", type: .retry, note: "three quick taps", usedFor: "counting in sets"),
        Haptic(name: "Notification", type: .notification, note: "the notification tap", usedFor: "session time running out"),
        Haptic(name: "Navigation", type: .navigationGenericManeuver, note: "Maps' generic turn"),
        Haptic(name: "Turn left", type: .navigationLeftTurn, note: "Maps' left turn"),
        Haptic(name: "Turn right", type: .navigationRightTurn, note: "Maps' right turn"),
        Haptic(name: "Depth prompt", type: .underwaterDepthPrompt, note: "a diving prompt"),
        Haptic(name: "Depth critical", type: .underwaterDepthCriticalPrompt, note: "a diving alarm"),
    ]

    var body: some View {
        List {
            Toggle(isOn: $asCounts) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("As counts")
                    Text("five in a row, at counting pace")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(haptics) { h in
                Button { play(h) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(h.name)
                            Spacer()
                            if playing == h.name {
                                Image(systemName: "waveform").foregroundStyle(Color.green)
                            }
                        }
                        Text(h.note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let used = h.usedFor {
                            Text("now: \(used)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.green)
                        }
                    }
                }
            }
            Text("Silent Mode and the watch's Haptic strength (Settings → Sounds & Haptics) change how these feel.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Haptics")
    }

    private func play(_ h: Haptic) {
        playing = h.name
        let times = asCounts ? 5 : 1
        Task { @MainActor in
            for i in 0..<times {
                WKInterfaceDevice.current().play(h.type)
                if i < times - 1 { try? await Task.sleep(for: .milliseconds(450)) }
            }
            try? await Task.sleep(for: .milliseconds(500))
            if playing == h.name { playing = nil }
        }
    }
}
