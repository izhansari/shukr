//
//  PrayerTimeEditSheet.swift
//  shukr
//
//  Long-press a completed prayer → "when did you pray?". The window bar shows where the picked
//  time lands (green Early for the first 30 min, yellow On time, red Late; past the end is
//  Qaza), the score updates live, and Cancel / Save sit at the bottom as capsules (2026-09-25:
//  the old sheet was a bare Form-style stack with a blue Save next to the score).
//

import SwiftUI

struct PrayerTimeEditSheet: View {
    let prayer: PrayerModel
    @Binding var time: Date
    /// From the prayer's start (never earlier) to now.
    let range: ClosedRange<Date>
    var onCancel: () -> Void
    var onSave: (Date) -> Void

    private var score: Double {
        PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: time)
    }

    var body: some View {
        let grade = PrayerScoring.grade(for: score)
        VStack(spacing: 20) {
            // Header, like the main circle's
            VStack(spacing: 4) {
                HStack(alignment: .center) {
                    Image(systemName: prayerIcon(for: prayer.name))
                    Text(prayer.name).fontWeight(.bold)
                }
                .font(.title2)
                Text("when did you pray?")
                    .font(.subheadline)
                    .fontWeight(.thin)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            PrayerWindowBar(start: prayer.startTime, end: prayer.endTime, marked: time, color: PrayerScoring.color(for: score))

            DatePicker("", selection: $time, in: range, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 150)
                .clipped()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((score * 100).rounded()))")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .contentTransition(.numericText(value: score))
                Text(grade.rawValue)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(PrayerScoring.color(for: score))
                    .contentTransition(.opacity)
            }
            .animation(.snappy, value: score)
            .sensoryFeedback(.selection, trigger: grade)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.primary)
                        .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                        .contentShape(Capsule())
                }
                Button {
                    onSave(min(max(time, range.lowerBound), range.upperBound))
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.green))
                        .contentShape(Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .fontDesign(.rounded)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

/// The prayer's window as a bar: Early (first 30 min) green, then On time yellow, then Late red,
/// with a marker where the picked time falls. Past the end, the marker sits at the end in gray.
private struct PrayerWindowBar: View {
    let start: Date
    let end: Date
    let marked: Date
    let color: Color

    var body: some View {
        let total = max(end.timeIntervalSince(start), 1)
        let early = min(PrayerScoring.earlyWindow / total, 1)
        let mid = early + (1 - early) / 2
        let position = min(max(marked.timeIntervalSince(start) / total, 0), 1)
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.green.opacity(0.35)).frame(width: max(w * early - 2, 0))
                        if early < 1 {
                            Capsule().fill(Color.yellow.opacity(0.35)).frame(width: max(w * (mid - early) - 2, 0))
                            Capsule().fill(Color.red.opacity(0.35))
                        }
                    }
                    .frame(height: 6)
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().stroke(color, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .shadow(color: color.opacity(0.4), radius: 4)
                        .offset(x: w * position - 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: position)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text(shortTimePM(start))
                Spacer()
                Text(shortTimePM(end))
            }
            .font(.caption2)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
        }
    }
}
