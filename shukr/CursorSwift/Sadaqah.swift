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
    /// Why it's on the list (facts only: registration, ratings).
    let why: String
    let symbol: String
    let url: URL
}

enum SadaqahCharities {
    /// The draft list (Izhan approves it), checked 2026-10-13: each a US 501(c)(3) rated 4 stars by Charity Navigator,
    /// its own donation page. Left out: Islamic Relief USA (renamed IDEA after its split from Islamic Relief Worldwide in
    /// Sep 2026; irusa.org is gone), Mercy-USA (3 stars), and platforms (LaunchGood, MyTenNights).
    static let all: [SadaqahCharity] = [
        SadaqahCharity(id: "zakat", name: "Zakat Foundation of America", does: "Zakat, emergency relief and education worldwide",
                       why: "4 stars on Charity Navigator", symbol: "hands.and.sparkles.fill",
                       url: URL(string: "https://www.zakat.org/donate")!),
        SadaqahCharity(id: "hhrd", name: "Helping Hand for Relief and Development", does: "Disaster relief, orphans, water and health",
                       why: "4 stars on Charity Navigator", symbol: "hand.raised.fill",
                       url: URL(string: "https://www1.hhrd.org/DetailDonate")!),
        SadaqahCharity(id: "penny", name: "Penny Appeal USA", does: "Water, education and relief",
                       why: "4 stars on Charity Navigator", symbol: "drop.fill",
                       url: URL(string: "https://www.pennyappealusa.org/donate/")!),
        SadaqahCharity(id: "icna", name: "ICNA Relief USA", does: "Food pantries, shelters and disaster relief in the US",
                       why: "4 stars on Charity Navigator", symbol: "house.fill",
                       url: URL(string: "https://icnarelief.org/donate/")!),
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

    private var startOfYear: Date { Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now }

    var body: some View {
        List {
            Section {
                totals
            }
            Section {
                ForEach(SadaqahCharities.all) { charity in
                    Button {
                        // Always ask once the charity's page closes (owner).
                        SadaqahSafari.open(charity.url) { editing = DonationDraft(after: charity) }
                    } label: { CharityRow(charity: charity) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Give with confidence")
            } footer: {
                Text("US nonprofits, each rated 4 stars by Charity Navigator. Each opens on the charity's own website; shukr takes nothing and never sees your payment.")
            }
            Section {
                Button { editing = DonationDraft(manual: ()) } label: {
                    Label("Log a donation", systemImage: "plus.circle.fill").foregroundStyle(Color.sage)
                }
                ForEach(log.donations.prefix(5)) { d in
                    Button { editing = DonationDraft(editing: d) } label: { DonationRow(donation: d) }
                        .buttonStyle(.plain)
                }
                if log.donations.count > 5 {
                    NavigationLink("All donations (\(log.donations.count))") { SadaqahHistoryPage() }
                }
            } header: {
                Text("Your donations")
            } footer: {
                Text("Private: kept on this phone only. Gave somewhere else? Log it here too.")
            }
        }
        .navigationTitle("Sadaqah")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .sheet(item: $editing) { DonationSheet(draft: $0) }
    }

    /// This year's total, the count, and Ramadan / Zakat when there are any.
    private var totals: some View {
        let year = log.total(since: startOfYear)
        let count = log.donations.filter { $0.date >= startOfYear }.count
        let zakat = log.total(since: startOfYear, purpose: .zakat)
        let ramadan = log.total(since: startOfYear, purpose: .ramadan)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Given this year").font(.subheadline).foregroundStyle(.secondary)
            Text(year.money())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(detailLine(count: count, zakat: zakat, ramadan: ramadan))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func detailLine(count: Int, zakat: Double, ramadan: Double) -> String {
        guard count > 0 else { return "Nothing logged yet this year" }
        var parts = [count == 1 ? "1 donation" : "\(count) donations"]
        if zakat > 0 { parts.append("Zakat \(zakat.money())") }
        if ramadan > 0 { parts.append("Ramadan \(ramadan.money())") }
        return parts.joined(separator: " · ")
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
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(charity.why)
                }
                .font(.caption).foregroundStyle(Color.sage)
                .padding(.top, 1)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
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
                            .swipeActions { Button("Delete") { asking = d }.tint(.red) }
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
        .navigationTitle("Your donations")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: SadaqahExport(text: log.csv()), preview: SharePreview("shukr donations.csv")) {
                    Image(systemName: "square.and.arrow.up")
                }
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
    /// After a charity's page: the question form, "Not this time" instead of Cancel.
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

struct DonationSheet: View {
    let draft: DonationDraft
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var amount: Double?
    @State private var purpose: SadaqahPurpose
    @State private var note: String
    @State private var date: Date
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private static let quickAmounts: [Double] = [10, 25, 50, 100]

    init(draft: DonationDraft) {
        self.draft = draft
        _to = State(initialValue: draft.donation.to)
        _amount = State(initialValue: draft.donation.amount > 0 ? draft.donation.amount : nil)
        _purpose = State(initialValue: draft.donation.purpose)
        _note = State(initialValue: draft.donation.note)
        _date = State(initialValue: draft.donation.date)
    }

    private var canSave: Bool {
        (amount ?? 0) > 0 && !to.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var title: String {
        if draft.askedAfterVisit { return "Did you donate?" }
        return draft.isNew ? "Log a donation" : "Donation"
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.askedAfterVisit {
                    Section {
                        Text("Did you donate to \(draft.donation.to)? Log it to keep track of what you've given.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section("Amount") {
                    TextField("0", value: $amount, format: .currency(code: draft.donation.currency))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                    HStack(spacing: 8) {
                        ForEach(Self.quickAmounts, id: \.self) { value in
                            Button { amount = value } label: {
                                Text(value.money(draft.donation.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(amount == value ? Color.sage : Color.primary.opacity(0.07)))
                                    .foregroundStyle(amount == value ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("For") {
                    PurposeChips(selection: $purpose)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                Section {
                    TextField("To (a charity, masjid, fundraiser…)", text: $to)
                        .disabled(draft.askedAfterVisit)
                    DatePicker("When", selection: $date, in: ...Date.now)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if !draft.isNew {
                    Section {
                        Button("Delete Donation", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft.askedAfterVisit ? "Not this time" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .alert("Delete this donation?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { SadaqahLog.shared.delete(draft.donation); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(canSave && draft.isNew)
    }

    private func save() {
        var d = draft.donation
        d.to = to.trimmingCharacters(in: .whitespaces)
        d.amount = amount ?? 0
        d.purpose = purpose
        d.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        d.date = date
        SadaqahLog.shared.save(d)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}

/// The purposes as chips that wrap.
private struct PurposeChips: View {
    @Binding var selection: SadaqahPurpose
    var body: some View {
        ChipFlow(spacing: 8) {
            ForEach(SadaqahPurpose.allCases) { p in
                Button { selection = p } label: {
                    HStack(spacing: 5) {
                        Image(systemName: p.symbol).font(.caption)
                        Text(p.title)
                    }
                        .font(.subheadline.weight(.medium))
                        .fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(selection == p ? Color.sage : Color.primary.opacity(0.07)))
                        .foregroundStyle(selection == p ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
