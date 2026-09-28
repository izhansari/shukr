//
//  PlaceMoments.swift
//  shukr
//
//  Things that happen because of where you are (2026-09-26):
//  • MasjidArrival — the dua for entering when you arrive at one of your own masajid (My masajid),
//    and the dua for leaving when you go. Opt-in (Settings → Masjid), because it needs "Always"
//    location for region monitoring; never required. Geofences (CLMonitor, iOS 17+) around up to
//    20 of your masajid, 100 m; at most one of each per masjid every 3 hours.
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

    private var monitor: CLMonitor?
    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private let manager = CLLocationManager()

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Launch (also a background relaunch for a region event): pick the monitor back up.
    /// One monitor per name per process, ever: creating a second throws ("already in use").
    func start() {
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
        for id in await monitor.identifiers where !wanted.contains(id) {
            await monitor.remove(id)
        }
        let existing = Set(await monitor.identifiers)
        for fav in favorites where !existing.contains(fav.id) {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: fav.latitude, longitude: fav.longitude), radius: 100)
            await monitor.add(condition, identifier: fav.id, assuming: .unsatisfied)
        }
    }

    private func clearConditions() async {
        guard let monitor else { return }
        for id in await monitor.identifiers { await monitor.remove(id) }
    }

    private func handle(_ event: CLMonitor.Event) {
        guard enabled, let fav = MosqueFavorites.all.first(where: { $0.id == event.identifier }) else { return }
        let entering: Bool
        switch event.state {
        case .satisfied: entering = true
        case .unsatisfied: entering = false
        default: return
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
        guard entering != wasInside || !known else { return }
        d.set(entering, forKey: insideKey)
        if entering {
            d.set(Date(), forKey: sinceKey)
            guard known else { return }
        } else {
            let since = d.object(forKey: sinceKey) as? Date
            d.removeObject(forKey: sinceKey)
            guard known, wasInside, let since, Date().timeIntervalSince(since) < 4 * 3600 else { return }
        }
        // Once per masjid and direction every 3 hours (GPS wobble at the edge).
        let key = "masjidArrival.last.\(entering ? "in" : "out").\(fav.id)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 3 * 3600 { return }
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
            UNNotificationRequest(identifier: "masjidArrival.\(UUID().uuidString)", content: content, trigger: nil))
    }
}

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
