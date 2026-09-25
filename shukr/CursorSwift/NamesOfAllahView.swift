//
//  NamesOfAllahView.swift
//  shukr
//
//  Hamburger → 99 Names (2026-09-25): a little side app for getting to know Allah through His
//  names — a searchable list, a detail page per name, and flashcards. Which names the user
//  knows is saved (`namesKnown`, standard defaults, comma-separated ids) and shown as a thin
//  ring at the top. Data: NamesOfAllahData.swift. Next: the personalised AI dua per name
//  (CLAUDE.md, "99 Names").
//

import SwiftUI

/// The set of names marked "knew it" in flashcards (or on a name's page).
struct KnownNames {
    static let key = "namesKnown"
    static func decode(_ raw: String) -> Set<Int> { Set(raw.split(separator: ",").compactMap { Int($0) }) }
    static func encode(_ ids: Set<Int>) -> String { ids.sorted().map(String.init).joined(separator: ",") }
}

struct NamesOfAllahView: View {
    @AppStorage(KnownNames.key) private var knownRaw = ""
    @State private var search = ""
    @State private var selected: AllahName?
    @State private var showFlashcards = false

    private var known: Set<Int> { KnownNames.decode(knownRaw) }

    private var shown: [AllahName] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return NamesOfAllah.all }
        return NamesOfAllah.all.filter {
            $0.transliteration.localizedCaseInsensitiveContains(q) || $0.meaning.localizedCaseInsensitiveContains(q)
                || $0.alsoMeans.localizedCaseInsensitiveContains(q) || $0.arabic.contains(q) || "\($0.id)" == q
        }
    }

    var body: some View {
        // Our own list, not a stock inset List: a compact header, then every name on one soft
        // rounded card with thin rows (owner: "tighter", "beautified", brand look).
        ScrollView {
            VStack(spacing: 18) {
                header
                LazyVStack(spacing: 0) {
                    let names = shown
                    ForEach(Array(names.enumerated()), id: \.element.id) { index, name in
                        Button { selected = name } label: {
                            NameRow(name: name, known: known.contains(name.id))
                        }
                        .buttonStyle(.plain)
                        if index < names.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .searchable(text: $search, prompt: "Search names or meanings")
        .fontDesign(.rounded)
        .navigationTitle("99 Names")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Flashcards: a soft green tint, up here out of the way (was a stark green pill).
                Button {
                    triggerSomeVibration(type: .light)
                    showFlashcards = true
                } label: {
                    Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { name in
            NameDetailSheet(start: name)
        }
        .fullScreenCover(isPresented: $showFlashcards) {
            NameFlashcardsView()
        }
        #if DEBUG
        .task {
            // With -demoNames: opens straight into flashcards (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-demoFlashcards") { showFlashcards = true }
        }
        #endif
    }

    private var header: some View {
        let learned = known.filter { $0 > 0 }.count
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color(.secondarySystemFill), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(learned) / 99)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: learned)
                Text("اللَّهُ")
                    .font(.custom("KFGQPCUthmanTahaNaskh", size: 26))
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(learned) of 99 known")
                    .font(.subheadline.weight(.medium))
                Text("the most beautiful names belong to Allah, so call upon Him by them")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                Text("Al-A'raf 7:180")
                    .font(.caption2)
                    .foregroundStyle(Color.green.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }
}

private struct NameRow: View {
    let name: AllahName
    let known: Bool
    var body: some View {
        HStack(spacing: 12) {
            // The number in a small ring, like the app's circles; green once known.
            ZStack {
                Circle().stroke(known ? Color.green.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: 1)
                Text(name.id == 0 ? "•" : "\(name.id)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(known ? Color.green : .secondary)
                    .monospacedDigit()
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(name.transliteration)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                Text(name.meaning)
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(name.arabic)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 21))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - One name

struct NameDetailSheet: View {
    let start: AllahName
    @State private var index = 0
    @AppStorage(KnownNames.key) private var knownRaw = ""

    private var name: AllahName { NamesOfAllah.all[index] }
    private var isKnown: Bool { KnownNames.decode(knownRaw).contains(name.id) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            Group {
                Text(name.arabic)
                    .font(.custom("KFGQPCUthmanTahaNaskh", size: 56))
                VStack(spacing: 4) {
                    Text(name.transliteration)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                    Text(name.meaning)
                        .font(.headline.weight(.regular))
                        .foregroundStyle(.green)
                    Text(name.alsoMeans)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(name.explanation)
                    .font(.body.weight(.light))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
            }
            .id(index)
            .transition(.blurReplace)

            Spacer(minLength: 10)

            Button {
                triggerSomeVibration(type: .light)
                var ids = KnownNames.decode(knownRaw)
                if isKnown { ids.remove(name.id) } else { ids.insert(name.id) }
                knownRaw = KnownNames.encode(ids)
            } label: {
                Label(isKnown ? "Known" : "Mark as known", systemImage: isKnown ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isKnown ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            HStack {
                arrow("chevron.left", enabled: index > 0) { index -= 1 }
                Spacer()
                Text(name.id == 0 ? "Allah" : "\(name.id) of 99")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                arrow("chevron.right", enabled: index < NamesOfAllah.all.count - 1) { index += 1 }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .fontDesign(.rounded)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { index = NamesOfAllah.all.firstIndex(of: start) ?? 0 }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }
}

// MARK: - Flashcards

struct NameFlashcardsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(KnownNames.key) private var knownRaw = ""
    @AppStorage("namesFlashcardsMeaningFirst") private var meaningFirst = false

    private enum Deck: String, CaseIterable { case learning = "Still learning", all = "All names" }
    @State private var deck: Deck = .learning
    @State private var cards: [AllahName] = []
    @State private var position = 0
    @State private var flipped = false
    @State private var drag: CGSize = .zero
    /// Where the answered card flies off to (its removal transition), ±.
    @State private var exitX: CGFloat = 600
    @State private var knewThisRound = 0
    @State private var started = false
    /// The name on the start page's top card.
    @State private var sample: AllahName?
    /// Every answer this round, newest last, so Back can undo it: the name, whether it was
    /// known before, and the answer given.
    @State private var answers: [(id: Int, wasKnown: Bool, knew: Bool)] = []
    /// Set for the step that goes back a card: the returning card slides in from the side it
    /// left, and the current one sinks away instead of flying off.
    @State private var goingBack = false

    private var known: Set<Int> { KnownNames.decode(knownRaw) }

    var body: some View {
        VStack(spacing: 18) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                Spacer()
                if started && position < cards.count {
                    Text("\(position + 1) of \(cards.count)")
                        .font(.subheadline.weight(.light))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Back: undo the last answer and return to that card (also from the end screen).
                Button { goBack() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.medium))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                .opacity(started && !answers.isEmpty ? 1 : 0)
                .disabled(!started || answers.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: answers.isEmpty)
                .accessibilityLabel("Previous card")
            }
            .padding(.horizontal, 20)

            if !started {
                setup
            } else if position < cards.count {
                progressBar
                card(cards[position])
                    .padding(.horizontal, 24)
                answerButtons
            } else {
                finished
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .fontDesign(.rounded)
    }

    // MARK: setup

    /// The start page (redesigned 2026-09-25, owner: "not a fan of the first page"): a fanned
    /// preview of the deck whose top card is a real name (and follows "front shows"), then the
    /// deck and front as two small choices, and Begin with the card count.
    private var setup: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            deckPreview
                .frame(height: 290)
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    choiceLabel("deck")
                    HStack(spacing: 10) {
                        deckTile(.learning, detail: learningPool.isEmpty ? "all known" : "\(learningPool.count) names")
                        deckTile(.all, detail: "99 names")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    choiceLabel("front shows")
                    HStack(spacing: 10) {
                        frontTile("the name", icon: "character.book.closed", selected: !meaningFirst) { meaningFirst = false }
                        frontTile("the meaning", icon: "text.alignleft", selected: meaningFirst) { meaningFirst = true }
                    }
                }
            }
            .padding(.horizontal, 24)

            Button {
                begin()
            } label: {
                Text("Begin · \(pool(for: deck).count) cards")
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(Color.green)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 26)

            Text("swipe right if you knew it, left to keep learning")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
            Spacer(minLength: 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: deck)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: meaningFirst)
        .onAppear { if sample == nil { sample = pool(for: deck).randomElement() } }
        .onChange(of: deck) { _, newDeck in sample = pool(for: newDeck).randomElement() }
    }

    /// Names not yet known (the "still learning" deck), Allah (id 0) aside.
    private var learningPool: [AllahName] { NamesOfAllah.all.filter { $0.id > 0 && !known.contains($0.id) } }

    private func pool(for deck: Deck) -> [AllahName] {
        let all = NamesOfAllah.all.filter { $0.id > 0 }
        guard deck == .learning else { return all }
        return learningPool.isEmpty ? all : learningPool
    }

    /// Three cards fanned out, the top one a real name from the chosen deck, floating gently.
    private var deckPreview: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return ZStack {
            ForEach([(-9.0, -26.0, 10.0), (6.0, 22.0, 4.0)], id: \.0) { angle, x, y in
                cardShape
                    .fill(Color(.secondarySystemBackground))
                    .overlay(cardShape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .frame(width: 200, height: 260)
                    .rotationEffect(.degrees(angle))
                    .offset(x: x, y: y)
            }
            ZStack {
                if let sample {
                    VStack(spacing: 10) {
                        if meaningFirst {
                            Text(sample.meaning)
                                .font(.system(size: 22, weight: .light, design: .rounded))
                                .foregroundStyle(Color.green)
                                .multilineTextAlignment(.center)
                            Text(sample.alsoMeans)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } else {
                            Text(sample.arabic)
                                .font(.custom("KFGQPCUthmanTahaNaskh", size: 42))
                            Text(sample.transliteration)
                                .font(.system(size: 20, weight: .light, design: .rounded))
                        }
                    }
                    .padding(20)
                    .id("\(sample.id)-\(meaningFirst)")
                    .transition(.blurReplace)
                }
            }
            .frame(width: 200, height: 260)
            .background(cardShape.fill(Color(.secondarySystemBackground)))
            .overlay(cardShape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
            .overlay(alignment: .topTrailing) {
                Text("\(known.filter { $0 > 0 }.count)/99")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                    .padding(12)
            }
            .rotationEffect(.degrees(-1.5))
        }
        .phaseAnimator([false, true]) { view, up in
            view.offset(y: up ? -5 : 3)
        } animation: { _ in .easeInOut(duration: 2.6) }
    }

    private func choiceLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func deckTile(_ option: Deck, detail: String) -> some View {
        choiceTile(selected: deck == option) {
            deck = option
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.rawValue).font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func frontTile(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        choiceTile(selected: selected, action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(selected ? .medium : .regular))
        }
    }

    /// A small rounded choice: soft card, sage outline and tint when picked.
    private func choiceTile<Content: View>(selected: Bool, action: @escaping () -> Void,
                                           @ViewBuilder content: () -> Content) -> some View {
        Button {
            guard !selected else { return }
            triggerSomeVibration(type: .light)
            action()
        } label: {
            content()
                .foregroundStyle(selected ? Color.sage : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? Color.sage.opacity(0.1) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Color.sage.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: selected ? 1 : 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func begin() {
        triggerSomeVibration(type: .light)
        // The previewed card goes first, so what you saw is what you start on.
        var deckCards = pool(for: deck).shuffled()
        if let sample, let i = deckCards.firstIndex(of: sample) { deckCards.swapAt(0, i) }
        cards = deckCards
        position = 0
        flipped = false
        knewThisRound = 0
        answers = []
        goingBack = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { started = true }
    }

    // MARK: card

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.secondarySystemFill))
                Capsule().fill(Color.green)
                    .frame(width: geo.size.width * CGFloat(position) / CGFloat(max(cards.count, 1)))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: position)
    }

    private func card(_ name: AllahName) -> some View {
        let lean = drag.width / 300
        return ZStack {
            // Front
            face(front: true, name)
                .opacity(flipped ? 0 : 1)
            // Back (pre-flipped so it reads correctly once the card turns)
            face(front: false, name)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(lean > 0.1 ? Color.green.opacity(min(lean, 1)) : Color(.separator).opacity(0.5),
                                lineWidth: lean > 0.1 ? 2 : 0.5)
                )
        )
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width) / 22))
        .id(name.id)
        .transition(goingBack
            ? .asymmetric(insertion: .offset(x: exitX).combined(with: .opacity),
                          removal: .scale(scale: 0.92).combined(with: .opacity))
            : .asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                          removal: .offset(x: exitX).combined(with: .opacity)))
        .onTapGesture {
            triggerSomeVibration(type: .light)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { flipped.toggle() }
        }
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if value.translation.width > 110 { answer(knew: true) }
                    else if value.translation.width < -110 { answer(knew: false) }
                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero } }
                }
        )
    }

    @ViewBuilder
    private func face(front: Bool, _ name: AllahName) -> some View {
        let showName = front != meaningFirst
        VStack(spacing: 14) {
            if showName {
                Text(name.arabic)
                    .font(.custom("KFGQPCUthmanTahaNaskh", size: 54))
                Text(name.transliteration)
                    .font(.system(size: 26, weight: .light, design: .rounded))
            } else {
                Text(name.meaning)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                Text(name.alsoMeans)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !front {
                    Text(name.explanation)
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(.primary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            if front {
                Text("tap to flip")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
            } else if meaningFirst {
                // Back of a meaning-first card is the name; add the explanation under it too.
                Text(name.explanation)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .padding(28)
    }

    private var answerButtons: some View {
        HStack(spacing: 14) {
            Button { answer(knew: false) } label: {
                Text("Still learning")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.primary)
                    .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                    .contentShape(Capsule())
            }
            Button { answer(knew: true) } label: {
                Text("Knew it")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color.green)
                    .background(Capsule().fill(Color.green.opacity(0.16)))
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func answer(knew: Bool) {
        guard position < cards.count else { return }
        let name = cards[position]
        var ids = known
        answers.append((name.id, ids.contains(name.id), knew))
        if knew { ids.insert(name.id); knewThisRound += 1 } else { ids.remove(name.id) }
        knownRaw = KnownNames.encode(ids)
        if knew { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { triggerSomeVibration(type: .light) }
        // The answered card leaves through its removal transition (flying off to that side)
        // while the next one comes in — in one step. Snapping the offset back to zero first
        // re-showed the answered card for a frame before the next one rendered.
        exitX = knew ? 600 : -600
        goingBack = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            position += 1
            flipped = false
            drag = .zero
        }
    }

    /// Undo the last answer: its known state goes back to what it was, and its card returns
    /// (from the side it flew off to), unflipped.
    private func goBack() {
        guard let last = answers.popLast(), position > 0 else { return }
        triggerSomeVibration(type: .light)
        var ids = known
        if last.wasKnown { ids.insert(last.id) } else { ids.remove(last.id) }
        knownRaw = KnownNames.encode(ids)
        if last.knew { knewThisRound -= 1 }
        exitX = last.knew ? 600 : -600
        goingBack = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            position -= 1
            flipped = false
            drag = .zero
        }
    }

    // MARK: finished

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().stroke(Color(.secondarySystemFill), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(knewThisRound) / Double(max(cards.count, 1)))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(knewThisRound)/\(cards.count)")
                    .font(.system(size: 34, weight: .light, design: .rounded))
            }
            .frame(width: 150, height: 150)
            Text("\(known.filter { $0 > 0 }.count) of 99 known")
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary)
            Button {
                sample = pool(for: deck).randomElement()
                withAnimation { started = false }
            } label: {
                Text("Study again")
                    .fontWeight(.semibold)
                    .frame(width: 200)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color.green)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            Button("Done") { dismiss() }
                .tint(.secondary)
            Spacer()
        }
    }
}
