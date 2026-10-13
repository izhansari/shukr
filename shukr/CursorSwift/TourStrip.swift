//
//  TourStrip.swift
//  shukr
//
//  The tours' guidance out of the way (owner, 2026-10-08, decision tour-hint-style A: the bubbles "basically block the
//  whole page"): a step where you DO something is one slim strip — the chapter, the one thing to do now, how far — at
//  the bottom, or at the top whenever what the step asks you to touch is down there (owner: "it could still obstruct
//  … the done folding button" — it never sits on its target). What a step EXPLAINS shows once, as the card, with
//  "Got it"; then the strip. ⓘ on the strip brings the card back. Steps that are only reading stay the card. The app
//  tour, the Zikr Tour and the first session's tips all use it.
//

import SwiftUI

extension TourPage {
    /// The step being done now: the first unfinished one with to-dos (else the first unfinished one).
    var activeSection: TourSection? {
        sections.first { !$0.done && !$0.tasks.isEmpty } ?? sections.first { !$0.done }
    }

    /// The to-dos of the step being done now (`todo` is the first section with any, finished or not).
    var currentTodos: [String] { activeSection.map(\.tasks) ?? tasks }

    /// Something to do and no button to press: a strip's step.
    var isDoing: Bool { primary == nil && !currentTodos.isEmpty }

    /// Words to read beyond the to-do (the card shows them once): lists, a note, or a lead too long for a line. A short
    /// lead ("Your task is on the wheel.") rides in the strip instead (`shortLead`) — a card and a "Got it" for one line
    /// was a tap for nothing.
    var explains: Bool {
        if let s = activeSection { return !s.blocks.isEmpty || s.note != nil || (s.lead.map { $0.count > Self.shortLeadMax } ?? false) }
        return (subline.map { $0.count > Self.shortLeadMax } ?? false) || insight != nil
    }

    static let shortLeadMax = 64

    /// A lead short enough for the strip's top line.
    var shortLead: String? {
        let lead: String? = if let section = activeSection { section.lead } else { subline }
        guard let lead, lead.count <= Self.shortLeadMax else { return nil }
        return lead
    }

    /// The card's identity for "Got it": the step and the section.
    func guideKey(_ step: String) -> String { "\(step)|\(activeSection?.id ?? headline)" }

    /// The card with "Got it" as its button (the explanation, read once before the strip).
    var withGotIt: TourPage {
        var p = self
        p.primary = TourCopy.gotIt
        return p
    }
}

/// Which explanations have been read ("Got it"), for this run of the app.
@MainActor @Observable final class TourGuideState {
    static let shared = TourGuideState()
    private(set) var read: Set<String> = []
    func gotIt(_ key: String) { read.insert(key) }
    func again(_ key: String) { read.remove(key) }
}

/// What the guide shows for a page: the card, the card with "Got it", or the strip.
enum TourGuideMode: Equatable {
    case card, cardThenStrip, strip

    @MainActor static func of(_ page: TourPage, key: String) -> TourGuideMode {
        guard page.isDoing else { return .card }
        if page.explains && !TourGuideState.shared.read.contains(key) { return .cardThenStrip }
        return .strip
    }
}

/// The slim strip: the chapter in small caps, the one thing to do now (it ticks, then the next slides up), and how far
/// (dots, or "2 of 3" while counting). Only ⓘ takes a touch — a tap anywhere else goes through to the page.
struct TourCoachStrip: View {
    let chapter: String?
    /// The step's own short line ("Your task is on the wheel."), over the to-do instead of the chapter.
    var lead: String? = nil
    let todos: [String]
    let ticked: Set<Int>
    var locked: Set<Int> = []
    var progress: (Int, Int)? = nil
    var onDetails: (() -> Void)? = nil
    /// ‹ to the step before (the card's Back).
    var onBack: (() -> Void)? = nil
    /// A way past the step that the phone can't do (the qibla's "no compass"), as quiet words.
    var extra: (label: String, action: () -> Void)? = nil
    /// The extra as the strip's button (bordered, trailing) — a step whose only move is it (the Zikr Tour's end).
    var extraProminent = false
    /// false inside `TourTopPanel`, which draws the one background for the card and the strip it becomes.
    var chrome = true
    /// The tour's way out, as a ✕ at the end (the top panel; it asks first).
    var onSkip: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    private var current: Int {
        todos.indices.first { !ticked.contains($0) && !locked.contains($0) } ?? max(todos.count - 1, 0)
    }
    private var currentDone: Bool { ticked.contains(current) }
    /// A to-do just done: the strip's edge pulses green, then settles (owner: as the zikr practice box shows a
    /// satisfied action).
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.trailing, -6)
            }
            ZStack {
                Circle()
                    .strokeBorder(TourInk.green.opacity(currentDone ? 0 : 0.6), lineWidth: 1.5)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(TourInk.green)
                    .opacity(currentDone ? 1 : 0)
                    .scaleEffect(currentDone ? 1 : 0.5)
            }
            .frame(width: 22, height: 22)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentDone)

            VStack(alignment: .leading, spacing: 1) {
                if let lead {
                    Text(lead)
                        .font(.system(.caption, design: .rounded, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let chapter {
                    Text(chapter)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                Text(todos.indices.contains(current) ? todos[current] : "")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(currentDone ? 0.5 : 0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(current)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                if let extra, !extraProminent {
                    Button(extra.label, action: extra.action)
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(TourInk.green)
                        .padding(.top, 2)
                }
            }
            .clipped()
            .animation(.smooth(duration: 0.35), value: current)

            Spacer(minLength: 6)

            if let extra, extraProminent {
                Button(action: extra.action) {
                    Text(extra.label)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(TourInk.green)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(TourInk.green.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(TourInk.green, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            } else if let progress {
                Text("\(progress.0) of \(progress.1)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .contentTransition(.numericText())
            } else if todos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(todos.indices, id: \.self) { i in
                        Circle()
                            .fill(ticked.contains(i) ? TourInk.green : Color.primary.opacity(i == current ? 0.45 : 0.15))
                            .frame(width: 6, height: 6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: ticked)
            }
            if let onDetails {
                Button(action: onDetails) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What this step is about")
            }
            if let onSkip { TourSkipX(action: onSkip) }
        }
        // Room round the words (owner: two-line strips "cant breathe").
        .padding(.leading, 16)
        .padding(.trailing, onDetails == nil && onSkip == nil ? 18 : 8)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .modifier(StripChrome(on: chrome, look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme,
                              backdrop: theme.backdrop))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TourInk.green.opacity(pulse ? 1 : 0), lineWidth: pulse ? 3 : 1.5)
                .shadow(color: TourInk.green.opacity(pulse ? 0.55 : 0), radius: pulse ? 10 : 0)
                .allowsHitTesting(false)
        }
        .onChange(of: ticked) { old, new in
            guard new.count > old.count else { return }
            withAnimation(.easeOut(duration: 0.15)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(.easeOut(duration: 0.6)) { pulse = false }
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(onDetails != nil || onBack != nil || extra != nil || onSkip != nil)
        .accessibilityElement(children: .combine)
    }
}

/// The tour's ✕ (skip): a small grey circle, in the strip and the top panel.
struct TourSkipX: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TourCopy.Skip.button)
    }
}

/// The strip's own background, unless a panel around it draws one.
private struct StripChrome: ViewModifier {
    let on: Bool
    let look: TourBubbleLook
    let scheme: ColorScheme
    let backdrop: Color
    func body(content: Content) -> some View {
        if on {
            content.tourBubble(RoundedRectangle(cornerRadius: 20, style: .continuous), look: look, scheme: scheme, backdrop: backdrop)
        } else {
            content
        }
    }
}

/// Where the strip goes: the bottom (above the tab bar when there is one), or the top when the step's target sits in
/// the lower part of the screen, or the step keeps the page's lower part (the list, `keepBottom`).
enum TourStripPlace {
    static func top(target: CGRect?, height: CGFloat, keepBottom: Bool = false) -> Bool {
        if keepBottom { return true }
        guard let target else { return false }
        return target.maxY > height * 0.58
    }
}

extension View {
    /// The strip pinned to an edge of `size`: `top` under the top bar, else at the bottom above `bottomInset`.
    func tourStripPlaced(top: Bool, size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        frame(width: min(size.width - 28, 460))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: top ? .top : .bottom)
            .padding(.top, top ? topInset : 0)
            .padding(.bottom, top ? 0 : bottomInset)
            .animation(.smooth(duration: 0.4), value: top)
    }
}

// MARK: - The panel over the time editor

/// The tour's panel while the time editor's sheet is up (owner: "the strip to stay at the top of the page instead of on
/// the sheet's top … so it's consistent"): a sheet covers the tour's layer, so this one is in its own window above it,
/// in the panel's place — the chapter's line, then the editor's two to-dos, the first ticking as soon as the time is in
/// the yellow. It takes no touches.
@MainActor enum TourEditorPanelWindow {
    private static var window: UIWindow?

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .normal + 1
        w.isUserInteractionEnabled = false
        w.overrideUserInterfaceStyle = scene.keyWindow?.traitCollection.userInterfaceStyle ?? .unspecified
        let host = UIHostingController(rootView: TourEditorPanelRoot())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}

private struct TourEditorPanelRoot: View {
    var body: some View {
        GeometryReader { geo in
            TourEditorPanel()
                .frame(width: min(geo.size.width - 28, 460))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, TourTopPanel.topInset)
        }
        .ignoresSafeArea()
        .circleThemeRoot()
    }
}

/// The panel's look and line, the editor's to-dos under them.
struct TourEditorPanel: View {
    private var runtime: TourRuntime { .shared }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue
    @State private var pulse = false
    @State private var shown = false

    private var inYellow: Bool { runtime.editorInYellow }
    private var todos: [String] { TourCopy.List.editorTodos.map(TourCopyStore.shared.t) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 22, height: 30).padding(.leading, -6)   // the ‹'s place, as in the panel
                // The panel's chapter line, as TourTopPanel draws it.
                (Text("2  ").foregroundStyle(Color.primary.opacity(0.4)) + Text(TourCopy.List.title).foregroundStyle(Color.primary))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(todos.indices, id: \.self) { i in
                        Circle()
                            .fill(i == 0 && inYellow ? TourInk.green : Color.primary.opacity(i == (inYellow ? 1 : 0) ? 0.45 : 0.15))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.trailing, 10)
            }
            .frame(height: 34)
            // The first to-do, as the panel draws one (its line over it); once in the yellow it's ✓ and held, its line
            // the score it'll keep (owner: "its own moment"), and Save comes in under it.
            row(done: inYellow,
                lead: inYellow ? TourCopy.List.editorInYellow(runtime.editorScore)
                               : TourCopyStore.shared.t(TourCopy.List.editorLine),
                todo: todos[0])
            if inYellow {
                row(done: false, lead: nil, todo: todos[1])
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: inYellow)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .tourBubble(RoundedRectangle(cornerRadius: 20, style: .continuous),
                    look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TourInk.green.opacity(pulse ? 1 : 0), lineWidth: pulse ? 3 : 1.5)
                .shadow(color: TourInk.green.opacity(pulse ? 0.55 : 0), radius: pulse ? 10 : 0)
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.25)) { shown = true } }
        .onChange(of: inYellow) { _, now in
            guard now else { return }
            withAnimation(.easeOut(duration: 0.15)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(.easeOut(duration: 0.6)) { pulse = false }
            }
        }
    }

    /// One to-do: its ring (a ✓ once done), its line over it in the larger type, the to-do small under it.
    private func row(done: Bool, lead: String?, todo: String) -> some View {
        HStack(alignment: .todoLine, spacing: 12) {
            ZStack {
                Circle().strokeBorder(TourInk.green.opacity(done ? 0 : 0.6), lineWidth: 1.5)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(TourInk.green)
                    .opacity(done ? 1 : 0)
                    .scaleEffect(done ? 1 : 0.5)
            }
            .frame(width: 16, height: 16)
            .padding(.leading, 3)
            .alignmentGuide(.todoLine) { $0[VerticalAlignment.center] }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: done)
            VStack(alignment: .leading, spacing: 2) {
                if let lead {
                    Text(lead)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                        .id(done)
                        .transition(.opacity)
                }
                Text(todo)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(done ? AnyShapeStyle(TourInk.green) : AnyShapeStyle(Color.primary.opacity(0.55)))
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.todoLine) { $0[VerticalAlignment.center] }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
    }
}

// MARK: - The panel over a cover (the map step)

/// The tour's panel while the map is up (the new flow's map step): the map is a full-screen cover over the tour's layer,
/// so the panel is in its own window above it — the same panel, its → closing the map for them (owner: the panel hides
/// the map's own way back). Touches outside the panel go through to the map.
@MainActor enum TourCoverPanelWindow {
    private static var window: UIWindow?

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PassThroughWindow(windowScene: scene)
        w.windowLevel = .normal + 1
        w.overrideUserInterfaceStyle = scene.keyWindow?.traitCollection.userInterfaceStyle ?? .unspecified
        let host = UIHostingController(rootView: TourCoverPanelRoot())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }

    /// Where the panel is (its root reports it): the window takes touches there only.
    static var panelFrame: CGRect = .zero

    /// Takes a touch only on the panel; the rest falls to the map under it (SwiftUI draws no subviews to test against).
    private final class PassThroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard TourCoverPanelWindow.panelFrame.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

private struct TourCoverPanelRoot: View {
    private var runtime: TourRuntime { .shared }
    var body: some View {
        GeometryReader { geo in
            if runtime.active, let step = runtime.step {
                let page = runtime.page
                TourTopPanel(page: page, mode: TourGuideMode.of(page, key: page.guideKey(step.rawValue)),
                             guideKey: page.guideKey(step.rawValue), ticked: runtime.ticked, nudges: runtime.nudges,
                             showsBack: false, qiblaSkip: false, openSection: nil, lit: [], step: step, place: nil,
                             onPrimary: { runtime.event(.next) }, onSecondary: {}, onBack: {}, onToggle: { _ in },
                             onSkipQibla: {}, onSkip: { runtime.skip() })
                    .frame(width: min(geo.size.width - 28, 460))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourCoverPanelWindow.panelFrame = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, TourTopPanel.topInset)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .circleThemeRoot()
    }
}
