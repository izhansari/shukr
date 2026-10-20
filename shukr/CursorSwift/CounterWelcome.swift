//
//  CounterWelcome.swift
//  shukr
//
//  The Zikr lock's practice page (ZikrLock.swift): the three ways to count, tried in boxes before the first zikr. It came
//  from the old Zikr Tour (ZikrTour.swift), removed 2026-10-20 (owner: "i only wanna keep the zikr lock hadith flow. the
//  other one is old").
//

import SwiftUI

/// The Zikr lock's practice page, before the first zikr (owner, 2026-10-09: "a nice welcome and just explains we gonna show them the
/// different ways to count and we'll do it together"; then "three different boxed areas in an hstack that has each ghost
/// finger graphic in it and they can satisfy the taps in those graphics before starting the actual counter … a green
/// border … a cross on its caption … each time they satisfy one flash that area's border"): the page's own colour over
/// the counter, three practice boxes, "Let's begin" once all three are done. It takes every touch, so nothing counts
/// under it; the boxes' moves are practice only.
struct CounterWelcome: View {
    /// "Skip this step" once this many are done (owner: "if there's only one satisfied, just put a secondary button");
    /// the main button lights up only with all three.
    var minimumDone = 1
    /// The button's words (the lock's practice leads on to their zikr: "continue to pick my zikr. or something like that").
    var buttonTitle = TourCopy.ZikrPractice.welcomeButton
    let onBegin: () -> Void
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done: Set<GestureHint.Kind> = []
    /// The box last touched: its ghost finger is the moving one (owner: "whichever one was last worked on … should be in
    /// focus"), else the first one still to do.
    @State private var focus: GestureHint.Kind?
    /// The rows come in one at a time (owner: "fade in each hstack one by one"): 1 the title, 2 the line, 3 the boxes,
    /// 4 the buttons.
    @State private var shown = 0
    private typealias C = TourCopy.ZikrPractice
    private var allDone: Bool { done.count == 3 }

    var body: some View {
        ZStack {
            theme.backdrop.opacity(0.96)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 0) {
                Text(C.welcomeKicker.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.4)
                    .foregroundStyle(Color.sage)
                    .rowIn(shown >= 1, reduceMotion)
                Text(C.welcomeBody)
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.top, 14)
                    .rowIn(shown >= 2, reduceMotion)
                // One ghost finger moving at a time — the first box still to do; the others hold their move still, faint
                // (owner: "they all show up at one time and it's like woah").
                let next = focus.flatMap { done.contains($0) ? nil : $0 }
                    ?? [GestureHint.Kind.tap, .drag, .stroke].first { !done.contains($0) }
                HStack(alignment: .top, spacing: 10) {
                    PracticeBox(kind: .tap, caption: C.practiceTap, active: next == .tap,
                                onTouch: { focus = .tap }) { done.insert(.tap) }
                    PracticeBox(kind: .drag, caption: C.practiceDrag, active: next == .drag,
                                onTouch: { focus = .drag }) { done.insert(.drag) }
                    PracticeBox(kind: .stroke, caption: C.practiceStroke, active: next == .stroke,
                                onTouch: { focus = .stroke }) { done.insert(.stroke) }
                }
                .padding(.top, 30)
                .rowIn(shown >= 3, reduceMotion)
                .allowsHitTesting(shown >= 3)
                VStack(spacing: 6) {
                    Button(action: onBegin) {
                        HStack(spacing: 6) {
                            Text(buttonTitle)
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.sage)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.sage.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .opacity(allDone ? 1 : 0.3)
                    .disabled(!allDone)
                    // Not all three yet, but some: allowed on, quietly (they know they've skipped some).
                    Button("Skip this step", action: onBegin)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(height: 32)
                        .opacity(!allDone && done.count >= minimumDone ? 1 : 0)
                        .allowsHitTesting(!allDone && done.count >= minimumDone)
                }
                .animation(.easeInOut(duration: 0.3), value: done.count)
                .padding(.top, 28)
                .rowIn(shown >= 4, reduceMotion)
            }
            .padding(.horizontal, 18)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .task {
            if reduceMotion { shown = 4; return }
            // At the pages' pace (page 3's parts): after the page before has gone, a part every 0.9 s, each 0.9 s in.
            try? await Task.sleep(for: .milliseconds(700))
            for row in 1...4 {
                withAnimation(.easeInOut(duration: 0.9)) { shown = row }
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }
}

private extension View {
    /// A row of the practice page coming in: faded and a touch lower until it's its turn.
    func rowIn(_ on: Bool, _ reduceMotion: Bool) -> some View {
        opacity(on ? 1 : 0).offset(y: on || reduceMotion ? 0 : 8)
    }
}

/// One way to count, to try: its ghost finger looping inside, three of the move to fill it. Each right move flashes the
/// border green; three, and the border stays green, the caption crossed out. A stroke's three are in one touch.
/// While a finger is down the box presses in, the ghost steps aside and an arrow shows the next move; a wrong move
/// flashes the border red and says why in a few words (owner: "it doesn't tell you if you're wrong … show me what to
/// do now that I'm holding the box down … minimal").
private struct PracticeBox: View {
    let kind: GestureHint.Kind
    let caption: String
    /// Its ghost finger moves (the box to try now); otherwise it's held still and faint.
    var active = true
    /// A finger came down on it (it takes the focus).
    var onTouch: () -> Void = {}
    let onDone: () -> Void
    @State private var count = 0
    @State private var flash: Color?
    @State private var why: String?
    @State private var pressed = false
    // A drag's way, read exactly as the counter reads it (tasbeehView: incrementThreshold 50): down 50 pt from the
    // highest point counts — at once, mid-drag — and back up 25 pt re-arms; a tap is a touch that doesn't move.
    @State private var highest: CGFloat = 0
    @State private var lowest: CGFloat = 0
    @State private var armed = true
    @State private var strokes = 0
    @State private var whyTask: Task<Void, Never>?
    /// The dot just filled pops (owner: "turn green with like a short pulse so it's clearer the count was registered").
    @State private var pop = false
    private static let needed = 3
    private static let step: CGFloat = 50   // the counter's incrementThreshold
    private var isDone: Bool { count >= Self.needed }

    var body: some View {
        let box = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 10) {
            ZStack {
                NeuPressed(shape: box, radius: 5, offset: 3)
                GestureHint(kind: kind, height: 150, still: !active)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .opacity(isDone ? 0.2 : (pressed ? 0 : (active ? 1 : 0.35)))
                    .animation(.easeInOut(duration: 0.4), value: active)
                // Held: the next move.
                if pressed, !isDone, kind == .stroke || (kind == .drag && strokes == 0) {
                    Image(systemName: armed ? "arrow.down" : "arrow.up")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.sage)
                        .id(armed)
                        .transition(.opacity)
                }
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.sage)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 170)
            .overlay(box.strokeBorder(border, lineWidth: flash != nil ? 3 : (isDone ? 2 : 1.5)))
            .shadow(color: (flash ?? .clear).opacity(0.55), radius: flash != nil ? 10 : 0)
            .scaleEffect(pressed && !isDone ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .animation(.easeOut(duration: 0.15), value: armed)
            .contentShape(box)
            .gesture(practice)
            .allowsHitTesting(!isDone)
            Text(caption)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(2, reservesSpace: true)   // two lines each, so the dots under them line up
                .strikethrough(isDone, color: Color.sage)
                .foregroundStyle(isDone ? Color.sage : Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                HStack(spacing: 5) {
                    ForEach(0..<Self.needed, id: \.self) { i in
                        Circle().fill(i < count ? Color.sage : Color.primary.opacity(0.15)).frame(width: 6, height: 6)
                            .scaleEffect(pop && i == count - 1 ? 1.9 : 1)
                    }
                }
                .opacity(why == nil ? 1 : 0)
                if let why {
                    Text(why)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 16)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: isDone)
        .animation(.easeOut(duration: 0.2), value: why)
    }

    /// Green flashing a right move, red a wrong one; green to stay once done; a quiet edge while held.
    private var border: Color {
        if let flash { return flash }
        if isDone { return .sage }
        return pressed ? Color.primary.opacity(0.3) : .clear
    }

    /// One gesture for every box: it sees the press, the way, and the lift, so a wrong move can be told apart.
    private var practice: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !pressed { pressed = true; strokes = 0; onTouch() }
                guard kind != .tap else { return }
                let y = v.translation.height
                highest = min(highest, y)
                lowest = max(lowest, y)
                if armed && y - highest > Self.step {
                    armed = false
                    lowest = y
                    strokes += 1
                    // The drag box: its one count per touch, as it happens (a second stroke is the next box's move).
                    if kind == .stroke || strokes == 1 { hit() }
                } else if !armed && lowest - y > Self.step / 2 {
                    armed = true
                    highest = y
                }
            }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                let moved = max(abs(dx), abs(dy)) > 10
                pressed = false
                highest = 0; lowest = 0; armed = true
                guard !isDone else { return }
                switch kind {
                case .tap:
                    if moved { wrong("Just tap") } else { hit() }
                case .drag:
                    // Counted already if it went far enough (mid-drag, like the counter).
                    if strokes > 0 { break }
                    if !moved { wrong("Drag down") }
                    else if dy < 0 { wrong("Down, not up") }
                    else { wrong("A bit further") }
                case .stroke:
                    if strokes == 0 { wrong(moved ? "Down, then up" : "Hold and drag") }
                    else { wrong("Keep your finger down"); withAnimation(.easeOut(duration: 0.2)) { count = 0 } }
                }
            }
    }

    private func hit() {
        guard !isDone else { return }
        withAnimation(.easeOut(duration: 0.15)) { count += 1; flash = .sage; why = nil }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pop = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
        }
        if isDone {
            triggerSomeVibration(type: .success)
            onDone()
        } else {
            triggerSomeVibration(type: .light)
        }
        clearFlash()
    }

    private func wrong(_ reason: String) {
        triggerSomeVibration(type: .warning)
        withAnimation(.easeOut(duration: 0.15)) { flash = .red; why = reason }
        clearFlash()
        whyTask?.cancel()
        whyTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { why = nil }
        }
    }

    private func clearFlash() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeIn(duration: 0.3)) { flash = nil }
        }
    }
}
