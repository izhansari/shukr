//
//  MantrasView.swift
//  shukr
//
//  Manage the mantra list from the side menu. A mantra has a short `name` (what cards, the
//  picker and session titles show), the `fullText` (Arabic / transliteration) and free `notes`.
//  The four built-ins are ordinary rows here — seeded on migration / first launch — so they can
//  be edited like the rest. Tasks and sessions point at the row, so a rename shows everywhere;
//  deleting a row unlinks them (tasks fall back to their name snapshot, sessions keep `title`).
//

import SwiftUI
import SwiftData

struct MantrasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var mantras: [MantraModel]

    @State private var editing: MantraModel? = nil
    @State private var showingNewMantra = false

    var body: some View {
        List {
            if mantras.isEmpty {
                Text("No mantras yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mantras) { mantra in
                    Button {
                        editing = mantra
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mantra.name)
                                    .foregroundStyle(.primary)
                                if !mantra.fullText.isEmpty {
                                    Text(mantra.fullText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let pace = mantra.secondsPerCount {
                                    Text("\(mantra.totalCount.formatted()) counted · \(String(format: "%.1fs", pace)) each")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if !mantra.notes.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary) // rows, not links
                }
                .onDelete(perform: delete)
            }
        }
        .fontDesign(.rounded)
        .navigationTitle("Mantras")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewMantra = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.green.opacity(0.7))
                }
            }
        }
        .sheet(item: $editing) { mantra in
            MantraEditorView(mantra: mantra)
        }
        .sheet(isPresented: $showingNewMantra) {
            MantraEditorView(mantra: nil)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(mantras[index]) // relationships are .nullify: tasks/sessions survive, unlinked
        }
    }
}


/// Create or edit one mantra. `mantra == nil` means create.
struct MantraEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMantras: [MantraModel]

    let mantra: MantraModel?
    @State private var name: String
    @State private var fullText: String
    @State private var notes: String

    init(mantra: MantraModel?) {
        self.mantra = mantra
        _name = State(initialValue: mantra?.name ?? "")
        _fullText = State(initialValue: mantra?.fullText ?? "")
        _notes = State(initialValue: mantra?.notes ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another mantra (other than the one being edited) already uses this name.
    private var isDuplicate: Bool {
        let lower = trimmedName.lowercased()
        return allMantras.contains { $0.name.lowercased() == lower && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Durood", text: $name)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Name")
                } footer: {
                    if isDuplicate {
                        Text("A mantra with this name already exists.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Shown on task cards, in the picker and in history.")
                    }
                }

                Section {
                    TextEditor(text: $fullText)
                        .frame(minHeight: 80)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Full mantra")
                } footer: {
                    Text("The complete wording, Arabic or transliterated.")
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Why or when to read it, who recommended it, anything you want to remember.")
                }

                if let mantra {
                    Section {
                        LabeledContent("Tasks", value: "\(mantra.tasks.count)")
                        LabeledContent("Sessions", value: "\(mantra.sessions.count)")
                        if mantra.totalCount > 0 {
                            LabeledContent("Total count", value: mantra.totalCount.formatted())
                            LabeledContent("Total time", value: zikrDurationString(mantra.totalSeconds))
                        }
                        if let pace = mantra.secondsPerCount {
                            PaceRow(secondsPerCount: pace)
                        }
                    } header: {
                        Text("Stats")
                    } footer: {
                        if mantra.secondsPerCount != nil {
                            Text("Rate is time-weighted over every session of this mantra. Tap it to switch between per count and per tasbeeh (100).")
                        }
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle(mantra == nil ? "New Mantra" : "Edit Mantra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let fullTextTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mantra {
            mantra.name = trimmedName
            mantra.fullText = fullTextTrimmed
            mantra.notes = notesTrimmed
            // Tasks read the live name through the relationship; keep their snapshot in step too
            // so a later deletion still shows the right name. Sessions keep their historical title.
            for task in mantra.tasks { task.mantraName = trimmedName }
        } else {
            context.insert(MantraModel(name: trimmedName, fullText: fullTextTrimmed, notes: notesTrimmed))
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MantrasView()
    }
    .modelContainer(for: [MantraModel.self, TaskModel.self, SessionDataModel.self], inMemory: true)
}


/// "Average pace" row: tap flips between seconds per count and time per tasbeeh (100 counts),
/// with the same slide-and-fade the Rate box on the tasbeeh pause screen uses.
private struct PaceRow: View {
    let secondsPerCount: TimeInterval
    @State private var showingPerCount = true

    var body: some View {
        HStack {
            Text("Average rate")
            Spacer()
            ZStack(alignment: .trailing) {
                Text(String(format: "%.1fs per count", secondsPerCount))
                    .opacity(showingPerCount ? 1 : 0)
                    .offset(y: showingPerCount ? 0 : -14)
                Text("\(zikrDurationString(secondsPerCount * 100)) per tasbeeh")
                    .opacity(showingPerCount ? 0 : 1)
                    .offset(y: showingPerCount ? 14 : 0)
            }
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .clipped()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                triggerSomeVibration(type: .medium)
                showingPerCount.toggle()
            }
        }
    }
}
