//
//  MarkLogPage.swift
//  shukr
//
//  My Dev Stuff → Mark log (DEBUG): every prayer mark from anywhere (MarkLog, WidgetMarks.swift), so a week of real use on
//  his phone shows which ways of marking are reliable (owner, 2026-10-22: "test it out throughout the week or something and
//  see on a real device which marking mediums work and which tend to have issues"). On top, each source's count: marked,
//  not marked, and how many got a location; under it every line, newest first. Share sends the file; Clear starts over.
//

#if DEBUG
import SwiftUI

struct MarkLogPage: View {
    @State private var lines: [String] = []
    @State private var confirmClear = false

    /// Per source: marked, not marked (anything else but an unmark), marked with a location.
    private struct Tally: Identifiable {
        let source: String
        var marked = 0, notMarked = 0, located = 0
        var id: String { source }
    }

    private var tallies: [Tally] {
        var by: [String: Tally] = [:]
        for line in lines {
            // "Oct 22 13:05:41  [app] widget ✓ · Dhuhr (…) → marked · …"
            guard let close = line.range(of: "] "), let dot = line.range(of: " · ", range: close.upperBound..<line.endIndex),
                  let arrow = line.range(of: " → ") else { continue }
            let source = String(line[close.upperBound..<dot.lowerBound])
            let result = line[arrow.upperBound...]
            var t = by[source] ?? Tally(source: source)
            if result.hasPrefix("marked") {
                t.marked += 1
                if line.contains("location: this phone's fix") || line.contains("location: the app's last fix") { t.located += 1 }
            } else if result.hasPrefix("not marked") || result.hasPrefix("NOT marked") {
                t.notMarked += 1
            }
            by[source] = t
        }
        return by.values.sorted { $0.marked + $0.notMarked > $1.marked + $1.notMarked }
    }

    var body: some View {
        List {
            Section {
                if tallies.isEmpty {
                    Text("Nothing marked yet. Mark a prayer from a widget, the Live Activity, a notification, Siri, Control Center or the watch.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(tallies) { t in
                    HStack {
                        Text(t.source)
                        Spacer()
                        Text("\(t.marked) marked · \(t.located) with a place" + (t.notMarked > 0 ? " · \(t.notMarked) not" : ""))
                            .foregroundStyle(t.notMarked > 0 ? Color.orange : Color.secondary)
                    }
                    .font(.footnote)
                }
            } header: { Text("By source") } footer: {
                Text("\"With a place\": a location was saved at the mark. A widget mark can also get one a few seconds later (its own line).")
            }
            Section("Every mark, newest first") {
                ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.contains("NOT marked") || line.contains("⚠︎") ? Color.orange : Color.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Mark log")
        .toolbar {
            if let url = MarkLog.url, !lines.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { confirmClear = true }.disabled(lines.isEmpty)
            }
        }
        .confirmationDialog("Clear the mark log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                if let url = MarkLog.url { try? FileManager.default.removeItem(at: url) }
                read()
            }
        }
        .onAppear(perform: read)
        .refreshable { read() }
    }

    private func read() {
        guard let url = MarkLog.url, let text = try? String(contentsOf: url, encoding: .utf8) else { lines = []; return }
        lines = text.split(separator: "\n").map(String.init)
    }
}
#endif
