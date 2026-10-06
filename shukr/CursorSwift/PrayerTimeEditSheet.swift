//
//  PrayerTimeEditSheet.swift
//  shukr
//
//  Long-press a completed prayer → "when did you pray?". The window bar shows where the picked
//  time lands (green Perfect for the first 30 min, yellow On time, red Late; past the end is
//  Qaza), the score updates live, and Cancel / Save sit at the bottom as capsules (2026-09-25:
//  the old sheet was a bare Form-style stack with a blue Save next to the score). Save is gray
//  until a different valid time is picked, then a green edge and green text.
//

import SwiftUI
import MapKit

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
    /// The time, and the new spot if the pin was moved (nil = where it was).
    var onSave: (Date, CLLocationCoordinate2D?) -> Void

    /// Where it was prayed (2026-09-26): a chip under the header opens `PrayerLocationPicker`; the
    /// picked spot waits here and is saved with Save, like the time. Off when the sheet is opened
    /// from the prayer map, which moves pins on the map itself.
    var showsLocation = true
    @State private var draftSpot: CLLocationCoordinate2D?
    @State private var pickingSpot = false
    @State private var spotAddress: String?
    private var savedSpot: CLLocationCoordinate2D? {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var shownSpot: CLLocationCoordinate2D? { draftSpot ?? savedSpot }

    init(prayer: PrayerModel, time: Binding<Date>, range: ClosedRange<Date>, showsLocation: Bool = true,
         onCancel: @escaping () -> Void, onSave: @escaping (Date, CLLocationCoordinate2D?) -> Void) {
        self.prayer = prayer
        self.showsLocation = showsLocation
        self._time = time
        // Open on the time saved for this prayer (owner, 2026-09-26). The parent's binding isn't
        // enough: it's written in the same long-press that presents the sheet, and the sheet came
        // up with the value from before — the device's time. Kept within what can be saved.
        let saved = prayer.timeAtComplete ?? time.wrappedValue
        self._draft = State(initialValue: min(max(saved, range.lowerBound), range.upperBound))
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
    /// The tour's fix step saves any changed time (tour v2, owner: "change its time, and save").
    /// The tour's Fajr fix saves only a time in the yellow (owner, 2026-10-06), until it's done.
    private var canSave: Bool {
        isValid && (changed || draftSpot != nil) && (!TourRuntime.shared.needsYellow(prayer) || draftInYellow)
    }
    private var draftInYellow: Bool {
        PrayerScoring.grade(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)) == .onTime
    }

    /// Where it was prayed, as a quiet chip under "when did you pray?" (owner, 2026-09-26: a full
    /// row above the buttons sat oddly): the masjid, else the address; tap to move the pin.
    private var spotChip: some View {
        // Before a move the stored masjid is right; after one, only your own masajid are known yet.
        let masjid = draftSpot == nil ? (prayer.atMasjid ? prayer.mosqueName : nil)
                                      : draftSpot.flatMap { MasjidDetector.favoriteMasjid(near: $0) }
        let title = shownSpot == nil ? "Add where you prayed"
                                     : (masjid ?? spotAddress ?? "Pinned on the map")
        let moved = draftSpot != nil
        return Button { pickingSpot = true } label: {
            HStack(spacing: 5) {
                Image(systemName: masjid != nil ? "building.columns.fill" : "mappin")
                    .font(.caption)
                Text(title).lineLimit(1)
                if moved {
                    Text("· moved").foregroundStyle(Color.green)
                } else if prayer.spotEdited {
                    Text("· edited").foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .foregroundStyle(masjid != nil ? Color.sage : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .overlay(Capsule().strokeBorder(moved ? Color.green.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: moved)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tour's fix step is in this sheet: its tip continues here (audit J: "nothing goes silent").
    private var tourTip: Bool { TourRuntime.shared.step == .list && TourRuntime.isPracticeAnywhere(prayer) }

    var body: some View {
        VStack(spacing: 20) {
            if tourTip { TourSheetTip().padding(.top, 26) }
            // Header, like the main circle's
            VStack(spacing: 4) {
                HStack(alignment: .center) {
                    Image(systemName: prayerIcon(for: prayer.name))
                    Text(prayer.displayName).fontWeight(.bold)
                }
                .font(.title2)
                Text("when did you pray?")
                    .font(.subheadline)
                    .fontWeight(.thin)
                    .foregroundStyle(.secondary)
                // Not in the tour: its fix step is the time alone (owner: only the intended thing).
                if showsLocation && !tourTip {
                    spotChip.padding(.top, 8)
                }
            }
            .padding(.top, tourTip ? 0 : 30)   // room under the drag handle

            PrayerTimeEditor(prayer: prayer, draft: $draft, range: range)

            Spacer(minLength: 0)

            SaveCancelButtons(canSave: canSave, onCancel: onCancel) { onSave(draft, draftSpot) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .fontDesign(.rounded)
        .onAppear { if openedWith == nil { openedWith = draft } }
        .sheet(isPresented: $pickingSpot) {
            PrayerLocationPicker(prayerName: prayer.displayName, original: shownSpot,
                                 recorded: prayer.recordedSpot ?? savedSpot,
                                 onCancel: { pickingSpot = false },
                                 onPick: { spot in draftSpot = spot; pickingSpot = false })
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
        .task(id: shownSpot.map { "\($0.latitude),\($0.longitude)" }) {
            spotAddress = nil
            if let spot = shownSpot { spotAddress = await PrayerSpotAddress.lookUp(spot) }
        }
        // The tour's tip at the largest text: the full height, else Save fell off the sheet (Sami, AX XXXL).
        .presentationDetents([tourTip && typeSize.isAccessibilitySize
                              ? .large : .height((showsLocation && !tourTip ? 572 : 540) + (tourTip ? 132 : 0))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

/// The heart of editing a prayer's time: the window bar (tap / drag to scrub), the wheel, the
/// score it would get, the recorded time to go back to, and why an impossible time can't be saved.
/// Used by the time editor sheet and inline on the map's prayer page.
struct PrayerTimeEditor: View {
    let prayer: PrayerModel
    @Binding var draft: Date
    /// From the prayer's start to now or the next Fajr (the day's rollover).
    let range: ClosedRange<Date>
    /// The big score line (the map's prayer page shows the score in its header instead).
    var showsScore = true

    var isValid: Bool { range.contains(draft) }
    /// The tour's practice clock (0 for a real prayer).
    private var shift: TimeInterval { PracticeClock.shift(for: prayer) }
    /// A Jumu'ah isn't graded by the clock (full marks, "Jumu'ah"), so the editor agrees with Save.
    private var score: Double {
        prayer.isJumuah ? 1 : PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)
    }

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
            return "That's before \(prayer.name) started at \(shortTimePM(range.lowerBound.addingTimeInterval(shift)))."
        }
        // The upper bound is now unless the day already rolled over before now.
        if range.upperBound < Date().addingTimeInterval(-60) {
            return "That's after Fajr at \(shortTimePM(range.upperBound.addingTimeInterval(shift))) — the next day had started."
        }
        return "That hasn't happened yet — it's \(shortTimePM(range.upperBound.addingTimeInterval(shift))) now."
    }

    var body: some View {
        let grade = PrayerScoring.grade(for: score)
        VStack(spacing: 20) {
            PrayerWindowBar(start: prayer.startTime, end: prayer.endTime, labelShift: shift,
                            marked: draft, color: isValid ? PrayerScoring.color(for: score) : Color(.tertiaryLabel),
                            onPick: pickFromBar)

            // The tour's practice prayer reads on its plain clock (PracticeClock): the wheel shows, and picks, shifted times.
            PrayerTimeWheel(time: Binding(get: { draft.addingTimeInterval(shift) }, set: { draft = $0.addingTimeInterval(-shift) }),
                            day: prayer.startTime.addingTimeInterval(shift),
                            range: range.lowerBound.addingTimeInterval(shift)...range.upperBound.addingTimeInterval(shift))
                .frame(height: 150)

            if showsScore {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isValid ? "\(Int((score * 100).rounded()))" : "–")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .contentTransition(.numericText(value: score))
                    Text(isValid ? (prayer.isJumuah ? "Jumu'ah" : grade.rawValue) : "not a valid time")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(isValid ? PrayerScoring.color(for: score) : .secondary)
                        .contentTransition(.opacity)
                }
                .animation(.snappy, value: score)
            }

            // Edited before: what the app recorded, one tap to go back to it.
            if let recorded = prayer.recordedTimeAtComplete, abs(draft.timeIntervalSince(recorded)) >= 30 {
                Button {
                    draft = min(max(recorded, range.lowerBound), range.upperBound)
                } label: {
                    Label("You marked it at \(shortTimePM(recorded.addingTimeInterval(shift))) · use that", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            if !isValid {
                // Out of range: say what is allowed (Save stays off until then).
                Text(invalidReason)
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else if !Calendar.current.isDate(draft, inSameDayAs: prayer.startTime) {
                // After midnight, say which day and time this actually is.
                Text(draft.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: grade)
    }
}

/// Cancel / Save as capsules: Save gray until there's something to save, then a green edge and
/// green text (owner — the solid green fill shouted).
struct SaveCancelButtons: View {
    let canSave: Bool
    var saveTitle = "Save"
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
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
            Button(action: onSave) {
                Text(saveTitle)
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
}

/// The prayer's window as a bar: Perfect (first 30 min) green, On time yellow, Late red, with a
/// marker where the picked time falls. A time after the window (Qaza) parks the marker at the
/// end, gray, with "qaza" under it — the bar itself only shows the window.
struct PrayerWindowBar: View {
    let start: Date
    let end: Date
    /// Moves the shown start / end (the tour's practice clock).
    var labelShift: TimeInterval = 0
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
                Text(shortTimePM(start.addingTimeInterval(labelShift)))
                Spacer()
                Text(isQaza ? "qaza" : shortTimePM(end.addingTimeInterval(labelShift)))
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
