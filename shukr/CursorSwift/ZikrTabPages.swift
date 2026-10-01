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

/// A labelled door at the top of the Zikr page ("Azkar" left, "History" right), in the look the
/// Tasks button had.
struct ZikrDoor: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                Text(title).font(.subheadline.weight(.medium))
            }
            .fontDesign(.rounded)
            .foregroundStyle(.gray.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    }
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
                        .disabled(anySession.isEmpty)
                }
                if #available(iOS 26.0, *) {
                    if !editing { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                }
            }
            .onDisappear { PaceCoordinator.stopAll() }   // a pace playing on a row stops with the page
    }
}
