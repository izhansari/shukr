//
//  ZikrTabPages.swift
//  shukr
//
//  The Zikr tab reorganised (owner, 2026-10-01, decision zikr-reorg-next-build A: "make the mock the
//  real thing"): the Zikr page keeps today (the wheel); Azkar and History are labelled doors at the
//  top, each its own page; Your tasks is a page from "N of M tasks done". They replace the History |
//  Azkar pager (ZikrLibraryView) and the Tasks sheet.
//

import SwiftUI
import SwiftData

/// A door at the top of the Zikr page: just its symbol (owner, 2026-10-01: SF Symbols only), in the
/// look of the Salah page's ☰ — History left, Azkar right. The name is its VoiceOver label.
struct ZikrDoor: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .font(.system(size: 19))
                .fontWeight(.light)
                .foregroundColor(.gray.opacity(0.8))
                .padding()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Azkar, its own page: yours first, built-ins below, the sort button top right; ＋ makes a new zikr
/// as a card over the page (the bottom bar beside search on iOS 26, top right before).
struct AzkarPage: View {
    @State private var search = ""
    @State private var showingNewZikr = false
    private var trimmed: String { search.trimmingCharacters(in: .whitespaces) }

    private static var bottomBarPlus: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    private var plus: some View {
        Button { showingNewZikr = true } label: {
            Image(systemName: "plus").fontWeight(.semibold).foregroundStyle(Color.green)
        }
        .accessibilityLabel("New zikr")
    }

    var body: some View {
        MantrasView(embedded: true, externalSearch: trimmed)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Azkar")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, placement: .toolbar, prompt: "Search azkar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AzkarSortButton() }
                if !Self.bottomBarPlus {
                    ToolbarItem(placement: .topBarTrailing) { plus }
                }
                if #available(iOS 26.0, *) {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { plus }
                }
            }
            .newZikrCard(isPresented: $showingNewZikr)   // the card over the page, not a sheet
            // The Zikr Tour's Azkar step: its bubble here, Continue back (ZikrTour.swift).
            .overlay { ZikrTourInline(place: .azkar) }
            .onAppear { ZikrTour.shared.azkarOpened() }
            .onChange(of: ZikrTour.shared.popPage) { _, _ in if ZikrTour.shared.step == .done { dismissAzkar() } }
    }
    @Environment(\.dismiss) private var dismissAzkar
}

/// History, its own page: the all-time header, the bars and every session; Select → Delete.
struct ZikrHistoryPage: View {
    @State private var search = ""
    @State private var editing = false
    /// Just whether there's any session (Select greys out without).
    @Query private var anySession: [SessionDataModel]
    private var trimmed: String { search.trimmingCharacters(in: .whitespaces) }

    init() {
        var one = FetchDescriptor<SessionDataModel>()
        one.fetchLimit = 1
        _anySession = Query(one)
    }

    var body: some View {
        HistoryPageView(search: trimmed, editing: $editing)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, placement: .toolbar, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "Done" : "Select") { withAnimation { editing.toggle() } }
                        .fontWeight(editing ? .semibold : .regular)
                        .disabled(anySession.isEmpty || CountTips.shared.guardsDeletes)   // the tour's delete tip: its row only
                }
                if #available(iOS 26.0, *) {
                    if !editing { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                }
            }
            .onDisappear { PaceCoordinator.stopAll() }   // a pace playing on a row stops with the page
            // The session tour: delete its practice session here, then back to the Zikr page.
            // Over the all-time header, never the rows: the session to delete is the top one.
            .overlay(alignment: .top) {
                if CountTips.shared.tip == .delete {
                    CountTipCard(tip: .delete).padding(.top, 70)
                }
            }
            // Skip tips, top right (over Select, which waits during the delete tip anyway).
            .overlay(alignment: .topTrailing) {
                if CountTips.shared.tip == .delete {
                    CountTipsSkip().padding(.trailing, 16).padding(.top, 14)
                }
            }
            .onAppear { CountTips.shared.historyOpened(); ZikrTour.shared.historyOpened() }
            .onChange(of: CountTips.shared.popHistory) { _, _ in dismiss() }
            // The Zikr Tour's History step: its bubble here, Continue back (ZikrTour.swift).
            .overlay { ZikrTourInline(place: .history) }
            .onChange(of: ZikrTour.shared.popPage) { _, _ in if ZikrTour.shared.step == .azkar { dismiss() } }
    }
    @Environment(\.dismiss) private var dismiss
}
