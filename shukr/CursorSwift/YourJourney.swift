//
//  YourJourney.swift
//  shukr
//
//  Journey phase 4 — Your journey (owner, 2026-10-16: "follow this mockup", board/mocks/journey-phase4; rules in
//  board/mocks/journey/spec.md, Screens 5, Data rules, Milestones). Reached from Journey's "Day N · since …" line.
//  Active days only: days before the first mark don't exist, rates count only the days shukr was used, a break of 7+
//  days folds into one "Away" row, excused prayers are never missed.
//

import SwiftUI
import SwiftData

struct YourJourneyPage: View {
    @Environment(\.circleTheme) private var theme
    let log: JourneyLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your journey").font(.system(size: 32, weight: .light, design: .rounded))
            if let first = log.firstDay {
                Text("Since \(first.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}
