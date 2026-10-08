//
//  SessionPage.swift
//  shukr
//
//  A saved session's own page (owner, ask session-page): a tap on a History row opens it — the
//  pause screen's look, for a session that's done: when it was, the zikr's card (full text,
//  notes, memo / photo), the bento (count, time, pace against your usual), Open zikr. Long-press a
//  row for its options; hold the pace on the row (or the rate tile here) to feel it.
//

import SwiftUI
import SwiftData

struct SessionPage: View {
    let session: SessionDataModel
    /// "Open zikr"; nil when there's no zikr (or it's already open behind).
    var onOpenZikr: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
    private var mantra: MantraModel? { session.mantra }
    private var name: String {
        if let m = mantra?.name { return m }
        return session.displayTitle
    }
    private var kind: String {
        switch session.sessionMode {
        case 1: return "\(session.targetMin) min session"
        case 2: return "\(session.targetCount) count session"
        default: return "freestyle session"
        }
    }
    /// "Wed, Sep 30 · 5:16 PM".
    private var when: String {
        session.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · "
            + session.startTime.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    zikrCard
                    ZikrBento(count: session.totalCount, seconds: session.secondsPassed,
                              secondsPerCount: session.avgTimePerClick,
                              perTasbeeh: session.tasbeehRate,
                              usualSecondsPerCount: mantra?.secondsPerCount(excluding: session))
                    if let task = session.task {
                        infoRow("checklist", "Counted toward \u{201C}\(task.title)\u{201D}")
                    }
                    if session.endedAsleep {
                        infoRow("moon.fill", "Sleep mode saved it, ending at your last tap")
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color("pauseColor").ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let onOpenZikr {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: onOpenZikr)
                    } label: {
                        Label("Open zikr", systemImage: "text.quote")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.sage)
                            .frame(width: 210, height: 52)
                            .background(Capsule().fill(Color.sage.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .fontDesign(.rounded)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.caption2.weight(.semibold))
            Text("\(when) · \(kind)")
        }
        .font(.subheadline.weight(.light))
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var zikrCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(name)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let mantra, mantra.audioData != nil || mantra.imageData != nil {
                    ZikrMediaStrip(mantra: mantra, compact: true)
                }
            }
            if let text = mantra?.fullText, !text.isEmpty {
                ZikrFullText(text: text)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            if let notes = mantra?.notes, !notes.isEmpty {
                Label(notes, systemImage: "doc.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if mantra == nil {
                Text("No zikr picked for this session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape.fill(.ultraThinMaterial))
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.sage).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
    }
}
