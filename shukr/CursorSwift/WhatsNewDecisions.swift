//
//  WhatsNewDecisions.swift
//  shukr
//
//  What's new's Decisions page (ask wn-decisions — owner: "an SF symbol with a badge on it in the top right
//  corner of the page, showing the amount of decisions I have outstanding. And clicking that badge … pushes a
//  new page to where I can see the decisions"). The questions are the team's decision records (CLAUDE.md step
//  8, `board/decide.sh`); his pick is a `FeedbackItem.Kind.decision`, pulled like any answer.
//

import SwiftUI

/// The toolbar badge: a checklist symbol with the count of decisions waiting; nothing at 0.
struct DecisionsBadgeButton: View {
    let count: Int
    let open: () -> Void
    var body: some View {
        if count > 0 {
            Button(action: open) {
                Image(systemName: "checklist")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .overlay(alignment: .topTrailing) {
                        Text("\(count)")
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 7, y: -5)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(count) decision\(count == 1 ? "" : "s") waiting")
        }
    }
}

/// Open decisions first, then the decided ones (they never vanish).
struct DecisionsView: View {
    @State private var feedback = FeedbackStore.shared

    var body: some View {
        let _ = feedback.revision   // re-read when he answers
        let all = WhatsNew.decisions
        let open = WhatsNew.openDecisions()
        let openIDs = Set(open.map(\.id))
        let decided = all.filter { !openIDs.contains($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if all.isEmpty {
                    Text("No questions from the team yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                if !open.isEmpty {
                    SectionTitle(text: "Waiting for you", count: open.count).padding(.leading, 4)
                    ForEach(open) { d in
                        DecisionCard(decision: d)
                            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.96).combined(with: .opacity)))
                    }
                }
                if !decided.isEmpty {
                    SectionTitle(text: "Decided", count: decided.count).padding(.leading, 4).padding(.top, open.isEmpty ? 0 : 8)
                    ForEach(decided) { d in DecisionCard(decision: d) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("Decisions")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        // `-demoDecisionChoose "<id>:<option>"` (+ `-demoDecisionNote "…"`): picks it 2 s in (simulated taps
        // can't reach this sheet everywhere).
        .task {
            guard let spec = UserDefaults.standard.string(forKey: "demoDecisionChoose"),
                  let colon = spec.lastIndex(of: ":"),
                  let d = WhatsNew.decision(String(spec[..<colon])) else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) {
                _ = FeedbackStore.shared.saveDecision(d, option: String(spec[spec.index(after: colon)...]),
                                                      text: UserDefaults.standard.string(forKey: "demoDecisionNote") ?? "")
            }
        }
        #endif
    }
}

/// One question: the options side by side (their pictures, Bradley's pick marked). Open: tap one to choose it.
/// Decided: his pick highlighted, his note, and Edit (choose again / change the note). ≤ ~40 % of the screen.
private struct DecisionCard: View {
    let decision: WhatsNewDecision
    @State private var editing = false
    @State private var note = ""
    @State private var pick: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        let answer = WhatsNew.answer(to: decision)
        let chosen = editing ? pick : answer?.option
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(meta(answer)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if answer != nil && !editing {
                    Button("Edit") {
                        pick = answer?.option
                        note = answer?.words ?? ""
                        withAnimation(.snappy) { editing = true }
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.sage)
                    .frame(minHeight: 32)
                }
            }
            Text(decision.question)
                .font(.headline)
                .lineLimit(2)
            if let why = decision.why, answer == nil || editing {
                Text("Bradley: \(why)").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            // Two per row: 3–4 options wrap instead of squeezing into narrow columns (never a horizontal scroll).
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top),
                                GridItem(.flexible(), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(decision.options) { o in
                    OptionTile(option: o, recommended: o.id == decision.recommend,
                               chosen: chosen == o.id, dimmed: chosen != nil && chosen != o.id) {
                        choose(o, answer: answer)
                    }
                }
            }
            if editing {
                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                HStack {
                    Button("Cancel") { withAnimation(.snappy) { editing = false } }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { save(answer: answer) }
                        .font(.body.weight(.semibold)).foregroundStyle(Color.sage)
                        .disabled(pick == nil)
                }
                .frame(minHeight: 36)
            } else if let words = answer?.words, !words.isEmpty {
                Text("\u{201C}\(words)\u{201D}").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1))
    }

    private func meta(_ answer: DecisionAnswer?) -> String {
        var parts = [decision.area ?? "Decision"]
        if let answer {
            let where_ = answer.source == "phone" ? "here" : answer.source == "board" ? "on the board" : "in chat"
            parts.append("you chose \(answer.option) \(where_)")
            parts.append(WhatsNew.whenLabel(answer.at))
        } else {
            parts.append(WhatsNew.whenLabel(decision.createdDate))
        }
        return parts.joined(separator: " · ")
    }

    /// Open: a tap chooses at once (the card moves to Decided; a note can be added there with Edit).
    /// Editing: a tap only picks; Save keeps it.
    private func choose(_ o: WhatsNewDecision.Option, answer: DecisionAnswer?) {
        triggerSomeVibration(type: .success)
        if editing {
            pick = o.id
            return
        }
        guard answer == nil else { return }
        withAnimation(.snappy) {
            _ = FeedbackStore.shared.saveDecision(decision, option: o.id, text: "")
        }
    }

    private func save(answer: DecisionAnswer?) {
        guard let pick else { return }
        triggerSomeVibration(type: .success)
        withAnimation(.snappy) {
            _ = FeedbackStore.shared.saveDecision(decision, option: pick, text: note, existing: answer?.item)
            editing = false
        }
    }
}

/// One option: its picture (≤ 160 pt), its label, "Bradley's pick" when it's his recommendation.
private struct OptionTile: View {
    let option: WhatsNewDecision.Option
    let recommended: Bool
    let chosen: Bool
    let dimmed: Bool
    let tap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill).opacity(0.6))
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().padding(4)
                    } else if option.shot == nil {
                        Text(option.id).font(.title.weight(.light)).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(option.id).font(.subheadline.weight(.bold)).foregroundStyle(chosen ? Color.green : .secondary)
                    Text(option.label).font(.subheadline.weight(chosen ? .semibold : .regular)).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                if recommended {
                    Label("Bradley's pick", systemImage: "star.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Color.sage)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(chosen ? Color.green.opacity(0.12) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(chosen ? Color.green.opacity(0.7) : Color(.separator).opacity(0.6), lineWidth: chosen ? 2 : 1))
            .opacity(dimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Option \(option.id): \(option.label)\(recommended ? ", Bradley's pick" : "")\(chosen ? ", chosen" : "")")
        .task(id: option.shot) {
            guard let shot = option.shot else { return }
            image = await Task.detached(priority: .userInitiated) { WhatsNew.image(shot)?.preparingForDisplay() }.value
        }
    }
}
