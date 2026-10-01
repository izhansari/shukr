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

/// The toolbar badge: a checklist symbol, always there (owner, 426B6DE8: "keep it in top right anyways so i
/// can click and see a page that says 'no decisions needed'"), with the count of decisions waiting when any.
struct DecisionsBadgeButton: View {
    let count: Int
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Image(systemName: "checklist")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 7, y: -5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(count) decision\(count == 1 ? "" : "s") waiting" : "Decisions: none needed")
    }
}

/// Open decisions first, then the decided ones (they never vanish).
struct DecisionsView: View {
    @State private var feedback = FeedbackStore.shared
    /// Decided is one folded row every time the page opens (owner, wn-decided-fold: "by default, just make it
    /// collapse when I come onto that page"); a tap shows them all. Never remembered open.
    @State private var decidedOpen = false

    var body: some View {
        let _ = feedback.revision   // re-read when he answers
        let all = WhatsNew.decisions
        let open = WhatsNew.openDecisions()
        let openIDs = Set(open.map(\.id))
        let decided = all.filter { !openIDs.contains($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if open.isEmpty {
                    // Nothing to decide: say so plainly (decided ones still listed below).
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 34, weight: .light)).foregroundStyle(Color.sage)
                        Text("No decisions needed").font(.headline)
                        Text("When the team has a question for you, it shows up here.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
                if !open.isEmpty {
                    SectionTitle(text: "Waiting for you", count: open.count).padding(.leading, 4)
                    ForEach(open) { d in
                        DecisionCard(decision: d)
                            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.96).combined(with: .opacity)))
                    }
                }
                if !decided.isEmpty {
                    DecidedFoldRow(count: decided.count, isOpen: decidedOpen) {
                        withAnimation(.snappy) { decidedOpen.toggle() }
                    }
                    .padding(.top, open.isEmpty ? 0 : 8)
                    if decidedOpen {
                        ForEach(decided) { d in
                            DecisionCard(decision: d).transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
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
            if ProcessInfo.processInfo.arguments.contains("-demoDecidedOpen") {   // the Decided fold, open
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy) { decidedOpen = true }
            }
            // `-demoDecisionClear <id>`: un-picks it 2 s in (back to Waiting).
            if let id = UserDefaults.standard.string(forKey: "demoDecisionClear"), let d = WhatsNew.decision(id) {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.snappy) {
                    _ = FeedbackStore.shared.saveDecision(d, option: nil, text: "", existing: WhatsNew.answer(to: d)?.item)
                }
                return
            }
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

/// "Decided · N" as one row (like Next build); the chevron turns when open.
private struct DecidedFoldRow: View {
    let count: Int
    let isOpen: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle").font(.body).foregroundStyle(Color.sage)
                (Text("Decided").font(.body.weight(.semibold)).foregroundStyle(.primary)
                 + Text(" · \(count)").font(.footnote).foregroundStyle(.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(isOpen ? "Hide" : "Show all").font(.footnote).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Decided, \(count)")
        .accessibilityHint(isOpen ? "Hides them" : "Shows them all")
    }
}

/// One question: the options side by side (their pictures, Bradley's pick marked). Open: tap one to choose it.
/// Decided: his pick highlighted, his note, and Edit (choose again, tap the pick again to un-pick it — back to
/// Waiting — or change the note). Withdrawn by the asker: greyed, "withdrawn", nothing to pick. ≤ ~40 % of the screen.
private struct DecisionCard: View {
    let decision: WhatsNewDecision
    @State private var editing = false
    @State private var note = ""
    @State private var pick: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        let answer = WhatsNew.answer(to: decision)
        let withdrawn = decision.withdrawnAt != nil
        let chosen = editing ? pick : answer?.option
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(meta(answer)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if answer != nil && !editing && !withdrawn {
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
            if withdrawn {
                Text(decision.withdrawnWhy.map { "Withdrawn: \($0)" } ?? "Withdrawn: no longer needed")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            } else if let why = decision.why, answer == nil || editing {
                Text("Bradley: \(why)").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            // Two per row: 3–4 options wrap instead of squeezing into narrow columns (never a horizontal scroll).
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top),
                                GridItem(.flexible(), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(decision.options) { o in
                    OptionTile(option: o, recommended: o.id == decision.recommend,
                               chosen: chosen == o.id, dimmed: withdrawn || (chosen != nil && chosen != o.id)) {
                        choose(o, answer: answer)
                    }
                    .allowsHitTesting(!withdrawn)
                }
            }
            if editing {
                // Undo (ask decision-undo: "i couldn't edit it to deselect"): tap the pick again to clear it.
                Text(pick == nil ? "No answer: Save puts it back in Waiting." : "Tap your pick again to clear it.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                HStack {
                    Button("Cancel") { withAnimation(.snappy) { editing = false } }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(pick == nil ? "Clear answer" : "Save") { save(answer: answer) }
                        .font(.body.weight(.semibold)).foregroundStyle(Color.sage)
                        .disabled(pick == answer?.option && note == (answer?.words ?? ""))
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
        if let withdrawn = decision.withdrawnAt {
            parts.append("withdrawn")
            parts.append(WhatsNew.whenLabel(withdrawn))
        } else if let answer {
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
            pick = pick == o.id ? nil : o.id   // the same one again un-picks it
            return
        }
        guard answer == nil else { return }
        withAnimation(.snappy) {
            // Picking again after an un-pick edits that same note while the team hasn't picked it up.
            _ = FeedbackStore.shared.saveDecision(decision, option: o.id, text: "", existing: WhatsNew.clearedItem(for: decision))
        }
    }

    private func save(answer: DecisionAnswer?) {
        triggerSomeVibration(type: .success)
        withAnimation(.snappy) {
            // No pick = un-picked: it goes back to Waiting.
            _ = FeedbackStore.shared.saveDecision(decision, option: pick, text: pick == nil ? "" : note, existing: answer?.item)
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
