//
//  LateMarkAsk.swift
//  shukr
//
//  The late-mark question (prayer-metrics rethink phase 6; board/scoring-rethink/plan-v3.md §3, §15). A prayer marked
//  after its window may have been prayed in its time — 81 of his 83 Fajr "Qazas" were tapped hours after sunrise — so
//  shukr asks once instead of guessing: "In its time" (a no-time mark: in its time, no clock claimed) or "Making it up
//  now". In the app the question comes before the mark (the list's row, the circle's hold); a mark from outside (widget,
//  notification, watch, Siri, the Live Activity) is asked about at the next open, one at a time (LateMarks). Swiping the
//  in-app question away marks nothing; an outside one swiped away stays made up and isn't asked again.
//
//  The look is a first pass on the design guide's vocabulary (one soft pill + one quiet line); Zoe owns the final look.
//

import SwiftUI
import SwiftData

@MainActor @Observable final class LateMarkAsk {
    static let shared = LateMarkAsk()

    struct Question: Identifiable {
        let id = UUID()
        let row: PrayerModel
        /// Asked before the mark (nil = the row is already marked, from outside).
        let mark: ((Bool) -> Void)?
    }

    var current: Question?
    @ObservationIgnored private var queue: [PrayerModel] = []
    @ObservationIgnored private var checking = false

    /// Would a mark of `row` now be after its window (and so need the question first)?
    static func wouldBeLate(_ row: PrayerModel, now: Date = Date()) -> Bool {
        !row.isCompleted && row.endTime <= now && !row.isJumuah && !TourRuntime.isPracticeAnywhere(row)
    }

    /// The list's row or the circle's hold, on a prayer whose window has ended: ask, then `mark(inTime)`.
    func askBeforeMarking(_ row: PrayerModel, mark: @escaping (Bool) -> Void) {
        current = Question(row: row, mark: mark)
    }

    /// After an open or an outside mark: queue every late mark nobody has answered for, and ask the first once the page
    /// is the user's.
    func checkOutsideMarks(in context: ModelContext) {
        LateMarks.startIfNeeded()
        guard let since = LateMarks.askFrom, !checking else { return }
        let rows = ((try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted && $0.markKind == nil && $0.timeAtComplete != nil }))) ?? [])
            .filter { LateMarks.needsAsk($0, since: since) }
            .sorted { ($0.timeAtComplete ?? .distantPast) < ($1.timeAtComplete ?? .distantPast) }
        let waiting = Set(queue.map(\.persistentModelID)).union(current.map { [$0.row.persistentModelID] } ?? [])
        queue += rows.filter { !waiting.contains($0.persistentModelID) }
        guard current == nil, !queue.isEmpty else { return }
        checking = true
        Task { @MainActor in
            defer { checking = false }
            // A moment after the page is up, and never over the first-run setup or the tour (askIfOverdue's pattern).
            try? await Task.sleep(for: .seconds(1.5))
            guard current == nil, !FirstRunSetup.isShowing, !TourRuntime.shared.active else { return }
            nextOutside()
        }
    }

    private func nextOutside() {
        while let row = queue.first {
            queue.removeFirst()
            if row.modelContext != nil, row.isCompleted, row.markKind == nil { current = Question(row: row, mark: nil); return }
        }
    }

    /// The answer. An outside mark is updated in place; an in-app one is marked through `mark`.
    func answer(_ q: Question, inTime: Bool, viewModel: PrayerViewModel) {
        current = nil
        if let mark = q.mark {
            mark(inTime)
        } else {
            viewModel.answerLateMark(q.row, inTime: inTime)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))   // the sheet down before the next one comes up
                nextOutside()
            }
        }
    }

    /// Swiped away: an in-app question marks nothing; an outside one stays made up and isn't asked again.
    func dismissed(_ q: Question, viewModel: PrayerViewModel) {
        guard current?.id == q.id else { return }
        current = nil
        if q.mark == nil {
            viewModel.answerLateMark(q.row, inTime: false)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                nextOutside()
            }
        }
    }
}

/// The question itself.
struct LateMarkSheet: View {
    let question: LateMarkAsk.Question
    let answer: (Bool) -> Void

    private var row: PrayerModel { question.row }
    private var outside: Bool { question.mark == nil }

    /// "Isha · Monday" / "Isha · Oct 12" — the prayer's own day.
    private var title: String {
        let day = row.dayStart
        let cal = Calendar.current
        let when = cal.isDateInToday(day) ? "today" : cal.isDateInYesterday(day) ? "yesterday"
            : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return "\(row.displayName) · \(when)"
    }

    /// The one quiet line: when its time ended, and (from outside) when it was marked.
    private var line: String {
        let ended = row.endTime.formatted(date: .omitted, time: .shortened)
        if outside, let at = row.timeAtComplete {
            // The day too when it was marked on a later day ("Marked Tue 9:38 PM"), else the clock alone reads backwards.
            let sameDay = Calendar.current.isDate(at, inSameDayAs: row.endTime)
            let when = sameDay ? "at " + at.formatted(date: .omitted, time: .shortened)
                : at.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return "Marked \(when), after its time ended at \(ended)."
        }
        return "Its time ended at \(ended)."
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 28, weight: .light, design: .rounded))
                Text(line).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            Text("Did you pray it in its time?")
                .font(.system(size: 17, weight: .regular, design: .rounded))
            VStack(spacing: 12) {
                Button { answer(true) } label: {
                    Text("In its time")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 240, height: 52)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                Button { answer(false) } label: {
                    Text(outside ? "Made it up later" : "Making it up now")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 240, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("In its time counts as prayed in its time, with no time recorded.")
                .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .fontDesign(.rounded)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}

/// On the Salah page: shows the question while there is one.
struct LateMarkAskHost: ViewModifier {
    @Environment(PrayerViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @State private var ask = LateMarkAsk.shared
    /// The question the sheet is showing: SwiftUI's nil write for a closing sheet can land after the next question was
    /// set, so a nil only counts as a swipe for the one on screen (Fable's review).
    @State private var presentedID: UUID?
    #if DEBUG
    /// DEBUG `-demoNoRecordCard`: the no-record card over the Salah page (its home is Journey's top — Zoe's), to try it.
    @State private var demoNoRecord: Date?
    @State private var demoPick: Date?
    #endif

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { ask.current }, set: {
            if $0 == nil, let q = ask.current, q.id == presentedID { ask.dismissed(q, viewModel: viewModel) }
        })) { q in
            LateMarkSheet(question: q) { inTime in ask.answer(q, inTime: inTime, viewModel: viewModel) }
                .onAppear { presentedID = q.id }
                .stageCover("lateMark")
        }
        #if DEBUG
        .overlay(alignment: .top) {
            if let day = demoNoRecord {
                NoRecordCard(day: day, onPick: { demoPick = day }, onNotNow: {
                    NoRecordDays.dismiss(day)
                    demoNoRecord = NoRecordDays.next(in: context)
                })
                .padding(.horizontal, 16).padding(.top, 60)
            }
        }
        .sheet(item: Binding(get: { demoPick.map(DemoDay.init) }, set: { demoPick = $0?.day })) { d in
            NoRecordPickSheet(day: d.day) { picked in
                NoRecordDays.fill(d.day, picked: picked, viewModel: viewModel)
                demoNoRecord = NoRecordDays.next(in: context)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoNoRecordCard") { demoNoRecord = NoRecordDays.next(in: context) }
        }
        #endif
    }
    #if DEBUG
    private struct DemoDay: Identifiable { let day: Date; var id: Date { day } }
    #endif
}

extension View {
    func lateMarkAsk() -> some View { modifier(LateMarkAskHost()) }
}
