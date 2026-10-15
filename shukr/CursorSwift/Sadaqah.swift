//
//  Sadaqah.swift
//  shukr
//
//  Settings → Sneak Peek → Sadaqah (owner, 2026-10-13, idea sadaqah-links): a short list of vetted charities that open
//  their own donation page in a Safari sheet, and a private log of what you gave. Closing the charity's page always asks
//  "Did you donate to …?" (owner: every time); "Log a donation" records anything given elsewhere. shukr never touches
//  the payment. The log is a JSON file in Application Support (no SwiftData model, so no schema change), on this phone
//  only, in its backup.
//

import SwiftUI
import SafariServices

// MARK: - The charities

/// One vetted charity: what it does, why it's listed, and the page its Donate button opens.
struct SadaqahCharity: Identifiable, Hashable {
    let id: String
    let name: String
    /// What they mainly do, one short line.
    let does: String
    let symbol: String
    let url: URL
    /// The kinds of work it does (a charity can be in several; the page's filter).
    var categories: Set<SadaqahCategory> = []
    /// Its ⓘ sheet: a few sentences on the work, then the facts behind listing it (registration, rating, where).
    var about: String = ""
    var facts: [SadaqahFact] = []
    /// Which side of the page it's on.
    var kind: GiveKind = .sadaqah
}

/// The page's two sides (owner, 2026-10-13: one place to give — sadaqah and community; no candidates).
enum GiveKind: String, CaseIterable, Identifiable {
    case sadaqah, community
    var id: String { rawValue }
    var title: String { self == .sadaqah ? "Sadaqah" : "Community" }
    /// Under the switch, so the difference is clear while choosing (owner).
    var meaning: String {
        switch self {
        case .sadaqah: "Charities that help people in need: relief, orphans, water. What you give here counts as your sadaqah."
        case .community: "Muslim groups working for our community's rights, voice and future. Kept apart from your sadaqah and zakat."
        }
    }
    var footer: String {
        switch self {
        case .sadaqah: "Tap ⓘ to see who they are and why they're here. Each opens on the charity's own website; shukr takes nothing and never sees your payment."
        case .community: "Muslim groups working for our community's rights and voice. Tap ⓘ to learn more. Each opens on the group's own website; shukr takes nothing and never sees your payment."
        }
    }
}

/// One line of a charity's ⓘ sheet.
struct SadaqahFact: Hashable {
    let symbol: String
    let text: String
}

/// The page's filter: All, or one kind of work (owner: grouped once the list grows); each side has its own.
/// ("In the US" went when IMAN and Muslim Legal Fund moved to Community: only ICNA Relief was left in it.)
enum SadaqahCategory: String, CaseIterable, Identifiable {
    case relief, orphans, water
    case civilRights, civic, legal, local, research
    var id: String { rawValue }
    var kind: GiveKind {
        switch self {
        case .relief, .orphans, .water: .sadaqah
        default: .community
        }
    }
    static func of(_ kind: GiveKind) -> [SadaqahCategory] { allCases.filter { $0.kind == kind } }
    var title: String {
        switch self {
        case .relief: "Emergency relief"
        case .orphans: "Orphans"
        case .water: "Water"
        case .civilRights: "Civil rights"
        case .civic: "Civic & voting"
        case .legal: "Legal defense"
        case .local: "Local community"
        case .research: "Research & education"
        }
    }
    var symbol: String {
        switch self {
        case .relief: "cross.case.fill"
        case .orphans: "figure.and.child.holdinghands"
        case .water: "drop.fill"
        case .civilRights: "hand.raised.fill"
        case .civic: "checkmark.seal.fill"
        case .legal: "building.columns.fill"
        case .local: "house.fill"
        case .research: "book.fill"
        }
    }
}

enum SadaqahCharities {
    /// The list, checked 2026-10-13 (Izhan approves it): US 501(c)(3)s rated 4 stars by Charity Navigator, plus the owner's
    /// picks — Help Yateem (UK charity 1158571), Human Development Fund, MATW Project, Paani Project (US nonprofits, no
    /// Charity Navigator star rating yet) — each on its own donation page. Left out: Islamic Relief USA (renamed IDEA after its split from Islamic Relief Worldwide in
    /// Sep 2026; irusa.org is gone), Mercy-USA (3 stars), and platforms (LaunchGood, MyTenNights).
    private static func nonprofit(_ ein: String) -> SadaqahFact {
        SadaqahFact(symbol: "building.columns", text: "US nonprofit, 501(c)(3) · EIN \(ein)")
    }
    private static func rated(_ score: Int, stars: Int = 4) -> SadaqahFact {
        SadaqahFact(symbol: "star", text: "Charity Navigator: \(score) / 100, \(stars == 4 ? "four" : "three") stars (Oct 2026)")
    }
    private static let notRated = SadaqahFact(symbol: "star", text: "Not yet rated by Charity Navigator")
    private static func works(_ text: String) -> SadaqahFact { SadaqahFact(symbol: "globe", text: text) }

    static let all: [SadaqahCharity] = [
        SadaqahCharity(id: "zakat", name: "Zakat Foundation of America", does: "Zakat, emergency relief and education worldwide",
                       symbol: "hands.and.sparkles.fill", url: URL(string: "https://www.zakat.org/donate")!,
                       categories: [.relief],
                       about: "Founded in 2001, it puts zakat and sadaqah into direct aid, emergency relief and education for people in need.",
                       facts: [nonprofit("36-4476244"), rated(95), works("Works worldwide")]),
        SadaqahCharity(id: "hhrd", name: "Helping Hand for Relief and Development", does: "Disaster relief, orphans, water and health",
                       symbol: "hand.raised.fill", url: URL(string: "https://www1.hhrd.org/DetailDonate")!,
                       categories: [.relief, .orphans, .water],
                       about: "A Michigan-based relief and development charity: disaster response, orphan sponsorship, clean water and health care.",
                       facts: [nonprofit("31-1628040"), rated(100), works("Works worldwide and in the US")]),
        SadaqahCharity(id: "hdf", name: "Human Development Fund", does: "Emergency food, clean water, orphans and medical relief",
                       symbol: "heart.circle.fill", url: URL(string: "https://give.hdfund.org/campaign/649760/donate")!,
                       categories: [.relief, .orphans, .water],
                       about: "Started by Muslim Americans from the relief world: emergency food, clean water, orphan sponsorship and medical relief.",
                       facts: [nonprofit("92-2204466"), notRated, works("Works in about 27 countries")]),
        SadaqahCharity(id: "matw", name: "MATW Project", does: "Water, orphans and food for those in need",
                       symbol: "globe.asia.australia.fill", url: URL(string: "https://matwprojectusa.org/donate")!,
                       categories: [.water, .orphans, .relief],
                       about: "Muslims Around The World: wells and water, orphan care and food for families in need. This is its US branch.",
                       facts: [nonprofit("92-1915834"), notRated, works("Works worldwide")]),
        SadaqahCharity(id: "paani", name: "Paani Project", does: "Wells, water aid and disaster relief in Pakistan",
                       symbol: "drop.fill", url: URL(string: "https://paaniproject.org/donate/")!,
                       categories: [.water, .relief],
                       about: "Run by volunteers from Michigan. It builds wells and gives water aid and disaster relief, and sends donors photos and video of the finished well.",
                       facts: [nonprofit("83-2222109"), notRated, works("Works in Pakistan and Jordan")]),
        SadaqahCharity(id: "life", name: "Life for Relief and Development", does: "Relief and development for families in need",
                       symbol: "leaf.fill", url: URL(string: "https://donate.lifeusa.org/donorportal/?donate=true")!,
                       categories: [.relief],
                       about: "A Michigan-based relief and development charity working since 1992: emergency aid, food, health and education.",
                       facts: [nonprofit("95-4402149"), rated(98), works("Works worldwide")]),
        SadaqahCharity(id: "baitulmaal", name: "Baitulmaal", does: "Orphans, water and relief",
                       symbol: "sun.max.fill", url: URL(string: "https://baitulmaal.org/donate/")!,
                       categories: [.orphans, .water, .relief],
                       about: "Based in Texas: orphan sponsorship, clean water and emergency relief in Africa, Asia and the Middle East.",
                       facts: [nonprofit("20-0942434"), rated(95), works("Works in Africa, Asia and the Middle East")]),
        SadaqahCharity(id: "muslimaid", name: "Muslim Aid America", does: "Disaster relief and fighting poverty",
                       symbol: "shippingbox.fill", url: URL(string: "https://www.mausa.org/donate-now/")!,
                       categories: [.relief],
                       about: "The US arm of Muslim Aid: disaster relief and long-term work against poverty.",
                       facts: [nonprofit("46-2504422"), rated(95), works("Works worldwide")]),
        SadaqahCharity(id: "penny", name: "Penny Appeal USA", does: "Water, education and relief",
                       symbol: "drop.circle.fill", url: URL(string: "https://www.pennyappealusa.org/donate/")!,
                       categories: [.water, .relief],
                       about: "The US branch of Penny Appeal, a Muslim charity founded in the UK in 2009: water, education, livelihoods and emergency relief.",
                       facts: [nonprofit("47-5165837"), rated(96), works("Works worldwide")]),
        SadaqahCharity(id: "yateem", name: "Help Yateem", does: "Orphans and orphanages around the world",
                       symbol: "figure.and.child.holdinghands", url: URL(string: "https://donate.helpyateem.org/")!,
                       categories: [.orphans],
                       about: "Supports orphans and orphanages: sponsorships, food, schooling and care.",
                       facts: [SadaqahFact(symbol: "building.columns", text: "Registered UK charity · no. 1158571"),
                               SadaqahFact(symbol: "star", text: "UK charity, so not rated by Charity Navigator"),
                               works("Works worldwide")]),
        SadaqahCharity(id: "icna", name: "ICNA Relief USA", does: "Food pantries, shelters and disaster relief in the US",
                       symbol: "house.fill", url: URL(string: "https://icnarelief.org/donate/")!,
                       categories: [.relief],
                       about: "Helps people in the US: food pantries, women's shelters, family services and disaster relief across the US.",
                       facts: [nonprofit("04-3810161"), rated(93), works("Works across the US")]),
        SadaqahCharity(id: "iman", name: "IMAN", does: "Health, wellness and community in Chicago",
                       symbol: "building.2.fill", url: URL(string: "https://imancentral.org/donate/")!,
                       categories: [.local],
                       about: "The Inner-City Muslim Action Network: a free health center, housing, job training and the arts on Chicago's South Side.",
                       facts: [nonprofit("36-4167433"), rated(94), works("Works in Chicago")], kind: .community),
        SadaqahCharity(id: "mlfa", name: "Muslim Legal Fund of America", does: "Legal defense for Muslims in the US",
                       symbol: "building.columns.fill", url: URL(string: "https://mlfa.org/donate")!,
                       categories: [.legal],
                       about: "Pays for lawyers in cases where Muslims in America face injustice: civil rights, discrimination and religious freedom.",
                       facts: [nonprofit("01-0548371"), rated(92), works("Works across the US")], kind: .community),
        // Community, checked 2026-10-13 (owner: sadaqah and community, no candidates; never a tax-deductible claim).
        SadaqahCharity(id: "ispu", name: "ISPU", does: "Research and polling on American Muslims",
                       symbol: "chart.bar.fill", url: URL(string: "https://ispu.donorsupport.co/-/XZJZAYEL")!,
                       categories: [.research],
                       about: "The Institute for Social Policy and Understanding: research and polling on American Muslims, used by journalists, policymakers and communities.",
                       facts: [nonprofit("38-3633581"), rated(97), works("Works across the US")], kind: .community),
        SadaqahCharity(id: "emgage", name: "Emgage Foundation", does: "Muslim voter education and civic engagement",
                       symbol: "checkmark.seal.fill", url: URL(string: "https://emgageusa.org/donate/")!,
                       categories: [.civic],
                       about: "Helps American Muslims register, learn about the issues and vote, with chapters in several states.",
                       facts: [nonprofit("26-1441032"), rated(97), works("Works across the US")], kind: .community),
        SadaqahCharity(id: "mpac", name: "MPAC Foundation", does: "Policy and media advocacy for American Muslims",
                       symbol: "megaphone.fill", url: URL(string: "https://www.mpac.org/donate")!,
                       categories: [.civilRights],
                       about: "The Muslim Public Affairs Council's foundation: policy work, media and training so American Muslims are heard.",
                       facts: [nonprofit("95-4675391"), rated(88, stars: 3), works("Works across the US")], kind: .community),
        SadaqahCharity(id: "muslimadvocates", name: "Muslim Advocates", does: "Fighting anti-Muslim discrimination in court and policy",
                       symbol: "hand.raised.fill", url: URL(string: "https://muslimadvocates.org/donate/")!,
                       categories: [.civilRights, .legal],
                       about: "Takes on anti-Muslim discrimination through lawsuits and policy work.",
                       facts: [nonprofit("30-0298794"), rated(82, stars: 3), works("Works across the US")], kind: .community),
        SadaqahCharity(id: "ing", name: "Islamic Networks Group", does: "Teaching about Islam in schools and communities",
                       symbol: "book.fill", url: URL(string: "https://ing.org/donate/")!,
                       categories: [.research],
                       about: "ING trains speakers who teach about Islam and Muslims in schools, workplaces and interfaith settings.",
                       facts: [nonprofit("77-0412815"), rated(86, stars: 3), works("Works across the US")], kind: .community),
        SadaqahCharity(id: "aman", name: "AMAN", does: "Community services and masjid support in Brooklyn",
                       symbol: "person.3.fill", url: URL(string: "https://amanusa.org/donation/")!,
                       categories: [.local],
                       about: "The American Muslim Advocacy Network: community services, masjid support and Ask the Mufti, based in Brooklyn.",
                       facts: [nonprofit("33-1743599"), notRated, works("Works in Brooklyn, New York")], kind: .community),
    ]
}


// MARK: - The log

/// One donation in the log.
struct SadaqahDonation: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Where it went: a listed charity's name, or whatever was typed.
    var to: String
    /// A listed charity's id, when it came from the list.
    var charityID: String?
    var amount: Double
    var currency: String
    var purpose: SadaqahPurpose
    var note: String
    var date: Date
}

/// What a donation was for.
enum SadaqahPurpose: String, Codable, CaseIterable, Identifiable {
    case unspecified, sadaqah, zakat, zakatFitr, jariyah, fidya, kaffarah, qurbani, ramadan, relief, orphans, masjid, community, other
    var id: String { rawValue }
    /// The For menu's choices (owner: "way too many options … no more than four", optional): None, Sadaqah, Zakat,
    /// Community. The others stay readable for donations logged with them.
    static let offered: [SadaqahPurpose] = [.unspecified, .sadaqah, .zakat, .community]
    /// Which side of the page it counts towards (Zakat / Sadaqah totals never include community gifts).
    var kind: GiveKind { self == .community ? .community : .sadaqah }
    var title: String {
        switch self {
        case .unspecified: "None"
        case .sadaqah: "Sadaqah"
        case .zakat: "Zakat"
        case .zakatFitr: "Zakat al-Fitr"
        case .jariyah: "Sadaqah Jariyah"
        case .fidya: "Fidya"
        case .kaffarah: "Kaffarah"
        case .qurbani: "Qurbani"
        case .ramadan: "Ramadan"
        case .relief: "Emergency relief"
        case .orphans: "Orphans"
        case .masjid: "Masjid"
        case .community: "Community"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .unspecified: "circle.dashed"
        case .sadaqah: "heart.fill"
        case .zakat: "scalemass.fill"
        case .zakatFitr: "sparkles"
        case .jariyah: "drop.fill"
        case .fidya: "fork.knife"
        case .kaffarah: "arrow.uturn.backward.circle.fill"
        case .qurbani: "leaf.fill"
        case .ramadan: "moon.stars.fill"
        case .relief: "cross.case.fill"
        case .orphans: "figure.and.child.holdinghands"
        case .masjid: "building.columns.fill"
        case .community: "person.3.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

/// The private log: a JSON file, read once, written on every change.
@Observable
final class SadaqahLog {
    static let shared = SadaqahLog()

    private(set) var donations: [SadaqahDonation] = []

    /// The phone's currency (amounts are typed in it).
    static var currency: String { Locale.current.currency?.identifier ?? "USD" }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sadaqah", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("donations.json")
    }()

    /// The file is there but couldn't be read: it's written with complete protection, so a launch while the phone is
    /// locked (a background wake builds Settings, and this) can't read it. Never written over then — it read as empty, and
    /// the next save replaced the whole log (perf-recheck review, 2026-10-14) — and read again before any change.
    private var fileUnread = false

    @discardableResult private func load() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { fileUnread = false; return true }
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder.sadaqah.decode([SadaqahDonation].self, from: data) else { fileUnread = true; return false }
        donations = list.sorted { $0.date > $1.date }
        fileUnread = false
        return true
    }

    private init() {
        load()
        // Unlocked again: what couldn't be read is read now.
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self, self.fileUnread else { return }
            self.load()
        }
        #if DEBUG
        // `-demoDonations`: stand-ins to look at (in memory; written only if one is edited).
        if ProcessInfo.processInfo.arguments.contains("-demoDonations") {
            let day: TimeInterval = 86_400
            func d(_ to: String, _ amount: Double, _ p: SadaqahPurpose, _ ago: Double) -> SadaqahDonation {
                SadaqahDonation(to: to, charityID: nil, amount: amount, currency: Self.currency, purpose: p, note: "", date: .now - ago * day)
            }
            donations = [d("Zakat Foundation of America", 250, .zakat, 2), d("Paani Project", 60, .relief, 9),
                         d("Emgage Foundation", 40, .community, 15), d("Help Yateem", 35, .orphans, 34),
                         d("Masjid Al-Noor", 20, .masjid, 41), d("Muslim Legal Fund of America", 75, .community, 50),
                         d("Zakat Foundation of America", 100, .sadaqah, 63)]
        }
        #endif
    }

    func save(_ donation: SadaqahDonation) {
        if fileUnread { load() }
        if let i = donations.firstIndex(where: { $0.id == donation.id }) { donations[i] = donation } else { donations.append(donation) }
        donations.sort { $0.date > $1.date }
        write()
    }

    func delete(_ donation: SadaqahDonation) {
        if fileUnread { load() }
        donations.removeAll { $0.id == donation.id }
        write()
    }

    private func write() {
        guard !fileUnread else { return }   // never over a log that couldn't be read
        guard let data = try? JSONEncoder.sadaqah.encode(donations) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// The total given in `currency` since `start` (other currencies are left out of a total, not converted).
    func total(since start: Date? = nil, purpose: SadaqahPurpose? = nil, kind: GiveKind? = nil) -> Double {
        donations.filter { d in
            d.currency == Self.currency
                && (start.map { d.date >= $0 } ?? true)
                && (purpose.map { d.purpose == $0 } ?? true)
                && (kind.map { d.purpose.kind == $0 } ?? true)
        }
        .reduce(0) { $0 + $1.amount }
    }

    /// The log as a spreadsheet (date, to, the organization's EIN when it's a listed US nonprofit, for, amount, currency,
    /// note), oldest first — what someone keeping their records needs. The EIN is a fact, never a deductibility claim.
    func csv() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current   // the day it was given here (UTC put an evening gift on the next day)
        func cell(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func ein(_ d: SadaqahDonation) -> String {
            // The listed charity it came from, or one typed by its name ("+" logs aren't linked to the list).
            let typed = d.to.trimmingCharacters(in: .whitespaces)
            guard let c = SadaqahCharities.all.first(where: { $0.id == d.charityID })
                    ?? SadaqahCharities.all.first(where: { $0.name.caseInsensitiveCompare(typed) == .orderedSame }) else { return "" }
            return c.facts.lazy.compactMap { fact in fact.text.range(of: "EIN ").map { String(fact.text[$0.upperBound...]) } }.first ?? ""
        }
        let rows = donations.sorted { $0.date < $1.date }.map { d in
            [f.string(from: d.date), cell(d.to), ein(d), d.purpose == .unspecified ? "" : d.purpose.title,
             String(format: "%.2f", d.amount), d.currency, cell(d.note)]
                .joined(separator: ",")
        }
        return (["Date,To,EIN,For,Amount,Currency,Note"] + rows).joined(separator: "\n")
    }
}

private extension JSONEncoder {
    static let sadaqah: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
private extension JSONDecoder {
    static let sadaqah: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

private extension Double {
    func money(_ code: String = SadaqahLog.currency) -> String {
        formatted(.currency(code: code).precision(.fractionLength(self == rounded() ? 0 : 2)))
    }
}

// MARK: - The page

struct SadaqahPage: View {
    @State private var log = SadaqahLog.shared
    @State private var editing: DonationDraft?
    /// The charity whose page just closed: the small "Did you donate to …?" sheet.
    @State private var asking: SadaqahCharity?
    /// Set by its Yes: the log sheet opens once the question has gone.
    @State private var confirmed: SadaqahCharity?
    /// Sadaqah | Community (owner).
    @State private var kind: GiveKind = .sadaqah
    /// The charities shown: all, or one kind of work.
    @State private var category: SadaqahCategory?
    /// The charity whose ⓘ sheet is up.
    @State private var info: SadaqahCharity?
    /// Its Donate: the site opens once the ⓘ sheet has gone.
    @State private var donateAfterInfo: SadaqahCharity?
    /// Swiped away: asked once before it goes.
    @State private var deleting: SadaqahDonation?
    /// The page's title has scrolled under the bar: the bar shows it.
    @State private var titleInBar = false
    /// Every donation, from a tap on the total.
    @State private var showHistory = false
    /// Kinds of giving, explained.
    @State private var showGuide = false

    private var startOfYear: Date { Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now }

    var body: some View {
        List {
            // The top, in the log sheet's look (owner): the title light and centred, then this year's total big.
            Section {
                // A tap on the total opens every donation (owner).
                Button { showHistory = true } label: { totals.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden)
                VStack(spacing: 10) {
                    kindSwitch
                    Text(kind.meaning)
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                        .id(kind)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
            }
            Section {
                ForEach(shownCharities) { charity in
                    HStack(spacing: 4) {
                        Button { give(to: charity) } label: { CharityRow(charity: charity) }
                            .buttonStyle(.plain)
                        // More about it (owner: an ⓘ, not a check mark on every row).
                        Button { info = charity } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 19))
                                .foregroundStyle(Color.sage)
                                .frame(width: 36, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .listRowBackground(Self.card)
                }
            } header: {
                HStack {
                    // How many are shown, so a filter visibly works (owner).
                    Text("Organizations · \(shownCharities.count)")
                    Spacer()
                    CategoryFilter(kind: kind, selection: $category).textCase(nil)
                }
            } footer: {
                Text(kind.footer)
            }
            Section {
                if log.donations.isEmpty {
                    Button { editing = DonationDraft(manual: ()) } label: {
                        Label("Log a donation", systemImage: "plus.circle.fill").foregroundStyle(Color.sage)
                    }
                    .listRowBackground(Self.card)
                }
                ForEach(log.donations.prefix(5)) { d in
                    Button { editing = DonationDraft(editing: d) } label: { DonationRow(donation: d) }
                        .buttonStyle(.plain)
                        // Not `.destructive`: the List would expect the row gone and the confirm never showed.
                        .swipeActions { Button { deleting = d } label: { Image(systemName: "trash.fill") }.tint(.red) }
                        .listRowBackground(Self.card)
                }
                if log.donations.count > 5 {
                    NavigationLink("All donations (\(log.donations.count))") { SadaqahHistoryPage() }
                        .listRowBackground(Self.card)
                }
            } header: {
                Text("Your donations")
            } footer: {
                Text("Private: on this phone, and in your iCloud backup if you turn it on. Gave somewhere else? Log it with +.")
            }
        }
        // The new-task flow's page: white, soft grey cards, no gap under the bar.
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .listSectionSpacing(18)
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("Give to Causes")   // the back button's word on pages pushed from here
        .navigationBarTitleDisplayMode(.inline)
        // The title is on the page; once it has scrolled under the bar, the bar shows it (owner: it stays up top).
        .toolbar {
            // Kinds of giving (owner: "sadaqah versus zakat … I myself get confused").
            ToolbarItem(placement: .topBarTrailing) {
                Button { showGuide = true } label: { Image(systemName: "info.circle") }   // owner: an info button, not a book
                    .accessibilityLabel("Kinds of giving")
            }
            // Log a donation (owner): the bar's own button, so iOS 26 draws it in Liquid Glass.
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = DonationDraft(manual: ()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log a donation")
            }
            ToolbarItem(placement: .principal) {
                Text("Give to Causes").font(.headline).fontDesign(.rounded)
                    .opacity(titleInBar ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: titleInBar)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 44
        } action: { _, under in
            titleInBar = under
        }
        .fontDesign(.rounded)
        .navigationDestination(isPresented: $showHistory) { SadaqahHistoryPage() }
        .sheet(isPresented: $showGuide) { GivingGuideSheet() }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-demoGivingGuide") { showGuide = true } }   // with -demoSadaqah
        #endif
        .sheet(item: $asking, onDismiss: {
            if let charity = confirmed { confirmed = nil; editing = DonationDraft(after: charity) }
        }) { charity in
            DidYouDonateSheet(charity: charity) { confirmed = charity; asking = nil }
        }
        .sheet(item: $editing) { DonationSheet(draft: $0) }
        .sheet(item: $info, onDismiss: {
            if let charity = donateAfterInfo { donateAfterInfo = nil; give(to: charity) }
        }) { charity in
            CharityInfoSheet(charity: charity) { donateAfterInfo = charity; info = nil }
        }
        .alert("Delete this donation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { d in
            Button("Delete", role: .destructive) { withAnimation { log.delete(d) } }
            Button("Cancel", role: .cancel) {}
        } message: { d in
            Text("\(d.amount.money(d.currency)) to \(d.to)")
        }
    }

    /// The organizations on the side shown, through the filter.
    private var shownCharities: [SadaqahCharity] {
        SadaqahCharities.all.filter { c in c.kind == kind && (category.map { c.categories.contains($0) } ?? true) }
    }

    /// The charity's own page; closing it always asks (owner).
    private func give(to charity: SadaqahCharity) {
        SadaqahSafari.open(charity.url) { asking = charity }
    }

    /// Sadaqah | Community, in the goal page's capsule switch (NewTaskFlow's Count | Minutes); a switch clears the filter.
    private var kindSwitch: some View {
        HStack(spacing: 0) {
            ForEach(GiveKind.allCases) { k in
                let on = kind == k
                Button {
                    guard k != kind else { return }
                    withAnimation(.snappy(duration: 0.25)) { kind = k; category = nil }
                } label: {
                    Text(k.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .frame(width: 128, height: 34)
                        .background(Capsule().fill(on ? Color(.systemBackground) : .clear)
                            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 4, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .sensoryFeedback(.selection, trigger: kind)
    }

    /// The soft grey of the log sheet's cards.
    static let card = Color.primary.opacity(0.045)

    /// The page's title, then this year's total big, as the log sheet shows an amount; the count (and the sadaqah / community split) under it.
    private var totals: some View {
        let year = log.total(since: startOfYear)
        let count = log.donations.filter { $0.date >= startOfYear }.count
        let community = log.total(since: startOfYear, kind: .community)
        return VStack(spacing: 6) {
            Text("Give to Causes").font(.system(size: 30, weight: .light, design: .rounded))
            Text("Trusted places to give, and a private record of what you've given")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(year.money())
                .font(.system(size: 60, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 14)
            HStack(spacing: 4) {
                Text(count == 0 ? "Given this year" : "Given this year · " + detailLine(count: count, community: community, year: year))
                    .multilineTextAlignment(.center)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func detailLine(count: Int, community: Double, year: Double) -> String {
        guard count > 0 else { return "Nothing logged yet this year" }
        var parts = [count == 1 ? "1 donation" : "\(count) donations"]
        // Only numbers that add up to the big one (owner: Zakat beside them read as a sum that didn't add up). Zakat,
        // Ramadan and the rest are in Your donations' filter.
        if community > 0, community < year {
            parts.append("Sadaqah \((year - community).money())")
            parts.append("Community \(community.money())")
        }
        return parts.joined(separator: " · ")
    }
}

/// The filter, beside "Organizations" (owner), in Azkar's sort-button look: the plain glyph on All; a green tinted pill
/// with the category's symbol and name while one is picked.
private struct CategoryFilter: View {
    let kind: GiveKind
    @Binding var selection: SadaqahCategory?
    var body: some View {
        Menu {
            Picker("Show", selection: Binding(get: { selection }, set: { new in
                withAnimation(.snappy(duration: 0.25)) { selection = new }
            })) {
                Label("All", systemImage: "square.grid.2x2").tag(SadaqahCategory?.none)
                ForEach(SadaqahCategory.of(kind)) { c in
                    Label(c.title, systemImage: c.symbol).tag(Optional(c))
                }
            }
            .pickerStyle(.inline)
        } label: {
            if let selection {
                HStack(spacing: 5) {
                    Image(systemName: selection.symbol).font(.caption)
                    Text(selection.title).font(.subheadline)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Color.green.opacity(0.16)))
                .fixedSize()
            } else {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 30, alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .tint(selection == nil ? Color.primary : Color.green)
        .accessibilityLabel(selection.map { "Filter: \($0.title)" } ?? "Filter")
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct CharityRow: View {
    let charity: SadaqahCharity
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: charity.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.sage))
            VStack(alignment: .leading, spacing: 2) {
                Text(charity.name).font(.body.weight(.semibold))
                Text(charity.does).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct DonationRow: View {
    let donation: SadaqahDonation
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: donation.purpose == .unspecified ? "gift.fill" : donation.purpose.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sage)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.sage.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(donation.to).lineLimit(1)
                // No "For" picked: just the day (owner: it's optional).
                Text((donation.purpose == .unspecified ? "" : "\(donation.purpose.title) · ") + donation.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(donation.amount.money(donation.currency)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - History

/// What Your donations shows (owner: "how much was sadaqah, how much was community, which groups"): everything, one side,
/// one "For", or one organization.
enum DonationFilter: Hashable {
    case kind(GiveKind)
    case purpose(SadaqahPurpose)
    case to(String)

    var title: String {
        switch self {
        case .kind(let k): k.title
        case .purpose(let p): p == .sadaqah ? "General sadaqah" : p.title
        case .to(let name): name
        }
    }
    var symbol: String {
        switch self {
        case .kind(let k): k == .sadaqah ? "heart.fill" : "person.3.fill"
        case .purpose(let p): p.symbol
        case .to: "building.2.fill"
        }
    }
    func matches(_ d: SadaqahDonation) -> Bool {
        switch self {
        case .kind(let k): d.purpose.kind == k
        case .purpose(let p): d.purpose == p
        case .to(let name): d.to == name
        }
    }
}

struct SadaqahHistoryPage: View {
    @State private var log = SadaqahLog.shared
    @State private var editing: DonationDraft?
    @State private var asking: SadaqahDonation?
    @State private var filter: DonationFilter?
    /// When (owner: a date range too); nil = all time.
    @State private var range: DonationRange?
    @State private var pickingDates = false

    private var shown: [SadaqahDonation] {
        log.donations.filter { d in
            (filter.map { $0.matches(d) } ?? true) && (range.map { $0.interval.contains(d.date) } ?? true)
        }
    }

    /// The donations by month, newest first.
    private var months: [(title: String, items: [SadaqahDonation])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: shown) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { start in
            (start.formatted(.dateTime.month(.wide).year()), groups[start] ?? [])
        }
    }

    private static func sum(_ list: [SadaqahDonation]) -> Double {
        list.filter { $0.currency == SadaqahLog.currency }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            if !log.donations.isEmpty {
                // The total for what's shown, big, as on the page before (owner: the log sheet's look).
                Section {
                    VStack(spacing: 4) {
                        Text(Self.sum(shown).money())
                            .font(.system(size: 48, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(([shown.count == 1 ? "1 donation" : "\(shown.count) donations"]
                              + [filter?.title, range?.title].compactMap { $0 }).joined(separator: " · ")
                             + (filter == nil && range == nil ? " in all" : ""))
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        Spacer()
                        DonationRangeMenu(range: $range) { pickingDates = true }.textCase(nil)
                        DonationFilterMenu(filter: $filter, donations: log.donations).textCase(nil)
                    }
                }
            }
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.items) { d in
                        Button { editing = DonationDraft(editing: d) } label: { DonationRow(donation: d) }
                            .buttonStyle(.plain)
                            // Not `.destructive`: the List would expect the row gone and the confirm never showed.
                            .swipeActions { Button { asking = d } label: { Image(systemName: "trash.fill") }.tint(.red) }
                            .listRowBackground(SadaqahPage.card)
                    }
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text(Self.sum(month.items).money())
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle("Your donations")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .animation(.snappy(duration: 0.25), value: filter)
        .overlay {
            if log.donations.isEmpty {
                ContentUnavailableView("No donations yet", systemImage: "gift", description: Text("Tap + to log one."))
            }
        }
        // A filter that matches nothing any more (its last donation deleted) lets go.
        .onChange(of: log.donations) { _, _ in if shown.isEmpty { filter = nil } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: SadaqahExport(text: log.csv()), preview: SharePreview("shukr donations.csv")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(log.donations.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = DonationDraft(manual: ()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log a donation")
            }
        }
        .sheet(item: $editing) { DonationSheet(draft: $0) }
        .sheet(isPresented: $pickingDates) {
            DateRangeSheet(start: range?.interval.start ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!,
                           end: range?.interval.end ?? .now) { from, to in
                withAnimation(.snappy(duration: 0.25)) { range = .custom(from, to) }
            }
        }
        .alert("Delete this donation?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { d in
            Button("Delete", role: .destructive) { log.delete(d) }
            Button("Cancel", role: .cancel) {}
        } message: { d in
            Text("\(d.amount.money(d.currency)) to \(d.to)")
        }
    }
}

/// Your donations' "when" (owner: a date range filter too).
enum DonationRange: Hashable {
    case thisMonth, last30, thisYear, lastYear, ramadan
    case custom(Date, Date)

    static let presets: [DonationRange] = [.thisMonth, .last30, .thisYear, .lastYear, .ramadan]

    var interval: DateInterval {
        let cal = Calendar.current
        let now = Date.now
        switch self {
        case .thisMonth: return cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        case .last30: return DateInterval(start: cal.date(byAdding: .day, value: -30, to: now)!, end: now)
        case .thisYear: return cal.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 0)
        case .lastYear:
            let last = cal.date(byAdding: .year, value: -1, to: now)!
            return cal.dateInterval(of: .year, for: last) ?? DateInterval(start: last, duration: 0)
        case .ramadan: return Self.latestRamadan
        case .custom(let from, let to):
            let start = cal.startOfDay(for: min(from, to))
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(from, to)))!
            return DateInterval(start: start, end: end)
        }
    }

    var title: String {
        switch self {
        case .thisMonth: "This month"
        case .last30: "Last 30 days"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .ramadan: "Ramadan \(Calendar.current.component(.year, from: Self.latestRamadan.start))"
        case .custom(let from, let to):
            "\(min(from, to).formatted(.dateTime.month(.abbreviated).day())) – \(max(from, to).formatted(.dateTime.month(.abbreviated).day().year()))"
        }
    }

    /// This Ramadan if it has begun, else last year's (Umm al-Qura).
    static var latestRamadan: DateInterval {
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = .current
        let year = hijri.component(.year, from: .now)
        func ramadan(_ y: Int) -> DateInterval? {
            hijri.date(from: DateComponents(year: y, month: 9, day: 1)).flatMap { hijri.dateInterval(of: .month, for: $0) }
        }
        if let this = ramadan(year), this.start <= .now { return this }
        return ramadan(year - 1) ?? DateInterval(start: .now, duration: 0)
    }
}

/// The date range's menu: a calendar glyph, or the green pill with the range while one is picked.
private struct DonationRangeMenu: View {
    @Binding var range: DonationRange?
    let pickDates: () -> Void
    var body: some View {
        Menu {
            Button { withAnimation(.snappy(duration: 0.25)) { range = nil } } label: {
                Label("All time", systemImage: range == nil ? "checkmark" : "infinity")
            }
            Section {
                ForEach(DonationRange.presets, id: \.self) { r in
                    Button { withAnimation(.snappy(duration: 0.25)) { range = r } } label: {
                        Label(r.title, systemImage: range == r ? "checkmark" : r == .ramadan ? "moon.stars" : "calendar")
                    }
                }
            }
            Button(action: pickDates) { Label("Choose dates…", systemImage: "calendar.badge.clock") }
        } label: {
            if let range {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.caption)
                    Text(range.title).font(.subheadline).lineLimit(1)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Color.green.opacity(0.16)))
            } else {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .tint(range == nil ? Color.primary : Color.green)
        .sensoryFeedback(.selection, trigger: range)
    }
}

/// "Choose dates…": from and to, then Done.
private struct DateRangeSheet: View {
    @State var start: Date
    @State var end: Date
    let onDone: (Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, in: ...Date.now, displayedComponents: .date)
                DatePicker("To", selection: $end, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Choose dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(start, end); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .fontDesign(.rounded)
        .presentationDetents([.height(260)])
    }
}

/// Your donations' filter: the plain glyph, or the green pill with the filter's name (as on the main page). Its menu lists
/// only what's in the log: Sadaqah / Community, each "For" used, each organization given to.
private struct DonationFilterMenu: View {
    @Binding var filter: DonationFilter?
    let donations: [SadaqahDonation]

    /// The "For"s used, without Community (Type covers it).
    private var purposes: [SadaqahPurpose] {
        SadaqahPurpose.allCases.filter { p in p != .community && donations.contains { $0.purpose == p } }
    }
    private var names: [String] {
        Array(Set(donations.map(\.to))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        Menu {
            option(nil, "All donations", "square.grid.2x2")
            Section("Type") {
                ForEach(GiveKind.allCases) { k in option(.kind(k), k.title, DonationFilter.kind(k).symbol) }
            }
            if purposes.count > 1 {
                Section("For") {
                    // "General sadaqah", so it isn't read as Type's Sadaqah (which includes zakat and the rest).
                    ForEach(purposes) { p in option(.purpose(p), p == .sadaqah ? "General sadaqah" : p.title, p.symbol) }
                }
            }
            if names.count > 1 {
                Section("Organization") {
                    ForEach(names, id: \.self) { n in option(.to(n), n, "building.2") }
                }
            }
        } label: {
            if let filter {
                HStack(spacing: 5) {
                    Image(systemName: filter.symbol).font(.caption)
                    Text(filter.title).font(.subheadline).lineLimit(1)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Color.green.opacity(0.16)))   // hugs the words
                .frame(maxWidth: 260, alignment: .trailing)              // a long name is cut short, never the row
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filter")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
        }
        .tint(filter == nil ? Color.primary : Color.green)
        .sensoryFeedback(.selection, trigger: filter)
    }

    /// One choice, ticked when it's the one shown.
    private func option(_ value: DonationFilter?, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { filter = value }
        } label: {
            Label(title, systemImage: filter == value ? "checkmark" : symbol)
        }
    }
}

/// The log as a .csv file for the share sheet.
struct SadaqahExport: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shukr donations.csv")
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - "Did you donate?" / Log a donation

/// What the sheet opens with: after a charity's page, a new manual entry, or an existing one to edit.
struct DonationDraft: Identifiable {
    let id = UUID()
    var donation: SadaqahDonation
    /// After a charity's page (its Yes): To is that charity, fixed.
    var askedAfterVisit = false
    var isNew = true

    init(after charity: SadaqahCharity) {
        donation = SadaqahDonation(to: charity.name, charityID: charity.id, amount: 0, currency: SadaqahLog.currency,
                                   purpose: charity.kind == .community ? .community : .sadaqah, note: "", date: .now)   // known from the list (owner)
        askedAfterVisit = true
    }
    init(manual: Void) {
        donation = SadaqahDonation(to: "", charityID: nil, amount: 0, currency: SadaqahLog.currency,
                                   purpose: .unspecified, note: "", date: .now)
    }
    init(editing existing: SadaqahDonation) {
        donation = existing
        isNew = false
    }
}

/// The log's one sheet, in the new-task flow's look (NewTaskFlow): a heading, the amount big in the middle with quick
/// amounts under it, one card of rows (To · For as a dropdown · When · Note), and the outlined sage button.
struct DonationSheet: View {
    let draft: DonationDraft
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    /// The amount as typed: digits and one decimal point, at most two places (`AmountInput`).
    @State private var amountText: String
    @State private var purpose: SadaqahPurpose
    @State private var note: String
    @State private var date: Date
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private static let quickAmounts: [Double] = [10, 25, 50, 100]

    init(draft: DonationDraft) {
        self.draft = draft
        _to = State(initialValue: draft.donation.to)
        _amountText = State(initialValue: draft.donation.amount > 0 ? AmountInput.text(for: draft.donation.amount) : "")
        _purpose = State(initialValue: draft.donation.purpose)
        _note = State(initialValue: draft.donation.note)
        _date = State(initialValue: draft.donation.date)
    }

    private var amount: Double { AmountInput.value(amountText) }
    private var canSave: Bool { amount > 0 && !to.trimmingCharacters(in: .whitespaces).isEmpty }
    private var symbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = draft.donation.currency
        return f.currencySymbol ?? "$"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 22) {
                    heading
                    amountField
                    quickAmounts
                    card {
                        if draft.askedAfterVisit {
                            row("building.2", "To") { Text(to).foregroundStyle(.secondary).lineLimit(1) }
                        } else {
                            row("building.2", "To") {
                                TextField("Charity, masjid…", text: $to)
                                    .multilineTextAlignment(.trailing)
                                    .submitLabel(.done)
                            }
                        }
                        Divider().padding(.leading, 52)
                        purposeMenu
                        Divider().padding(.leading, 52)
                        row("calendar", "When") {
                            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date).labelsHidden()   // the day is enough (owner)
                        }
                        Divider().padding(.leading, 52)
                        row("note.text", "Note") {
                            TextField("Optional", text: $note)
                                .multilineTextAlignment(.trailing)
                                .submitLabel(.done)
                        }
                    }
                    if !draft.isNew {
                        Button("Delete Donation", role: .destructive) { confirmDelete = true }
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            Button(action: save) {
                Text(draft.isNew ? "Save" : "Save changes")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .frame(width: 240, height: 52)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fontDesign(.rounded)
        .presentationDetents([.large])
        .interactiveDismissDisabled(canSave && draft.isNew)
        .confirmationDialog("Delete this donation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Donation", role: .destructive) { SadaqahLog.shared.delete(draft.donation); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .barGlass(Circle())   // Liquid Glass (owner)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var heading: some View {
        let title = draft.isNew ? "Log a donation" : "Your donation"
        let subtitle = draft.askedAfterVisit ? "To \(draft.donation.to)" : draft.isNew ? "Anything you gave, anywhere" : "Tap anything to change it"
        return VStack(spacing: 6) {
            Text(title).font(.system(size: 30, weight: .light, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    /// The amount, big: the currency sign, then what's typed (empty shows a faint 0).
    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(symbol).foregroundStyle(amountText.isEmpty ? .tertiary : .primary)
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .fixedSize()
                .onChange(of: amountText) { _, t in
                    let clean = AmountInput.clean(t)
                    if clean != t { amountText = clean }
                }
        }
        .font(.system(size: 60, weight: .light, design: .rounded))
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
    }

    /// $10 · $25 · $50 · $100 in the goal page's capsule switch.
    private var quickAmounts: some View {
        HStack(spacing: 0) {
            ForEach(Self.quickAmounts, id: \.self) { value in
                let on = amount == value
                Button {
                    amountText = AmountInput.text(for: value)
                    amountFocused = false
                } label: {
                    Text(value.money(draft.donation.currency))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .frame(width: 72, height: 34)
                        .background(Capsule().fill(on ? Color(.systemBackground) : .clear)
                            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 4, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    /// For: a dropdown (owner: not every choice on screen at once).
    private var purposeMenu: some View {
        Menu {
            Picker("For", selection: $purpose) {
                // Four up front (owner: "no more than four"); the rest folded under More.
                ForEach(SadaqahPurpose.offered) { p in Label(p.title, systemImage: p.symbol).tag(p) }
            }
            Menu("More") {
                Picker("More", selection: $purpose) {
                    ForEach(SadaqahPurpose.allCases.filter { !SadaqahPurpose.offered.contains($0) }) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: purpose.symbol).foregroundStyle(Color.sage).frame(width: 24)
                Text("For").foregroundStyle(.primary)
                Spacer()
                Text(purpose.title).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 20)
    }

    private func row<Value: View>(_ icon: String, _ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.sage).frame(width: 24)
            Text(label).foregroundStyle(.primary).lineLimit(1).fixedSize()   // "When" never wraps beside the date
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func save() {
        var d = draft.donation
        d.to = to.trimmingCharacters(in: .whitespaces)
        d.amount = amount
        d.purpose = purpose
        d.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        d.date = date
        SadaqahLog.shared.save(d)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}

/// A charity's ⓘ: what it does and the facts behind listing it, then Donate.
private struct CharityInfoSheet: View {
    let charity: SadaqahCharity
    let onDonate: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: charity.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.sage))
            VStack(spacing: 8) {
                Text(charity.name)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)   // long names wrap, never "Develo…" (owner)
                Text(charity.about)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            VStack(spacing: 0) {
                ForEach(Array(charity.facts.enumerated()), id: \.offset) { i, fact in
                    if i > 0 { Divider().padding(.leading, 52) }
                    HStack(spacing: 12) {
                        Image(systemName: fact.symbol).foregroundStyle(Color.sage).frame(width: 24)
                        Text(fact.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
            Button(action: onDonate) {
                Text("Donate")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .frame(width: 240, height: 50)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        .padding(.top, 26)
        .frame(maxWidth: .infinity)
        .fontDesign(.rounded)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// "Sadaqah, zakat and more" (owner): what each kind of giving is, in a few lines, in the log sheet's look.
/// ⚠️ Written as plain, widely agreed summaries (no hadith quoted); like the other religious copy in the app, it needs a
/// knowledgeable check before release (CLAUDE.md, Open items).
struct GivingGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Kind: Identifiable, Hashable {
        let id: String
        let symbol: String
        let title: String
        /// The one thing to know, on the list.
        let line: String
        /// The rest, a tap away.
        let more: String
    }
    private struct Group: Identifiable {
        let id: String
        let kinds: [Kind]
    }

    /// Checked 2026-10-13 against mainstream sources (Zakat Foundation, IslamQA, SeekersGuidance, Darul Ifta Birmingham,
    /// Muslim Aid, Human Appeal); still for a knowledgeable check before release. Grouped by when you give, one line each,
    /// the rest a tap away (owner, decision giving-guide-voice A: it read like an AI list article — no taglines, no icons,
    /// "schools differ" said once at the foot).
    private static let groups: [Group] = [
        Group(id: "Every year", kinds: [
            Kind(id: "zakat", symbol: "scalemass.fill", title: "Zakat",
                 line: "2.5% of savings you've held for a full year above the nisab.",
                 more: "One of the five pillars. Count what you've saved: cash, gold and silver, investments. If it has stayed above the nisab, a set minimum, for a full Islamic year, 2.5% of it is your zakat. It goes to the people the Qur'an names, among them the poor and people in debt."),
        ]),
        Group(id: "Any time", kinds: [
            Kind(id: "sadaqah", symbol: "heart.fill", title: "Sadaqah",
                 line: "Any gift, any amount. A kind word counts too.",
                 more: "There's no minimum and no set time, and it doesn't have to be money. Helping someone, or a smile, is sadaqah as well."),
            Kind(id: "jariyah", symbol: "drop.fill", title: "Sadaqah Jariyah",
                 line: "A gift that keeps helping after you've gone, like a well or a Qur'an someone reads.",
                 more: "Its reward keeps reaching you for as long as people benefit from it, even after you pass away. A well people drink from, a masjid people pray in, or knowledge people keep learning from."),
        ]),
        Group(id: "Ramadan and Eid", kinds: [
            Kind(id: "fitr", symbol: "sparkles", title: "Zakat al-Fitr",
                 line: "About one meal per person in your home, before the Eid prayer.",
                 more: "Owed for every person in your household at the end of Ramadan. Give it before the Eid prayer, so people in need can celebrate too. Your masjid usually announces the amount each year."),
            Kind(id: "fidya", symbol: "fork.knife", title: "Fidya",
                 line: "One meal for someone in need for each fast you can never make up.",
                 more: "For when you're too ill or too old to fast and can't make the days up. If you can make them up later, you do that instead. Fasts missed for your period or after childbirth are made up later, with no fidya. If you're pregnant or nursing you make the days up too; schools differ on whether fidya is also owed."),
            Kind(id: "kaffarah", symbol: "arrow.uturn.backward", title: "Kaffarah",
                 line: "For a Ramadan fast broken on purpose: fast 60 days in a row, or feed 60 people.",
                 more: "You make up the day itself either way. Which cases also need kaffarah depends on your school of thought. A broken oath has its own, smaller kaffarah."),
            Kind(id: "qurbani", symbol: "leaf.fill", title: "Qurbani",
                 line: "An animal at Eid al-Adha, its meat shared.",
                 more: "A sheep, goat, cow or camel, sacrificed in the days of Eid al-Adha, with the meat shared among family, friends and people in need. Some schools hold it's required if you can afford it, others that it's strongly encouraged. Many charities can do it for you abroad."),
        ]),
        Group(id: "Not yours to keep", kinds: [
            Kind(id: "riba", symbol: "percent", title: "Bank interest",
                 line: "Give it away. It doesn't count as zakat or sadaqah.",
                 more: "Islam forbids earning interest. If some still lands in your account, many scholars say to pass it on to people in need, without counting it as your zakat or sadaqah."),
        ]),
    ]

    /// The page's title has scrolled under the bar: the bar shows it (owner).
    @State private var titleInBar = false

    var body: some View {
        // In its own NavigationStack: the ✕ is the bar's own button (Liquid Glass on iOS 26 — owner), the title goes up
        // into the bar as it scrolls, and a row pushes its page.
        NavigationStack {
            List {
                VStack(spacing: 6) {
                    Text("Kinds of giving").font(.system(size: 30, weight: .light, design: .rounded))
                    Text("What each one is, in a few lines").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Self.groups) { group in
                    Section {
                        ForEach(group.kinds) { k in
                            NavigationLink(value: k) {
                                HStack(alignment: .top, spacing: 12) {
                                    KindSymbol(symbol: k.symbol, size: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(k.title).font(.body.weight(.medium))
                                        Text(k.line).font(.subheadline).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .listRowBackground(SadaqahPage.card)
                        }
                    } header: {
                        Text(group.id).foregroundStyle(Color.sage)
                    }
                }
                Section {} footer: { Self.footer(.center) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Kind.self) { KindPage(kind: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text("Kinds of giving").font(.headline).fontDesign(.rounded)
                        .opacity(titleInBar ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: titleInBar)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 50
            } action: { _, under in
                titleInBar = under
            }
        }
        .fontDesign(.rounded)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // Owner: the imam at your masjid, not "a scholar" — easier to find.
    private static func footer(_ alignment: TextAlignment) -> some View {
        Text("Schools differ on the details. The imam at your masjid can tell you what applies to you.")
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.top, 4)
    }

    /// The kind's symbol in a sage circle (the page's colour, as the Give page's rows have).
    private struct KindSymbol: View {
        let symbol: String
        let size: CGFloat
        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.sage))
        }
    }

    /// A kind's page: its line, then the rest.
    private struct KindPage: View {
        let kind: Kind
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        KindSymbol(symbol: kind.symbol, size: 40)
                        Text(kind.title).font(.system(size: 30, weight: .light, design: .rounded))
                    }
                    Text(kind.line).font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(kind.more).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    GivingGuideSheet.footer(.leading).padding(.top, 10)
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// After a charity's page closes (owner: a small sheet with the charity's name; yes → the log).
private struct DidYouDonateSheet: View {
    let charity: SadaqahCharity
    let onYes: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: charity.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.sage))
            VStack(spacing: 4) {
                Text("Did you donate to").font(.subheadline).foregroundStyle(.secondary)
                Text(charity.name)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)   // long names wrap, never "Develo…" (owner)
            }
            .padding(.horizontal, 24)
            Button(action: onYes) {
                Text("Yes, log it")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .frame(width: 240, height: 50)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Button("Not this time") { dismiss() }
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .fontDesign(.rounded)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }
}

/// A typed amount: digits and one decimal point, at most two places and seven whole digits (owner: "$10.888888").
enum AmountInput {
    private static var separator: String { Locale.current.decimalSeparator ?? "." }

    static func clean(_ text: String) -> String {
        var whole = "", fraction = "", seenPoint = false
        for ch in text {
            if ch.isNumber {
                if seenPoint { if fraction.count < 2 { fraction.append(ch) } }
                else if whole.count < 7 { whole.append(ch) }
            } else if (ch == "." || ch == ",") && !seenPoint {
                seenPoint = true
            }
        }
        if whole.count > 1, whole.hasPrefix("0") { whole = String(whole.drop(while: { $0 == "0" })); if whole.isEmpty { whole = "0" } }
        if seenPoint { return (whole.isEmpty ? "0" : whole) + separator + fraction }
        return whole
    }

    static func value(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: separator, with: ".")) ?? 0
    }

    static func text(for value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: ".", with: separator)
    }
}

// MARK: - Safari

/// The charity's page in Safari's own screen, presented by UIKit over whatever is on top — inside a SwiftUI sheet, its
/// Done dismissed the sheets under it too. Done calls `onDone`, so the question comes up as soon as it closes.
enum SadaqahSafari {
    private static var delegate: Delegate?

    static func open(_ url: URL, onDone: @escaping () -> Void) {
        guard var top = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        while let next = top.presentedViewController { top = next }
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor.systemGreen
        controller.dismissButtonStyle = .done
        controller.modalPresentationStyle = .fullScreen   // only Done closes it, so `onDone` always runs
        let d = Delegate(onDone: onDone)
        delegate = d
        controller.delegate = d
        top.present(controller, animated: true)
    }

    private final class Delegate: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone()
            SadaqahSafari.delegate = nil
        }
    }
}
