//
//  PrayerTimeEditSheet.swift
//  shukr
//
//  Long-press a completed prayer → "when did you pray?". The window bar shows where the picked
//  time lands (green Early for the first 30 min, yellow On time, red Late; past the end is
//  Qaza), the score updates live, and Cancel / Save sit at the bottom as capsules (2026-09-25:
//  the old sheet was a bare Form-style stack with a blue Save next to the score). Save is gray
//  until a different valid time is picked, then a green edge and green text.
//

import SwiftUI

struct PrayerTimeEditSheet: View {
    let prayer: PrayerModel
    @Binding var time: Date
    /// The time being picked lives here until Save (owner saw the bar hang on device: every
    /// minute scrubbed wrote the parent's state and re-rendered the prayer row behind the sheet).
    @State private var draft: Date
    /// From the prayer's start (never earlier) to now or the next Fajr (the day's rollover),
    /// whichever is first. After the window it's Qaza, e.g. Isha at 12:30 AM.
    let range: ClosedRange<Date>
    var onCancel: () -> Void
    var onSave: (Date) -> Void

    init(prayer: PrayerModel, time: Binding<Date>, range: ClosedRange<Date>,
         onCancel: @escaping () -> Void, onSave: @escaping (Date) -> Void) {
        self.prayer = prayer
        self._time = time
        self._draft = State(initialValue: time.wrappedValue)
        self.range = range
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var isValid: Bool { range.contains(draft) }
    /// The time the sheet opened with; Save is off until a different (valid) one is picked.
    @State private var openedWith: Date?
    private var changed: Bool {
        guard let openedWith else { return false }
        return abs(draft.timeIntervalSince(openedWith)) >= 30
    }
    private var canSave: Bool { isValid && changed }

    /// Tap / drag on the window bar: that point of the window, to the minute, kept within what
    /// can be saved (not before the start, not after now).
    private func pickFromBar(_ fraction: Double) {
        let window = prayer.endTime.timeIntervalSince(prayer.startTime)
        let raw = prayer.startTime.addingTimeInterval(window * fraction)
        let minute = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let picked = min(max(minute, range.lowerBound), range.upperBound)
        if picked != draft { draft = picked }
    }

    /// Why an out-of-range time can't be saved: nearer (on the clock) to the start → it's before
    /// the prayer; nearer the other end → it hasn't happened yet, or it's past the day's rollover.
    private var invalidReason: String {
        let cal = Calendar.current
        func clock(_ d: Date) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        func dist(_ a: Date, _ b: Date) -> Double { let x = abs(clock(a) - clock(b)); return min(x, 1440 - x) }
        if dist(draft, range.lowerBound) <= dist(draft, range.upperBound) {
            return "That's before \(prayer.name) started at \(shortTimePM(range.lowerBound))."
        }
        // The upper bound is now unless the day already rolled over before now.
        if range.upperBound < Date().addingTimeInterval(-60) {
            return "That's after Fajr at \(shortTimePM(range.upperBound)) — the next day had started."
        }
        return "That hasn't happened yet — it's \(shortTimePM(range.upperBound)) now."
    }

    private var score: Double {
        PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)
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
            .padding(.top, 30)   // room under the drag handle

            PrayerWindowBar(start: prayer.startTime, end: prayer.endTime,
                            marked: draft, color: isValid ? PrayerScoring.color(for: score) : Color(.tertiaryLabel),
                            onPick: pickFromBar)

            PrayerTimeWheel(time: $draft, day: prayer.startTime, range: range)
                .frame(height: 150)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isValid ? "\(Int((score * 100).rounded()))" : "–")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .contentTransition(.numericText(value: score))
                Text(isValid ? grade.rawValue : "not a valid time")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(isValid ? PrayerScoring.color(for: score) : .secondary)
                    .contentTransition(.opacity)
            }
            .animation(.snappy, value: score)
            .sensoryFeedback(.selection, trigger: grade)

            if !isValid {
                // Out of range: say what is allowed (Save stays off until then).
                Text(invalidReason)
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if !Calendar.current.isDate(draft, inSameDayAs: prayer.startTime) {
                // After midnight, say which day and time this actually is.
                Text(draft.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

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
                    onSave(draft)
                } label: {
                    // Gray until there's something to save; then a green edge and green text
                    // (owner — matches the other Saves; the solid green fill shouted).
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(canSave ? Color.green : Color.secondary)
                        .background(Capsule().strokeBorder(canSave ? Color.green : Color(.separator),
                                                           lineWidth: canSave ? 1.5 : 1))
                        .contentShape(Capsule())
                }
                .disabled(!canSave)
                .animation(.easeInOut(duration: 0.2), value: canSave)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .fontDesign(.rounded)
        .onAppear { if openedWith == nil { openedWith = draft } }
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

/// The prayer's window as a bar: Early (first 30 min) green, On time yellow, Late red, with a
/// marker where the picked time falls. A time after the window (Qaza) parks the marker at the
/// end, gray, with "qaza" under it — the bar itself only shows the window.
private struct PrayerWindowBar: View {
    let start: Date
    let end: Date
    let marked: Date
    let color: Color
    /// Tap or drag on the bar: the fraction of the window under the finger, 0…1.
    var onPick: (Double) -> Void = { _ in }

    var body: some View {
        let total = max(end.timeIntervalSince(start), 1)
        let early = min(PrayerScoring.earlyWindow / total, 1)
        let mid = early + (1 - early) / 2
        let position = min(max(marked.timeIntervalSince(start) / total, 0), 1)
        let isQaza = marked > end
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
                        .animation(.snappy(duration: 0.12), value: position)
                }
                .frame(height: 16)
                // A taller touch target than the 6 pt bar; tap to jump, drag to scrub.
                .contentShape(Rectangle().inset(by: -14))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in onPick(min(max(value.location.x / max(w, 1), 0), 1)) }
                )
            }
            .frame(height: 16)
            HStack {
                Text(shortTimePM(start))
                Spacer()
                Text(isQaza ? "qaza" : shortTimePM(end))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isQaza)
            }
            .font(.caption2)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Time wheel

/// A continuous hour / minute / AM-PM wheel, like the system time wheel: hours loop and AM/PM
/// follows as you scroll past 12, so 11 PM → 12 AM → 1 AM is one scroll. Times outside `range`
/// (before the prayer, after now or the rollover) are grayed but never corrected — the sheet
/// disables Save instead (owner: auto-snapping "doesn't change the wheel" felt wrong; a
/// one-day system wheel snapped Isha's 12 AM back to the start). A picked time lands on the
/// prayer's day or the next, whichever is in range; if neither, `time` is the prayer's-day
/// version and is out of range.
struct PrayerTimeWheel: UIViewRepresentable {
    @Binding var time: Date
    /// Any instant on the prayer's calendar day.
    let day: Date
    let range: ClosedRange<Date>

    private static let loops = 200   // rows = 24 × loops (hours), 60 × loops (minutes)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        context.coordinator.show(time, in: picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if time != context.coordinator.shown { context.coordinator.show(time, in: picker) }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: PrayerTimeWheel
        var shown: Date?
        private var hour24 = 0, minute = 0
        private let cal = Calendar.current

        init(_ parent: PrayerTimeWheel) { self.parent = parent }

        /// The instant for this clock time on the prayer's day or the next, if either is in range.
        private func validDate(_ h: Int, _ m: Int) -> Date? {
            let base = cal.startOfDay(for: parent.day)
            for offset in 0...1 {
                guard let d = cal.date(byAdding: .day, value: offset, to: base),
                      let t = cal.date(bySettingHour: h, minute: m, second: 0, of: d) else { continue }
                if parent.range.contains(t) { return t }
            }
            return nil
        }
        private func dayDate(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.startOfDay(for: parent.day)) ?? parent.day
        }
        /// Cached per hour (the range doesn't change while the sheet is up): each hour row used to
        /// run 60 × 2 calendar lookups every time it was drawn.
        private var hourValidity: [Int: Bool] = [:]
        private func hourValid(_ h: Int) -> Bool {
            if let known = hourValidity[h] { return known }
            let v = (0..<60).contains { validDate(h, $0) != nil }
            hourValidity[h] = v
            return v
        }

        /// Put the wheel on `t` (middle of the loops). The first time reloads everything; after
        /// that (the bar scrubbing) it only selects rows, and refreshes the minutes' graying only
        /// when the hour changed — a full reload per minute hung the bar on device.
        private var loaded = false
        func show(_ t: Date, in picker: UIPickerView) {
            let c = cal.dateComponents([.hour, .minute], from: t)
            let hourChanged = (c.hour ?? 0) != hour24
            hour24 = c.hour ?? 0
            minute = c.minute ?? 0
            shown = t
            if !loaded {
                picker.reloadAllComponents()
                loaded = true
            } else if hourChanged {
                picker.reloadComponent(1)
            }
            picker.selectRow(24 * (PrayerTimeWheel.loops / 2) + hour24, inComponent: 0, animated: false)
            picker.selectRow(60 * (PrayerTimeWheel.loops / 2) + minute, inComponent: 1, animated: false)
            picker.selectRow(hour24 >= 12 ? 1 : 0, inComponent: 2, animated: false)
        }

        private func publish(_ picker: UIPickerView) {
            let t = validDate(hour24, minute) ?? dayDate(hour24, minute)
            shown = t
            parent.time = t
            picker.reloadComponent(0)
            picker.reloadComponent(1)
        }

        // MARK: data source / delegate
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            [24 * PrayerTimeWheel.loops, 60 * PrayerTimeWheel.loops, 2][component]
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { 64 }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            let text: String, valid: Bool
            switch component {
            case 0:
                let h = row % 24
                text = "\(h % 12 == 0 ? 12 : h % 12)"
                valid = hourValid(h)
            case 1:
                let m = row % 60
                text = String(format: "%02d", m)
                valid = validDate(hour24, m) != nil
            default:
                text = row == 0 ? "AM" : "PM"
                valid = true
            }
            label.text = text
            label.textAlignment = .center
            let base = UIFont.systemFont(ofSize: 23, weight: .regular)
            label.font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 23)
            label.textColor = valid ? .label : .tertiaryLabel
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            switch component {
            case 0:
                hour24 = row % 24
                // AM/PM follows the hour, like the system wheel.
                pickerView.selectRow(hour24 >= 12 ? 1 : 0, inComponent: 2, animated: true)
            case 1:
                minute = row % 60
            default:
                // Tapping AM/PM moves the hour 12 either way, to the nearer row.
                let wantPM = row == 1
                if (hour24 >= 12) != wantPM {
                    let current = pickerView.selectedRow(inComponent: 0)
                    let target = wantPM ? current + 12 : current - 12
                    hour24 = (hour24 + 12) % 24
                    pickerView.selectRow(target, inComponent: 0, animated: true)
                }
            }
            publish(pickerView)
        }
    }
}
