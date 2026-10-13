//
//  TourCopyTuner.swift
//  shukr
//
//  The tour's words, editable on the phone with the panel drawn as it will look (owner, 2026-10-13: "a tuner where I can
//  adjust the copy and see what it will look like … put it next to the app tour in Settings"). Edits are kept on this
//  phone only (UserDefaults), laid over TourCopy wherever the tour shows its words; "Copy changes" puts them on the
//  clipboard (original → new) to be baked into TourCopy.swift. Beta builds only (WhatsNewAccess.beta).
//

import SwiftUI

/// The edits, keyed by the original words.
@MainActor @Observable final class TourCopyStore {
    static let shared = TourCopyStore()
    private static let key = "tourCopy.overrides"
    private(set) var overrides: [String: String] =
        (UserDefaults.standard.dictionary(forKey: TourCopyStore.key) as? [String: String]) ?? [:]

    /// The words as they show: the edit, else the original.
    func t(_ original: String) -> String { overrides[original] ?? original }

    func set(_ original: String, _ new: String) {
        if new == original || new.isEmpty { overrides.removeValue(forKey: original) } else { overrides[original] = new }
        UserDefaults.standard.set(overrides, forKey: Self.key)
    }

    func resetAll() {
        overrides = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// For pasting into chat: each change, original then new.
    var exportText: String {
        overrides.sorted { $0.key < $1.key }
            .map { "• \($0.key)\n  → \($0.value)" }
            .joined(separator: "\n\n")
    }
}

extension TourPage {
    /// Every string with its edit laid over it.
    func applyingCopy() -> TourPage {
        let s = TourCopyStore.shared
        var p = self
        p.subline = subline.map(s.t)
        p.tasks = tasks.map(s.t)
        p.insight = insight.map(s.t)
        p.sections = sections.map { sec in
            var sec = sec
            sec.lead = sec.lead.map(s.t)
            sec.note = sec.note.map(s.t)
            sec.tasks = sec.tasks.map(s.t)
            sec.todoLeads = sec.todoLeads.map(s.t)
            sec.todoAfters = sec.todoAfters.map(s.t)
            sec.blocks = sec.blocks.map { b in
                TourBlock(lead: b.lead.map(s.t), items: b.items.map(s.t), colours: b.colours, numbered: b.numbered, pairs: b.pairs)
            }
            return sec
        }
        return p
    }

    /// Every original string on the page that the tuner can edit, in reading order (to-do screens: only that to-do's).
    func editableStrings(todo: Int?) -> [String] {
        var out: [String] = []
        if let subline { out.append(subline) }
        for sec in sections where !sec.done {
            if let todo, !sec.tasks.isEmpty {
                if sec.todoLeads.indices.contains(todo) { out.append(sec.todoLeads[todo]) }
                if sec.tasks.indices.contains(todo) { out.append(sec.tasks[todo]) }
                if sec.todoAfters.indices.contains(todo), !sec.todoAfters[todo].isEmpty { out.append(sec.todoAfters[todo]) }
                continue
            }
            if let lead = sec.lead { out.append(lead) }
            for b in sec.blocks {
                if let lead = b.lead { out.append(lead) }
                out.append(contentsOf: b.items)
            }
            out.append(contentsOf: sec.tasks)
            if let note = sec.note { out.append(note) }
        }
        out.append(contentsOf: tasks)
        if let insight { out.append(insight) }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// One screen of the tour, as the tuner shows it.
struct TourCopyScreen: Identifiable {
    let id: String
    let title: String
    let step: TourStep
    let phase: TourPhase
    var ticked: Set<Int> = []
    /// A to-do screen: which one (drawn before, and held after).
    var todo: Int? = nil
    /// Extra words not on a page (the editor's, the skip alert's).
    var extra: [String] = []
}

/// Settings → Tours → Tour copy (beta).
struct TourCopyTuner: View {
    @State private var store = TourCopyStore.shared
    @State private var copied = false
    @State private var confirmReset = false

    private var screens: [TourCopyScreen] {
        var s: [TourCopyScreen] = [
            .init(id: "intro", title: "Welcome", step: .intro, phase: .learn),
            .init(id: "circle.learn", title: "1 · What it shows", step: .circle, phase: .learn),
        ]
        for i in TourCopy.Circle.todos.indices {
            s.append(.init(id: "circle.\(i)", title: "1 · To-do \(i + 1)", step: .circle, phase: .tryIt,
                           ticked: Set(0..<i), todo: i))
        }
        s.append(.init(id: "circle.marked", title: "2 · Swipe up", step: .circle, phase: .tryIt, ticked: [0, 1, 2]))
        s.append(.init(id: "list.learn", title: "2 · From here you can", step: .list, phase: .learn))
        for i in TourCopy.List.todos.indices {
            s.append(.init(id: "list.\(i)", title: "2 · To-do \(i + 1)", step: .list, phase: .tryIt,
                           ticked: Set(0..<i), todo: i))
        }
        s.append(.init(id: "list.editor", title: "2 · Time editor", step: .list, phase: .tryIt, ticked: [0, 1, 2],
                       extra: [TourCopy.List.editorLine] + TourCopy.List.editorTodos))
        s.append(.init(id: "list.end", title: "2 · That's your day", step: .list, phase: .tryIt, ticked: [0, 1, 2, 3]))
        s.append(.init(id: "settings.go", title: "3 · Get there", step: .settings, phase: .go))
        s.append(.init(id: "settings.learn", title: "3 · What you set here", step: .settings, phase: .learn))
        for i in TourCopy.Settings.todos.indices {
            s.append(.init(id: "settings.\(i)", title: "3 · To-do \(i + 1)", step: .settings, phase: .tryIt,
                           ticked: Set(0..<i), todo: i))
        }
        s.append(.init(id: "settings.last", title: "Tour complete", step: .settings, phase: .last))
        s.append(.init(id: "skip", title: "Skip alert", step: .circle, phase: .learn,
                       extra: [TourCopy.Skip.alertTitle, TourCopy.Skip.alertLine, TourCopy.Skip.alertKeep, TourCopy.Skip.alertSkip]))
        return s
    }

    var body: some View {
        List {
            Section {
                Text("Edit any line and the panel above it changes. Edits stay on this phone; tap Copy changes and paste them to Frank.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button(copied ? "Copied" : "Copy changes (\(store.overrides.count))") {
                        UIPasteboard.general.string = store.exportText
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    .disabled(store.overrides.isEmpty)
                    Spacer()
                    Button("Reset all", role: .destructive) { confirmReset = true }
                        .disabled(store.overrides.isEmpty)
                }
                .buttonStyle(.borderless)
            }
            ForEach(screens) { screen in
                Section(screen.title) { ScreenEditor(screen: screen) }
            }
        }
        .navigationTitle("Tour copy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset every edit?", isPresented: $confirmReset) {
            Button("Keep", role: .cancel) {}
            Button("Reset", role: .destructive) { store.resetAll() }
        }
    }
}

/// One screen: the panel drawn with the edits (before, and held after for a to-do), then its words to edit.
private struct ScreenEditor: View {
    let screen: TourCopyScreen
    private var store: TourCopyStore { .shared }

    private var raw: TourPage { TourRuntime.previewPage(screen.step, screen.phase, ticked: screen.ticked, pending: nil) }
    private var strings: [String] {
        (screen.id == "skip" ? [] : raw.editableStrings(todo: screen.todo)) + screen.extra
    }

    var body: some View {
        VStack(spacing: 10) {
            if screen.id == "skip" {
                VStack(spacing: 4) {
                    Text(store.t(TourCopy.Skip.alertTitle)).font(.headline)
                    Text(store.t(TourCopy.Skip.alertLine)).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text(store.t(TourCopy.Skip.alertKeep))
                        Spacer()
                        Text(store.t(TourCopy.Skip.alertSkip)).foregroundStyle(.red)
                    }
                    .font(.callout).padding(.top, 6)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemFill)))
            } else if screen.id == "list.editor" {
                TourEditorPanel()
            } else if screen.step == .intro {
                TourPageView(step: .intro, page: raw.applyingCopy(), place: nil, ticked: [], lit: [], openSection: nil,
                             showsBack: false, qiblaSkip: false, onPrimary: {}, onSecondary: {}, onBack: {},
                             onToggle: { _ in }, onSkipQibla: {})
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.tertiarySystemFill)))
                    .allowsHitTesting(false)
            } else {
                preview(raw.applyingCopy())
                if let i = screen.todo {
                    let held = TourRuntime.previewPage(screen.step, screen.phase, ticked: screen.ticked.union([i]), pending: i)
                    if held.pendingTodo != nil {
                        Text("Once done").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        preview(held.applyingCopy())
                    }
                }
            }
            ForEach(strings, id: \.self) { original in
                CopyField(original: original)
            }
        }
        .padding(.vertical, 4)
    }

    private func preview(_ page: TourPage) -> some View {
        TourTopPanel(page: page, mode: TourGuideMode.of(page, key: "tuner." + screen.id), guideKey: "tuner." + screen.id,
                     ticked: screen.ticked.union(page.pendingTodo.map { [$0] } ?? []), nudges: 0, showsBack: true,
                     qiblaSkip: false, openSection: nil, lit: [], step: screen.step, place: nil,
                     onPrimary: {}, onSecondary: {}, onBack: {}, onToggle: { _ in }, onSkipQibla: {}, onSkip: {})
            .allowsHitTesting(false)
    }
}

/// One line: edited in place, the original shown under it once changed (tap ↺ to put it back).
private struct CopyField: View {
    let original: String
    @State private var text = ""
    private var store: TourCopyStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                TextField("", text: $text, axis: .vertical)
                    .font(.callout)
                    .onChange(of: text) { _, new in store.set(original, new) }
                if store.overrides[original] != nil {
                    Button { text = original } label: { Image(systemName: "arrow.uturn.backward.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Put back the original")
                }
            }
            if store.overrides[original] != nil {
                Text(original).font(.caption2).foregroundStyle(.secondary).strikethrough()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill).opacity(0.5)))
        .onAppear { text = store.t(original) }
    }
}
