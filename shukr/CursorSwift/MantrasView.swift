//
//  MantrasView.swift
//  shukr
//
//  Manage the zikr / mantra list from the side menu.
//
//  Today a mantra is just a string (`MantraModel.text`). This screen is laid out so the
//  richer model (title + full Arabic text + notes) can slot in: the editor sheet is the
//  one place fields get added, and the list rows only read `text`.
//

import SwiftUI
import SwiftData

struct MantrasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.text) private var customMantras: [MantraModel]

    @State private var editing: MantraModel? = nil
    @State private var showingNewMantra = false

    var body: some View {
        List {
            Section {
                ForEach(MantraModel.builtIn, id: \.self) { text in
                    HStack {
                        Text(text)
                        Spacer()
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Built-in")
            } footer: {
                Text("These ship with the app and can't be edited yet.")
            }

            Section {
                if customMantras.isEmpty {
                    Text("No custom mantras yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customMantras) { mantra in
                        Button {
                            editing = mantra
                        } label: {
                            HStack {
                                Text(mantra.text)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("My Mantras")
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
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNewMantra) {
            MantraEditorView(mantra: nil)
                .presentationDetents([.medium])
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(customMantras[index])
        }
        // Tasks keep their mantra string; nothing else references MantraModel directly (yet).
    }
}


/// Create or edit one mantra. `mantra == nil` means create.
/// When the richer model lands, add its fields here (title / fullText / notes) and nowhere else.
struct MantraEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMantras: [MantraModel]
    @Query private var tasks: [TaskModel]

    let mantra: MantraModel?
    @State private var text: String

    init(mantra: MantraModel?) {
        self.mantra = mantra
        _text = State(initialValue: mantra?.text ?? "")
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another mantra (built-in or custom, other than the one being edited) already uses this text.
    private var isDuplicate: Bool {
        let lower = trimmed.lowercased()
        if MantraModel.builtIn.contains(where: { $0.lowercased() == lower }) { return true }
        return allMantras.contains { $0.text.lowercased() == lower && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var canSave: Bool {
        !trimmed.isEmpty && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Durood", text: $text)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Mantra")
                } footer: {
                    if isDuplicate {
                        Text("A mantra with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }
                // TODO(richer mantra): Section("Full text") { TextEditor(...) } for the Arabic
                // TODO(richer mantra): Section("Notes") { TextEditor(...) }
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
        if let mantra {
            let oldText = mantra.text
            mantra.text = trimmed
            // Tasks reference the mantra by string today; keep them in sync with a rename.
            // Sessions are left alone: their title is a historical snapshot.
            for task in tasks where task.mantra == oldText {
                task.mantra = trimmed
            }
        } else {
            context.insert(MantraModel(text: trimmed))
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
