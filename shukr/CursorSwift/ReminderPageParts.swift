import SwiftUI

// The pieces of Your Notifications' page, shared so Your Live Activities and Your Fajr Alarms are built the same way
// (owner, 2026-10-14: "match the template of the Your Notifications page … answers why the limit for each, answers
// topping up, and shows breakdown"): a status row, the slots bar, the "why" rows opening an ⓘ card, then what's set up.

/// The page's first row: a shield in green when all is well (orange when something needs him), what's on, how far ahead,
/// and — when there's somewhere to go — a chevron.
struct ReminderPageStatus: View {
    let good: Bool
    let title: String
    let subtitle: String
    /// "Needs a look", in orange, beside the chevron.
    var note: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: good ? "checkmark.shield" : "exclamationmark.shield")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(good ? Color(.systemGreen) : Color.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color(.label))
                Text(subtitle).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let note {
                Text(note).font(.subheadline).foregroundStyle(.orange)
            }
            if action != nil {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 4)
    }
}

/// How full iOS's room for them is, in parts: one coloured run per part, the free room in grey, a key for the parts
/// there are. "23 of 64 in use · 4 kept for snoozes".
struct ReminderSlotsBar: View {
    struct Part {
        let count: Int
        let color: Color
        let label: String
        /// Said in the key instead of the count (Your Data: "4.8 MB").
        var value: String? = nil
    }
    let caption: String
    let limit: Int
    let parts: [Part]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.footnote).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.count > 0 {
                            Rectangle().fill(part.color)
                                .frame(width: max(geo.size.width * CGFloat(part.count) / CGFloat(max(limit, 1)) - 1.5, 2))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // the grey track shows even with nothing in it
                .background(Color(.systemGray5))
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack(spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.count > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(part.color).frame(width: 7, height: 7)
                            Text("\(part.label) \(part.value ?? String(part.count))")
                        }
                    }
                }
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}

/// "Why only 64?" / "Tops itself up": a grey symbol, the question, an orange "Needs a look" when one of his settings is in
/// the way, a chevron; opens its ⓘ card.
struct ReminderWhyLink: View {
    let symbol: String
    let title: String
    var needsLook = false
    var tint = Color(.secondaryLabel)
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Explicit colours: inside a Button's label the hierarchical styles took the tint (blue rows).
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(needsLook ? Color.orange : tint).frame(width: 26)
                Text(title).foregroundStyle(Color(.label))
                Spacer()
                if needsLook {
                    Text("Needs a look").font(.subheadline).foregroundStyle(.orange)
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                } else if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

/// An ⓘ card's body: the headline, the points (green symbol, a bold line, a grey one; orange when it's in the way),
/// a fix when one is needed, then the explaining points.
struct ReminderExplainer: View {
    let head: String
    let points: [ReminderWhy.Point]
    var fix: (title: String, action: () -> Void)? = nil
    var explainHead: String? = nil
    var explain: [ReminderWhy.Point] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(head)
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(points.indices, id: \.self) { row(points[$0]) }
            if let fix {
                Button(fix.title, action: fix.action)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
            }
            if let explainHead {
                Text(explainHead.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(explain.indices, id: \.self) { row(explain[$0]) }
            }
        }
    }

    private func row(_ p: ReminderWhy.Point) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.symbol)
                .font(.system(size: 17))
                .foregroundStyle(p.neutral ? Color.secondary : p.warn ? Color.orange : Color(.systemGreen))
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.big).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(p.warn && !p.neutral ? Color.orange : .primary)
                Text(p.small).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The breakdown's day heading, as Your Notifications' picked day: the day in a headline, its count on the right.
struct ReminderDayHeading: View {
    let title: String
    let count: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            Text(count)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 6)
    }
}

/// The page's title, as Your Notifications sets it: inline, rounded, regular weight.
extension View {
    func reminderPageTitle(_ title: String) -> some View {
        self
            .listStyle(.insetGrouped)
            .fontDesign(.rounded)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.system(.headline, design: .rounded, weight: .regular))
                }
            }
    }
}

extension ReminderWhy.Point {
    /// Every "Tops itself up" says it the same way (AutoTopUp): the moments shukr gets without being opened.
    static let wakes = ReminderWhy.Point(
        big: "Whenever shukr wakes",
        small: "A prayer card starting, a ✓ on a card or the widget, a reminder's button, stopping the alarm, or a big move with Always location: each one tops up your reminders, alarms and cards.",
        symbol: "bolt.horizontal.circle", warn: false)
}
