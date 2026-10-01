//
//  PlaceMoments.swift
//  shukr
//
//  Things that happen because of where you are (2026-09-26):
//  • MasjidArrival — the dua for entering when you arrive at one of your own masajid (My masajid),
//    and the dua for leaving when you go. Opt-in (Settings → Masjid), because it needs "Always"
//    location for region monitoring; never required. Geofences (CLMonitor, iOS 17+) around up to
//    20 of your masajid, 200 m (2026-10-01: at 100 m "entering" came once you were inside, phone away);
//    at most one of each per masjid every 3 hours. DEBUG builds keep Library/Caches/masjid.log.
//  • HolyCityWelcome — "Welcome to Makkah" / "Welcome to Madinah" the first time the app sees you
//    there (within ~6 km of the Kaaba / ~5 km of Masjid an-Nabawi); again only after you've been
//    more than 50 km away. A small easter egg (owner, 2026-09-26); the Umrah companion is on the
//    wish list in CLAUDE.md.
//

import Foundation
import CoreLocation
import UserNotifications
import Combine

// MARK: - Masjid arrival duas

@MainActor
final class MasjidArrival {
    static let shared = MasjidArrival()
    static let enabledKey = "masjidArrivalDuas"
    /// The geofence radius: "entering" as you pull into the parking lot, not once you're inside.
    static let radius: CLLocationDistance = 200
    /// The radius the monitor's conditions were added with; a change re-adds them all.
    private static let radiusKey = "masjidArrival.radius"
    /// Re-adding a condition makes the monitor report its state again: a report this soon after is a
    /// baseline, not a crossing.
    private var resyncedAt: Date?

    private var monitor: CLMonitor?
    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private let manager = CLLocationManager()

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Launch (also a background relaunch for a region event): pick the monitor back up.
    /// One monitor per name per process, ever: creating a second throws ("already in use").
    func start() {
        #if DEBUG
        MasjidLog.write("start: enabled \(enabled), always \(hasAlways), monitor \(monitor != nil)")
        #endif
        guard enabled else { return }
        if cancellable == nil {
            cancellable = NotificationCenter.default.publisher(for: MosqueHiding.changed)
                .sink { [weak self] _ in Task { await self?.syncConditions() } }
        }
        if monitor != nil {
            Task { await syncConditions() }
            return
        }
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// The Settings switch. On: asks for "Always" (the system shows its prompt), then watches.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            manager.requestAlwaysAuthorization()
            start()
        } else {
            Task { await clearConditions() }   // the monitor stays; it just watches nothing
        }
    }

    var hasAlways: Bool { manager.authorizationStatus == .authorizedAlways }

    private func run() async {
        // Letters only: "shukr.masajid" crashed ("Monitor name is not valid").
        let monitor = await CLMonitor("shukrMasajid")
        self.monitor = monitor
        await syncConditions()
        do {
            for try await event in await monitor.events {
                handle(event)
            }
        } catch {}
    }

    private func syncConditions() async {
        guard let monitor else { return }
        let favorites = Array(MosqueFavorites.all.prefix(20))
        let wanted = Set(favorites.map(\.id))
        let d = UserDefaults.standard
        // Added with another radius (the old 100 m): add them all again.
        if d.double(forKey: Self.radiusKey) != Self.radius {
            for id in await monitor.identifiers { await monitor.remove(id) }
            d.set(Self.radius, forKey: Self.radiusKey)
            resyncedAt = Date()
            #if DEBUG
            MasjidLog.write("radius → \(Int(Self.radius)) m: conditions re-added")
            #endif
        }
        for id in await monitor.identifiers where !wanted.contains(id) {
            await monitor.remove(id)
            #if DEBUG
            MasjidLog.write("removed \(id)")
            #endif
        }
        let existing = Set(await monitor.identifiers)
        for fav in favorites where !existing.contains(fav.id) {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: fav.latitude, longitude: fav.longitude), radius: Self.radius)
            await monitor.add(condition, identifier: fav.id, assuming: .unsatisfied)
            // The first-visit bug (2026-10-01): with no stored state, the first arrival was taken as a
            // baseline and nothing was sent. A new condition is assumed outside, so record that: the
            // first real arrival is then a crossing. (Starred while standing in it: the monitor reports
            // "inside" at once and that counts as arriving — you're there.)
            let insideKey = "masjidArrival.inside.\(fav.id)"
            if d.object(forKey: insideKey) == nil { d.set(false, forKey: insideKey) }
            #if DEBUG
            MasjidLog.write("watching \(fav.name) (\(Int(Self.radius)) m)")
            #endif
        }
    }

    private func clearConditions() async {
        guard let monitor else { return }
        for id in await monitor.identifiers { await monitor.remove(id) }
    }

    private func handle(_ event: CLMonitor.Event) {
        #if DEBUG
        let stateWord = event.state == .satisfied ? "inside" : event.state == .unsatisfied ? "outside" : "unknown"
        MasjidLog.write("iOS: \(event.identifier) \(stateWord) (event at \(MasjidLog.clock(event.date)))")
        #endif
        guard enabled, let fav = MosqueFavorites.all.first(where: { $0.id == event.identifier }) else { return }
        let entering: Bool
        switch event.state {
        case .satisfied: entering = true
        case .unsatisfied: entering = false
        default: return
        }
        // Just after re-adding the conditions: the monitor's reports are their current state, not crossings.
        if let resyncedAt, Date().timeIntervalSince(resyncedAt) < 30 {
            UserDefaults.standard.set(entering, forKey: "masjidArrival.inside.\(fav.id)")
            if entering { UserDefaults.standard.set(Date(), forKey: "masjidArrival.insideSince.\(fav.id)") }
            #if DEBUG
            MasjidLog.write("→ baseline after re-adding: \(entering ? "inside" : "outside"), nothing sent")
            #endif
            return
        }
        // Only a real crossing (2026-09-28). The monitor reports every region's state when it (re)starts —
        // each launch — and an "outside" there read as leaving: two "Leaving the masjid" duas at once for
        // masajid the owner hadn't been to. Now:
        // • no stored state yet (first run, the key cleared, or launching at the masjid): record, post nothing;
        // • the same state as stored: nothing;
        // • outside → inside: entering (also when iOS relaunches the app for the crossing — that event is
        //   the monitor's first report in the new process, so a blanket "first report is a baseline"
        //   would swallow real arrivals);
        // • inside → outside: leaving only if the arrival was within 4 h; a missed exit hours ago
        //   (phone off, monitor suspended) is cleared silently.
        let d = UserDefaults.standard
        let insideKey = "masjidArrival.inside.\(fav.id)"
        let sinceKey = "masjidArrival.insideSince.\(fav.id)"
        let known = d.object(forKey: insideKey) != nil
        let wasInside = d.bool(forKey: insideKey)
        guard entering != wasInside || !known else {
            #if DEBUG
            MasjidLog.write("→ same as before (\(entering ? "inside" : "outside")), nothing sent")
            #endif
            return
        }
        d.set(entering, forKey: insideKey)
        if entering {
            d.set(Date(), forKey: sinceKey)
            guard known else {
                #if DEBUG
                MasjidLog.write("→ no earlier state: recorded inside, nothing sent")
                #endif
                return
            }
        } else {
            let since = d.object(forKey: sinceKey) as? Date
            d.removeObject(forKey: sinceKey)
            guard known, wasInside, let since, Date().timeIntervalSince(since) < 4 * 3600 else {
                #if DEBUG
                MasjidLog.write("→ left, but no arrival in the last 4 h: nothing sent")
                #endif
                return
            }
        }
        // Once per masjid and direction every 3 hours (GPS wobble at the edge).
        let key = "masjidArrival.last.\(entering ? "in" : "out").\(fav.id)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 3 * 3600 {
            #if DEBUG
            MasjidLog.write("→ \(entering ? "entering" : "leaving") already sent within 3 h, nothing sent")
            #endif
            return
        }
        UserDefaults.standard.set(Date(), forKey: key)
        Self.notify(masjid: fav.name, entering: entering)
    }

    /// The notification itself (also used by the Settings "try it" row).
    static func notify(masjid: String, entering: Bool) {
        let content = UNMutableNotificationContent()
        content.title = masjid
        if entering {
            content.subtitle = "Entering the masjid"
            content.body = "اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ\nAllahumma-ftah li abwaba rahmatik — O Allah, open for me the gates of Your mercy."
        } else {
            content.subtitle = "Leaving the masjid"
            content.body = "اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ\nAllahumma inni as'aluka min fadlik — O Allah, I ask You of Your bounty."
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "masjidArrival.\(UUID().uuidString)", content: content, trigger: nil)) { error in
            #if DEBUG
            MasjidLog.write("→ sent \(entering ? "entering" : "leaving") dua for \(masjid)" + (error.map { ": FAILED \($0.localizedDescription)" } ?? ""))
            #endif
        }
    }
}

#if DEBUG
/// The masjid duas' own log (DEBUG builds), like the compass's: every report from iOS (inside / outside and
/// when iOS says it happened), what the app decided, and each dua sent, in the app's Library/Caches/masjid.log
/// (the last ~500 KB). Pull it with `xcrun devicectl device copy from --device <udid> --domain-type
/// appDataContainer --domain-identifier com.betternorms.shukr --source Library/Caches/masjid.log --destination <file>`.
enum MasjidLog {
    private static let queue = DispatchQueue(label: "shukr.masjidLog", qos: .utility)
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "masjid.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"; return f
    }()

    static func clock(_ date: Date) -> String { stamp.string(from: date) }

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 500_000 {
                let old = url.deletingLastPathComponent().appending(path: "masjid.old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
#endif

// MARK: - Makkah / Madinah welcome

@MainActor
final class HolyCityWelcome {
    static let shared = HolyCityWelcome()
    private var cancellable: AnyCancellable?

    private struct City {
        let key, title, body: String
        let centre: CLLocation
        let radius: CLLocationDistance
    }
    private let cities = [
        City(key: "makkah", title: "Welcome to Makkah",
             body: "May Allah accept your visit to His House. The qibla is all around you now.",
             centre: CLLocation(latitude: 21.4225, longitude: 39.8262), radius: 6_000),
        City(key: "madinah", title: "Welcome to Madinah",
             body: "The city of the Prophet ﷺ. May Allah accept your visit — send salawat upon him.",
             centre: CLLocation(latitude: 24.4672, longitude: 39.6111), radius: 5_000),
    ]

    func start(_ updates: PassthroughSubject<CLLocation?, Never>) {
        cancellable = updates
            .compactMap { $0 }
            .throttle(for: .seconds(30), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.check($0) }
    }

    func check(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        for city in cities {
            let distance = location.distance(from: city.centre)
            let armedKey = "holyCity.away.\(city.key)"
            // Re-armed once you've been well away (first launch counts as away).
            if distance > 50_000 { defaults.set(true, forKey: armedKey); continue }
            guard distance < city.radius, defaults.object(forKey: armedKey) as? Bool ?? true else { continue }
            defaults.set(false, forKey: armedKey)
            let content = UNMutableNotificationContent()
            content.title = city.title
            content.body = city.body
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "holyCity.\(city.key)", content: content, trigger: nil))
        }
    }
}
