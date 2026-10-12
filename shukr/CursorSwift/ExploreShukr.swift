//
//  ExploreShukr.swift
//  shukr
//
//  Settings → Explore shukr (owner, ask settings-explore: "a section in settings … where we can market or sell the other
//  features that we have that we don't really talk about, like the widgets, the lock screen widgets, shortcuts, app
//  intent"). Second pass (owner: "graphics or pics the same way we been doing. and a little more detail"; no Fajr alarm or
//  Live Activities here — Settings has them): each feature in a card — a picture in the setup pages' style (the sage
//  panel, today's real times where they help), its name, why it's nice, what's cool about it, and one action.
//

import SwiftUI

struct ExploreShukrPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("A few things shukr can do outside the app.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                ExploreCard(title: "Home Screen widgets",
                            why: "Your prayer's ring where you'll see it, without opening shukr.",
                            points: ["Mark the prayer done right from the widget",
                                     "Pick its corner buttons: Qibla, Tasbeeh, Daily Ayah or 99 Names",
                                     "Zikr, Name of the Day and Daily Ayah widgets too",
                                     "Its look is set in Settings → Appearance"],
                            steps: ["Touch and hold an empty spot on your Home Screen.",
                                    "Tap Edit, then Add Widget.",
                                    "Search for shukr and pick a size."]) { HomeScreenPicture() }
                ExploreCard(title: "Lock Screen widgets",
                            why: "How long is left at a glance, every time you pick up your phone.",
                            points: ["The circle counts down in a prayer's last hour",
                                     "A line with the prayer and how long is left"],
                            steps: ["Touch and hold your Lock Screen, then tap Customize.",
                                    "Choose your Lock Screen and tap the widget area.",
                                    "Pick one of shukr's."]) { LockScreenPicture() }
                ExploreCard(title: "Control Center",
                            why: "Qibla and Tasbeeh one swipe away, even from another app.",
                            points: ["Qibla opens straight to the compass, Tasbeeh straight to the counter",
                                     "Put them on your Lock Screen or the Action button too"],
                            steps: ["Swipe down from the top-right corner of your screen.",
                                    "Tap + at the top left, then Add a Control.",
                                    "Search for shukr and pick Qibla or Tasbeeh."]) { ControlCenterPicture() }
                ExploreCard(title: "Siri and Shortcuts",
                            why: "Ask without opening anything.",
                            points: ["“Fajr time from shukr” or “Next prayer time from shukr”",
                                     "Prayer times, with an offset, in your own Shortcuts and automations"],
                            action: ("Open Shortcuts", {
                                if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                            })) { SiriPicture() }
                ExploreCard(title: "Apple Watch",
                            why: "Your prayers and your zikr on your wrist.",
                            points: ["Mark prayers with a tap, undo if you slip",
                                     "Count zikr with taps, Double Tap or the Crown",
                                     "The qibla arrow and a map that turns with you",
                                     "Complications for your watch face"],
                            steps: ["Open the Watch app on your iPhone.",
                                    "Scroll to Available Apps.",
                                    "Tap Install next to shukr."]) { WatchPicture() }
                ExploreCard(title: "Memories",
                            why: "A photo after you pray, kept day by day.",
                            points: ["Both cameras at once, the way Locket does",
                                     "Find any photo by prayer, place, note or date, Hijri too",
                                     "On this day, from years before"],
                            action: ("Open Memories", { MemoriesPresenter.shared.open = true })) { MemoriesPicture() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Explore shukr")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}

// MARK: - The card

private struct ExploreCard<Picture: View>: View {
    let title: String
    let why: String
    var points: [String] = []
    var steps: [String]? = nil
    var action: (String, () -> Void)? = nil
    @ViewBuilder let picture: () -> Picture
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            picture()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background {
                    // The setup pages' panel (NotificationDemo, LiveActivityDemo, AlarmDemo).
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Color.sage.opacity(0.55), Color.sage.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
                Text(why).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.sage)
                            Text(point).font(.system(.subheadline, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let steps {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("How to add it")
                        Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
                }
                .buttonStyle(.plain)
                if open {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.sage).frame(width: 14)
                                Text(step).font(.system(.subheadline, design: .rounded))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            if let action {
                Button {
                    triggerSomeVibration(type: .light)
                    action.1()
                } label: {
                    Text(action.0)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.sage)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - The pictures (drawn, today's real times where they help)

/// The prayer the pictures show: whichever is on now (or next), with its real window.
private struct ShownPrayer {
    let name: String
    let start: Date
    let end: Date
    var minutesLeft: Int { max(1, Int(end.timeIntervalSinceNow / 60)) }
    var left: String {
        let m = minutesLeft
        return m >= 60 ? "\(m / 60) hr \(m % 60) min" : "\(m) min"
    }
    var progress: Double {
        let total = end.timeIntervalSince(start)
        return total > 0 ? min(max(Date().timeIntervalSince(start) / total, 0.05), 0.95) : 0.4
    }
    static var now: ShownPrayer {
        let now = Date()
        for p in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
            if let w = prayerWindowToday(p), now < w.end { return ShownPrayer(name: p, start: w.start, end: w.end) }
        }
        return ShownPrayer(name: "Asr", start: now.addingTimeInterval(-40 * 60), end: now.addingTimeInterval(100 * 60))
    }
}

/// A ring like the widget's: a soft track and the arc, sage.
private struct MiniRing: View {
    let progress: Double
    var width: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct HomeScreenPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        HStack(spacing: 14) {
            // The Prayers widget, small.
            VStack(spacing: 8) {
                ZStack {
                    MiniRing(progress: p.progress, width: 6).frame(width: 74, height: 74)
                    VStack(spacing: 1) {
                        Image(systemName: prayerIcon(for: p.name)).font(.system(size: 13, weight: .light))
                        Text(p.name).font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
                HStack {
                    Image(systemName: "location.north.line")
                    Spacer()
                    Image(systemName: "circle.hexagonpath")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }
            .padding(12)
            .frame(width: 124, height: 132)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            // App icons around it, as on a Home Screen.
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color(.systemBackground).opacity(0.55))
                                .frame(width: 52, height: 52)
                        }
                    }
                }
            }
        }
    }
}

private struct LockScreenPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        VStack(spacing: 10) {
            // A Lock Screen's clock: no AM / PM.
            Text(Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            HStack(spacing: 12) {
                // The circle: the prayer's ring; in its last hour the time left replaces the symbol ("27m").
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Circle().trim(from: 0, to: p.progress).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(5)
                    Group {
                        if p.minutesLeft < 60 { Text("\(p.minutesLeft)m").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                        else { Image(systemName: prayerIcon(for: p.name)).font(.system(size: 15)) }
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                // The line.
                VStack(alignment: .leading, spacing: 2) {
                    Label(p.name, systemImage: prayerIcon(for: p.name)).font(.system(size: 13, weight: .semibold))
                    Text("\(p.left) left").font(.system(size: 12))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.18)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.2, blue: 0.17), Color(red: 0.06, green: 0.08, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

private struct ControlCenterPicture: View {
    var body: some View {
        let ours: [Int: (String, String)] = [1: ("location.north.line", "Qibla"), 2: ("circle.hexagonpath", "Tasbeeh")]
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { i in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(ours[i] != nil ? Color(.systemBackground) : Color(.systemBackground).opacity(0.4))
                        if let (symbol, _) = ours[i] {
                            Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(Color.sage)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(ours[i] != nil ? 0.12 : 0), radius: 5, y: 2)
                    Text(ours[i]?.1 ?? " ").font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

private struct SiriPicture: View {
    var body: some View {
        let next = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
            .compactMap { p in prayerWindowToday(p).map { (p, $0.start) } }
            .first { $0.1 > Date() }
        VStack(alignment: .leading, spacing: 10) {
            Text("“Next prayer time from shukr”")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color(.systemBackground).opacity(0.6)))
            HStack(spacing: 10) {
                Image(systemName: prayerIcon(for: next?.0 ?? "Fajr")).font(.system(size: 20, weight: .light))
                VStack(alignment: .leading, spacing: 1) {
                    Text(next?.0 ?? "Fajr").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(next.map { "at \($0.1.formatted(date: .omitted, time: .shortened))" } ?? "tomorrow morning")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
    }
}

private struct WatchPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.black)
                .frame(width: 118, height: 140)
            RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.primary.opacity(0.25), lineWidth: 5)
                .frame(width: 126, height: 148)
            // The Crown.
            Capsule().fill(Color.primary.opacity(0.35)).frame(width: 7, height: 26).offset(x: 67, y: -18)
            ZStack {
                MiniRing(progress: p.progress, width: 6).frame(width: 82, height: 82)
                VStack(spacing: 1) {
                    Image(systemName: prayerIcon(for: p.name)).font(.system(size: 12))
                    Text(p.name).font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

private struct MemoriesPicture: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let tilt = [-9.0, 6.0, 0.0][i]
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [[Color(red: 0.55, green: 0.66, blue: 0.6), Color(red: 0.75, green: 0.68, blue: 0.55),
                                                   Color(red: 0.42, green: 0.55, blue: 0.62)][i], .white.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 112, height: 112)
                    .overlay(alignment: .topLeading) {
                        // The front camera, inset (the Locket look).
                        if i == 2 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.86, green: 0.78, blue: 0.7))
                                .frame(width: 34, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2))
                                .padding(8)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 3))
                    .rotationEffect(.degrees(tilt))
                    .offset(x: CGFloat(i - 1) * 14)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
            }
        }
    }
}
