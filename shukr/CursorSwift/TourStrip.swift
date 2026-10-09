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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    private var current: Int {
        todos.indices.first { !ticked.contains($0) && !locked.contains($0) } ?? max(todos.count - 1, 0)
    }
    private var currentDone: Bool { ticked.contains(current) }

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
        }
        .padding(.leading, 14)
        .padding(.trailing, onDetails == nil ? 16 : 6)
        .frame(minHeight: 56)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .tourBubble(RoundedRectangle(cornerRadius: 20, style: .continuous),
                    look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
        .contentShape(Rectangle())
        .allowsHitTesting(onDetails != nil || onBack != nil || extra != nil)
        .accessibilityElement(children: .combine)
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
