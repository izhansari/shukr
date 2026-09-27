//
//  NextLabelPlayground.swift
//  shukr
//
//  The "NEXT" tag above a prayer that hasn't started, and a DEBUG playground to tune it (owner,
//  2026-09-27: keeps NEXT on and wants to set its look himself). Settings → My Dev Stuff → NEXT
//  label playground…: offset, size, opacity and letter spacing, applied live to the main circle and
//  the summary's next Fajr (both draw `NextTag`), with Copy values (paste them back to the agent)
//  and Reset. Stored as JSON in standard defaults (`NextLabelTuning.key`); the home-screen widget
//  keeps its own scaled tag.
//

import SwiftUI

struct NextLabelTuning: Codable, Equatable {
    /// Points above the name's top (negative = up).
    /// The owner's playground values (2026-09-27, feedback CC72A6E8).
    var offset: Double = -28.76
    var size: Double = 8.72
    /// Of the tertiary label, scaled from 0.3 (see NextTag).
    var opacity: Double = 0.263
    var tracking: Double = 2.57

    static let key = "nextLabelTuning"
    static let defaults = NextLabelTuning()

    static func decode(_ json: String) -> NextLabelTuning {
        (json.data(using: .utf8)).flatMap { try? JSONDecoder().decode(NextLabelTuning.self, from: $0) } ?? .defaults
    }
    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    var readable: String {
        String(format: "NEXT label — offset %.1f pt, size %.1f pt, opacity %.2f, letter spacing %.1f", offset, size, opacity, tracking)
    }
}

/// "NEXT" over a name, without taking space (an overlay on the name, so the name never moves).
struct NextTag: View {
    var shown = true
    #if DEBUG
    @AppStorage(NextLabelTuning.key) private var tuningJSON = ""
    private var tuning: NextLabelTuning { NextLabelTuning.decode(tuningJSON) }
    #else
    // Release: the fixed defaults, never values a debug install left in the defaults.
    private let tuning = NextLabelTuning.defaults
    #endif

    var body: some View {
        Text("next")
            .font(.system(size: tuning.size, weight: .medium, design: .rounded))
            .tracking(tuning.tracking)
            .textCase(.uppercase)
            // The tertiary label at the default opacity (0.3), scaled from there — `primary` at
            // 0.3 read darker than the `.tertiary` it replaced (review, 2026-09-27).
            .foregroundStyle(Color(uiColor: .tertiaryLabel).opacity(min(tuning.opacity / 0.3, 1)))
            .fixedSize()
            .offset(y: tuning.offset)
            .opacity(shown ? 1 : 0)
    }
}

#if DEBUG
struct NextLabelPlayground: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NextLabelTuning.key) private var tuningJSON = ""
    @State private var t = NextLabelTuning.defaults
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                }
                Section("NEXT label") {
                    slider("Offset", $t.offset, -60...0, "%.1f pt")
                    slider("Size", $t.size, 6...16, "%.1f pt")
                    slider("Opacity", $t.opacity, 0.1...1, "%.2f")
                    slider("Letter spacing", $t.tracking, 0...6, "%.1f")
                }
                Section {
                    Button(copied ? "Copied" : "Copy values", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = t.readable + "\n" + t.json
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) { t = .defaults }
                } footer: {
                    Text("Changes show on the Salah circle and tomorrow's Fajr right away.")
                }
            }
            .navigationTitle("NEXT label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { t = NextLabelTuning.decode(tuningJSON) }
            .onChange(of: t) { _, new in tuningJSON = new.json }
        }
    }

    /// The main circle's layout at its real size: dashed track, NEXT, icon + name, caption.
    private var preview: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise").font(.system(size: 22, weight: .light))
                    Text("Fajr").font(.system(size: 32, weight: .light, design: .rounded))
                }
                .foregroundStyle(Color.primary.opacity(0.55))
                .overlay(alignment: .top) { NextTag() }
                Text("in 8h 5m")
                    .font(.subheadline).fontWeight(.thin).foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
#endif
