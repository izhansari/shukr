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

