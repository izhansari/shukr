//
//  FajrTabMocks.swift
//  shukr
//
//  DEBUG mocks (owner, 2026-10-14): three layouts for Settings → Reminders → Fajr Alarm that keep it about the height of
//  the Notifications and Live Activities sides (a status row, a row of five columns). `-demoFajrMock A|B|C|C1|C2|C3` with
//  `-demoSettings -settings.remindersTab fajrAlarm`. Not wired to anything: pictures to choose from.
//

#if DEBUG
import SwiftUI

struct FajrTabMock: View {
    let variant: String
    @State private var on = true

    var body: some View {
        statusRow
        switch variant {
        case "A": presets
        case "B": week
        case "C2": compact; proofBig
        case "C3": compact; proofTimeline
        default: compact
        }
    }

    /// The proof (owner: "showing the calculated time as well as the Fajr time, so someone can double check"): the alarm
    /// in green, Fajr's own time under it — the original design's two lines, under the controls.
    private var proofBig: some View {
        VStack(spacing: 2) {
            Text("Alarm tomorrow 5:10 AM").font(.headline.weight(.semibold)).fontDesign(.rounded).foregroundStyle(Color.green)
            Text("Fajr starts 5:30 AM").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// The proof as a short line: the alarm, the gap the rule makes, then Fajr.
    private var proofTimeline: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("5:10 AM").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.green)
                Text("Alarm").font(.caption2).foregroundStyle(.secondary)
            }
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 2)
                Text("20 min").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).background(Color(.secondarySystemGroupedBackground))
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text("5:30 AM").font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("Fajr starts").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// As the other two sides open: the state in a line, its switch on the right.
    private var statusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: on ? "alarm" : "alarm")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(on ? Color(.systemGreen) : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(on ? "Fajr alarm is on" : "Fajr alarm is off").font(.system(.body, design: .rounded))
                Text(!on ? "Turn it on to wake for Fajr"
                     : variant == "C1" ? "Rings 5:10 AM · Fajr starts 5:30 AM"
                     : variant.hasPrefix("C") && variant != "C" ? "Every morning, moving with Fajr" : "Rings 5:10 AM tomorrow")
                    .font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $on).labelsHidden()
        }
        .padding(.vertical, 2)
    }

    // A: the common rules as five columns, the bells' shape (name, symbol, word); Custom opens the wheels in a sheet.
    private var presets: some View {
        let cols: [(String, String, String, Bool)] = [("At Fajr", "alarm", "start", false), ("10 min", "alarm", "before", false),
                                                      ("20 min", "alarm.fill", "before", true), ("30 min", "alarm", "before", false),
                                                      ("Custom", "slider.horizontal.3", "pick", false)]
        return HStack {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                if i > 0 { Divider() }
                column(c.0, c.1, c.2, picked: c.3)
            }
        }
        .padding(.vertical, 4)
    }

    // B: the next five mornings' alarms (it moves with Fajr), the bells' shape; the row opens the rule's wheels in a sheet.
    private var week: some View {
        let days: [(String, String)] = [("Wed", "5:10"), ("Thu", "5:11"), ("Fri", "5:12"), ("Sat", "5:13"), ("Sun", "5:14")]
        return VStack(spacing: 8) {
            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    if i > 0 { Divider() }
                    column(d.0, i == 0 ? "alarm.fill" : "alarm", d.1, picked: i == 0)
                }
            }
            HStack(spacing: 6) {
                Text("20 min before Fajr starts").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(.footnote, design: .rounded))
        }
        .padding(.vertical, 4)
    }

    // C: no wheels: the minutes with − / +, then before / after and start / end as small menus, on one line.
    private var compact: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: "minus").frame(width: 34, height: 32)
                Text("20 min").font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit().frame(minWidth: 56)
                Image(systemName: "plus").frame(width: 34, height: 32)
            }
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            pill("before")
            pill("Fajr starts")
            Spacer(minLength: 0)
        }
        .font(.system(.subheadline, design: .rounded))
        .padding(.vertical, 4)
    }

    private func pill(_ word: String) -> some View {
        HStack(spacing: 3) {
            Text(word)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    /// prayerCol's shape: the name, the symbol, the word under it.
    private func column(_ name: String, _ symbol: String, _ word: String, picked: Bool) -> some View {
        VStack {
            Text(name).font(.footnote).foregroundStyle(picked ? Color(.systemGreen) : .primary)
                .frame(maxWidth: .infinity)
            Spacer()
            Image(systemName: symbol).foregroundStyle(picked ? Color(.systemGreen) : .secondary).frame(height: 22)
            Spacer()
            Text(word).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
