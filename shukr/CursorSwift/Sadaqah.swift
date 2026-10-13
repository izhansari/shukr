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
    /// Its ⓘ sheet: a few sentences on the work, then the facts behind listing it (registration, rating, where).
    /// The kinds of work it does (a charity can be in several; the page's filter).
    var categories: Set<SadaqahCategory> = []
    var about: String = ""
    var facts: [SadaqahFact] = []
}

/// One line of a charity's ⓘ sheet.
struct SadaqahFact: Hashable {
    let symbol: String
    let text: String
}

/// The page's filter: All, or one kind of work (owner: grouped once the list grows).
enum SadaqahCategory: String, CaseIterable, Identifiable {
    case atHome, relief, orphans, water
    var id: String { rawValue }
    var title: String {
        switch self {
        case .atHome: "In the US"
        case .relief: "Emergency relief"
        case .orphans: "Orphans"
        case .water: "Water"
        }
    }
    var symbol: String {
        switch self {
        case .atHome: "house.fill"
        case .relief: "cross.case.fill"
        case .orphans: "figure.and.child.holdinghands"
        case .water: "drop.fill"
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
    private static func rated(_ score: Int) -> SadaqahFact {
        SadaqahFact(symbol: "star", text: "Charity Navigator: \(score) / 100, four stars (Oct 2026)")
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
                       categories: [.atHome, .relief],
                       about: "Helps people in the US: food pantries, women's shelters, family services and disaster relief across the US.",
                       facts: [nonprofit("04-3810161"), rated(93), works("Works across the US")]),
        SadaqahCharity(id: "iman", name: "IMAN", does: "Health, wellness and community in Chicago",
                       symbol: "building.2.fill", url: URL(string: "https://imancentral.org/donate/")!,
                       categories: [.atHome],
                       about: "The Inner-City Muslim Action Network: a free health center, housing, job training and the arts on Chicago's South Side.",
                       facts: [nonprofit("36-4167433"), rated(94), works("Works in Chicago")]),
        SadaqahCharity(id: "mlfa", name: "Muslim Legal Fund of America", does: "Legal defense for Muslims in the US",
                       symbol: "building.columns.fill", url: URL(string: "https://mlfa.org/donate")!,
                       categories: [.atHome],
                       about: "Pays for lawyers in cases where Muslims in America face injustice: civil rights, discrimination and religious freedom.",
                       facts: [nonprofit("01-0548371"), rated(92), works("Works across the US")]),
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
    case sadaqah, zakat, ramadan, relief, orphans, masjid, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sadaqah: "Sadaqah"
        case .zakat: "Zakat"
        case .ramadan: "Ramadan"
        case .relief: "Emergency relief"
        case .orphans: "Orphans"
        case .masjid: "Masjid"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .sadaqah: "heart.fill"
        case .zakat: "scalemass.fill"
        case .ramadan: "moon.stars.fill"
        case .relief: "cross.case.fill"
        case .orphans: "figure.and.child.holdinghands"
        case .masjid: "building.columns.fill"
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

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder.sadaqah.decode([SadaqahDonation].self, from: data) {
            donations = list.sorted { $0.date > $1.date }
        }
    }

    func save(_ donation: SadaqahDonation) {
        if let i = donations.firstIndex(where: { $0.id == donation.id }) { donations[i] = donation } else { donations.append(donation) }
        donations.sort { $0.date > $1.date }
        write()
    }

    func delete(_ donation: SadaqahDonation) {
        donations.removeAll { $0.id == donation.id }
        write()
    }

    private func write() {
        guard let data = try? JSONEncoder.sadaqah.encode(donations) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// The total given in `currency` since `start` (other currencies are left out of a total, not converted).
    func total(since start: Date? = nil, purpose: SadaqahPurpose? = nil) -> Double {
        donations.filter { d in
            d.currency == Self.currency
                && (start.map { d.date >= $0 } ?? true)
                && (purpose.map { d.purpose == $0 } ?? true)
        }
        .reduce(0) { $0 + $1.amount }
    }

    /// The log as a spreadsheet (date, to, for, amount, currency, note).
    func csv() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        func cell(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = donations.map { d in
            [f.string(from: d.date), cell(d.to), d.purpose.title, String(format: "%.2f", d.amount), d.currency, cell(d.note)]
                .joined(separator: ",")
        }
        return (["Date,To,For,Amount,Currency,Note"] + rows).joined(separator: "\n")
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
            }
            Section {
                ForEach(SadaqahCharities.all.filter { c in category.map { c.categories.contains($0) } ?? true }) { charity in
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
                    Text("Organizations")
                    Spacer()
                    CategoryFilter(selection: $category).textCase(nil)
                }
            } footer: {
                Text("Tap ⓘ to see who they are and why they're here. Each opens on the charity's own website; shukr takes nothing and never sees your payment.")
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
                Text("Private: kept on this phone only. Gave somewhere else? Log it with +.")
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

    /// The charity's own page; closing it always asks (owner).
    private func give(to charity: SadaqahCharity) {
        SadaqahSafari.open(charity.url) { asking = charity }
    }

    /// The soft grey of the log sheet's cards.
    static let card = Color.primary.opacity(0.045)

    /// The page's title, then this year's total big, as the log sheet shows an amount; the count and Ramadan / Zakat under it.
    private var totals: some View {
        let year = log.total(since: startOfYear)
        let count = log.donations.filter { $0.date >= startOfYear }.count
        let zakat = log.total(since: startOfYear, purpose: .zakat)
        let ramadan = log.total(since: startOfYear, purpose: .ramadan)
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
                Text(count == 0 ? "Given this year" : "Given this year · " + detailLine(count: count, zakat: zakat, ramadan: ramadan))
                    .multilineTextAlignment(.center)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func detailLine(count: Int, zakat: Double, ramadan: Double) -> String {
        guard count > 0 else { return "Nothing logged yet this year" }
        var parts = [count == 1 ? "1 donation" : "\(count) donations"]
        if zakat > 0 { parts.append("Zakat \(zakat.money())") }
        if ramadan > 0 { parts.append("Ramadan \(ramadan.money())") }
        return parts.joined(separator: " · ")
    }
}

/// The filter, beside "Organizations" (owner), in Azkar's sort-button look: the plain glyph on All; a green tinted pill
/// with the category's symbol and name while one is picked.
private struct CategoryFilter: View {
    @Binding var selection: SadaqahCategory?
    var body: some View {
        Menu {
            Picker("Show", selection: Binding(get: { selection }, set: { new in
                withAnimation(.snappy(duration: 0.25)) { selection = new }
            })) {
                Label("All", systemImage: "square.grid.2x2").tag(SadaqahCategory?.none)
                ForEach(SadaqahCategory.allCases) { c in
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
            Image(systemName: donation.purpose.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sage)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.sage.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(donation.to).lineLimit(1)
                Text("\(donation.purpose.title) · \(donation.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(donation.amount.money(donation.currency)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - History

struct SadaqahHistoryPage: View {
    @State private var log = SadaqahLog.shared
    @State private var editing: DonationDraft?
    @State private var asking: SadaqahDonation?

    /// The donations by month, newest first.
    private var months: [(title: String, items: [SadaqahDonation])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: log.donations) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { start in
            (start.formatted(.dateTime.month(.wide).year()), groups[start] ?? [])
        }
    }

    var body: some View {
        List {
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
                        Text(month.items.filter { $0.currency == SadaqahLog.currency }.reduce(0) { $0 + $1.amount }.money())
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle("Your donations")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .overlay {
            if log.donations.isEmpty {
                ContentUnavailableView("No donations yet", systemImage: "gift", description: Text("Tap + to log one."))
            }
        }
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
        .alert("Delete this donation?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { d in
            Button("Delete", role: .destructive) { log.delete(d) }
            Button("Cancel", role: .cancel) {}
        } message: { d in
            Text("\(d.amount.money(d.currency)) to \(d.to)")
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
                                   purpose: .sadaqah, note: "", date: .now)
        askedAfterVisit = true
    }
    init(manual: Void) {
        donation = SadaqahDonation(to: "", charityID: nil, amount: 0, currency: SadaqahLog.currency,
                                   purpose: .sadaqah, note: "", date: .now)
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
                            DatePicker("", selection: $date, in: ...Date.now).labelsHidden()
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
                    .background(Circle().fill(Color.primary.opacity(0.06)))
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
                ForEach(SadaqahPurpose.allCases) { p in Label(p.title, systemImage: p.symbol).tag(p) }
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
            Text(label).foregroundStyle(.primary)
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
