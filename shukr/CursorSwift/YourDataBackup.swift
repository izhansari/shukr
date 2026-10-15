import Foundation
import SwiftData
import Compression

// Your Data's copy and its restore (owner, 2026-10-14: "allow it to also accept importing of data if they ever want to
// restore from a backup"). The copy is a .zip: spreadsheets for people (CSV) + shukr-backup.json for shukr (every field,
// with ids) + photos/ and azkar-media/. A restore only ADDS what this iPhone is missing — nothing here is changed or
// removed (a prayer left unmarked here takes the copy's mark) — so restoring twice, or onto a phone in use, is safe.
// No schema change: everything goes through the models' own fields.

/// shukr-backup.json. `format` goes up only if a field changes meaning; new optional fields don't need it.
struct ShukrBackup: Codable {
    var format = 1
    var made = Date()
    var app = ""
    var prayers: [Prayer] = []
    var dayScores: [DayScore] = []
    var azkar: [Zikr] = []
    var goals: [Goal] = []
    var sessions: [Session] = []
    var donations: [SadaqahDonation] = []
    var excused: [ExcusedRange] = []
    // Added after the first copies (optional, so those still open): the audit of everything shukr keeps (2026-10-14).
    /// The 99 Names marked "knew it" (their ids, 0 = Allah).
    var namesKnown: [Int]? = nil
    /// Prayer photos with a heart (their keys).
    var photoFavorites: [String]? = nil
    var favoriteMosques: [FavoriteMosque]? = nil
    /// Mosques not to recommend (MosqueHiding's ids: name|lat|lon).
    var hiddenMosques: [String]? = nil
    var bests: Bests? = nil
    /// The settings as words, for the record (a restore never changes this iPhone's settings).
    var settings: [String: String]? = nil

    struct Prayer: Codable {
        var id: UUID, name: String, dateAtMake: Date, startTime: Date, endTime: Date
        var isCompleted: Bool, timeAtComplete: Date?, numberScore: Double?, englishScore: String?
        var lat: Double?, lon: Double?, mosqueName: String?
        var recordedTimeAtComplete: Date?, recordedLat: Double?, recordedLon: Double?, dayKey: String?
    }
    struct DayScore: Codable { var date: Date, averageScore: Double? }
    /// The best streaks as kept (they're recounted from the rows too, but a record can outlive its rows).
    struct Bests: Codable { var dayStreak: Int, dayStreakDate: Date?, inTimeStreak: Int }
    struct Zikr: Codable {
        var id: UUID, name: String, fullText: String, notes: String, quickAddStep: Int, createdAt: Date, builtInID: String?
        /// Paths inside the copy (azkar-media/…).
        var photo: String?, memo: String?
    }
    struct Goal: Codable {
        var id: UUID, zikrID: UUID?, mantraName: String, customName: String?, isCountMode: Bool, goal: Int, sortOrder: Int
        var pausedAt: Date?, reminderKind: String?, reminderTimeMinutes: Int?, reminderPrayer: String?
        var reminderOffsetMinutes: Int?, reminderWeekdays: Int?
    }
    struct Session: Codable {
        var id: UUID, title: String, sessionMode: Int, targetMin: Int, targetCount: Int, totalCount: Int, startTime: Date
        var secondsPassed: Double, avgTimePerClick: Double, tasbeehRate: String, goalID: UUID?, zikrID: UUID?
        var endedAsleep: Bool
    }

    static let fileName = "shukr-backup.json"
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

extension DataExport {
    /// Everything for shukr-backup.json, and the azkar media it points at (main actor: SwiftData's objects).
    @MainActor static func backup(_ context: ModelContext, media: Bool) -> (ShukrBackup, [(name: String, data: Data)]) {
        var b = ShukrBackup()
        b.app = BuildInfo.line
        b.prayers = ((try? context.fetch(FetchDescriptor<PrayerModel>())) ?? []).map { p in
            .init(id: p.id, name: p.name, dateAtMake: p.dateAtMake, startTime: p.startTime, endTime: p.endTime,
                  isCompleted: p.isCompleted, timeAtComplete: p.timeAtComplete, numberScore: p.numberScore,
                  englishScore: p.englishScore, lat: p.latPrayedAt, lon: p.longPrayedAt, mosqueName: p.mosqueName,
                  recordedTimeAtComplete: p.recordedTimeAtComplete, recordedLat: p.recordedLat, recordedLon: p.recordedLon,
                  dayKey: p.prayerDayKey)
        }
        b.dayScores = ((try? context.fetch(FetchDescriptor<DailyPrayerScore>())) ?? []).map { .init(date: $0.date, averageScore: $0.averageScore) }
        var files: [(String, Data)] = []
        let names = mediaNames(context)
        b.azkar = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).map { z in
            var photo: String?, memo: String?
            if media, let data = z.imageData, let n = names[z.id] { photo = "azkar-media/\(n) photo.jpg"; files.append(("\(n) photo.jpg", data)) }
            if media, let data = z.audioData, let n = names[z.id] { memo = "azkar-media/\(n) memo.m4a"; files.append(("\(n) memo.m4a", data)) }
            return .init(id: z.id, name: z.name, fullText: z.fullText, notes: z.notes, quickAddStep: z.quickAddStep,
                         createdAt: z.createdAt, builtInID: z.builtInID, photo: photo, memo: memo)
        }
        b.goals = ((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).map { t in
            .init(id: t.id, zikrID: t.mantraRef?.id, mantraName: t.mantraName, customName: t.customName,
                  isCountMode: t.isCountMode, goal: t.goal, sortOrder: t.sortOrder, pausedAt: t.pausedAt,
                  reminderKind: t.reminderKind, reminderTimeMinutes: t.reminderTimeMinutes, reminderPrayer: t.reminderPrayer,
                  reminderOffsetMinutes: t.reminderOffsetMinutes, reminderWeekdays: t.reminderWeekdays)
        }
        b.sessions = ((try? context.fetch(FetchDescriptor<SessionDataModel>())) ?? []).map { s in
            .init(id: s.id, title: s.title, sessionMode: s.sessionMode, targetMin: s.targetMin, targetCount: s.targetCount,
                  totalCount: s.totalCount, startTime: s.startTime, secondsPassed: s.secondsPassed,
                  avgTimePerClick: s.avgTimePerClick, tasbeehRate: s.tasbeehRate, goalID: s.task?.id, zikrID: s.mantra?.id,
                  endedAsleep: s.endedAsleep)
        }
        b.donations = SadaqahLog.shared.donations
        b.excused = Excused.ranges
        b.namesKnown = KnownNames.decode(UserDefaults.standard.string(forKey: KnownNames.key) ?? "").sorted()
        b.photoFavorites = PrayerPhotoFavorites.shared.keys.sorted()
        b.favoriteMosques = MosqueFavorites.all
        b.hiddenMosques = (UserDefaults.standard.stringArray(forKey: MosqueHiding.key) ?? []).sorted()
        let d = UserDefaults.standard
        let bestOn = d.double(forKey: "dateOfMaxPrayerStreak")
        b.bests = .init(dayStreak: d.integer(forKey: "maxPrayerStreak"), dayStreakDate: bestOn > 0 ? Date(timeIntervalSince1970: bestOn) : nil,
                        inTimeStreak: d.integer(forKey: "maxOnTimeStreak"))
        b.settings = Dictionary(DataSettings.rows(), uniquingKeysWith: { a, _ in a })
        return (b, files)
    }

    /// A file name per zikr with media, after its name (two with one name get " 2").
    @MainActor private static func mediaNames(_ context: ModelContext) -> [UUID: String] {
        var out: [UUID: String] = [:]
        var used = Set<String>()
        for z in (try? context.fetch(FetchDescriptor<MantraModel>())) ?? [] where z.imageData != nil || z.audioData != nil {
            var base = safeName(z.name), n = 2
            while used.contains(base) { base = safeName(z.name) + " \(n)"; n += 1 }
            used.insert(base)
            out[z.id] = base
        }
        return out
    }
}

// MARK: - Restore

/// A copy picked in Files: a .zip, the folder Files unzips it into, or shukr-backup.json alone (no photos then).
struct BackupSource {
    let backup: ShukrBackup
    /// A file of the copy by its path inside it ("photos/…", "azkar-media/…").
    let file: (String) -> Data?
    /// Prayer photos (and their notes) in the copy, by file name.
    let photoNames: [String]

    enum Problem: Error { case notACopy, unreadable }

    static func open(_ url: URL) throws -> BackupSource {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return try folder(url) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw Problem.unreadable }
        if url.pathExtension.lowercased() == "json" {
            guard let b = try? ShukrBackup.decoder.decode(ShukrBackup.self, from: data) else { throw Problem.notACopy }
            return BackupSource(backup: b, file: { _ in nil }, photoNames: [])
        }
        guard let zip = MiniZip(data) else { throw Problem.notACopy }
        // The copy's files sit in one top folder ("shukr data 2026-10-14/…"): found by where the json is.
        guard let jsonPath = zip.names.first(where: { $0.hasSuffix(ShukrBackup.fileName) }),
              let json = zip.data(jsonPath),
              let b = try? ShukrBackup.decoder.decode(ShukrBackup.self, from: json) else { throw Problem.notACopy }
        let root = String(jsonPath.dropLast(ShukrBackup.fileName.count))
        let photos = zip.names.filter { $0.hasPrefix(root + "photos/") && !$0.hasSuffix("/") }
            .map { String($0.dropFirst((root + "photos/").count)) }.filter { !$0.contains("/") && !$0.hasPrefix(".") }
        return BackupSource(backup: b, file: { zip.data(root + $0) }, photoNames: photos)
    }

    /// The unzipped folder (security-scoped: everything is read now, while it's open).
    private static func folder(_ url: URL) throws -> BackupSource {
        let fm = FileManager.default
        var root = url
        if !fm.fileExists(atPath: root.appending(path: ShukrBackup.fileName).path),
           let inner = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
               .first(where: { fm.fileExists(atPath: $0.appending(path: ShukrBackup.fileName).path) }) {
            root = inner
        }
        guard let json = try? Data(contentsOf: root.appending(path: ShukrBackup.fileName)),
              let b = try? ShukrBackup.decoder.decode(ShukrBackup.self, from: json) else { throw Problem.notACopy }
        var files: [String: Data] = [:]
        let photosDir = root.appending(path: "photos")
        let photos = ((try? fm.contentsOfDirectory(atPath: photosDir.path)) ?? []).filter { !$0.hasPrefix(".") }
        for name in photos { files["photos/" + name] = try? Data(contentsOf: photosDir.appending(path: name)) }
        for z in b.azkar {
            for path in [z.photo, z.memo].compactMap({ $0 }) { files[path] = try? Data(contentsOf: root.appending(path: path)) }
        }
        return BackupSource(backup: b, file: { files[$0] }, photoNames: photos)
    }
}

/// What a restore would add, worked out before anything is written (the sheet says it), then what it did.
struct RestorePlan {
    var prayers = 0, prayersMarked = 0, sessions = 0, azkar = 0, goals = 0, photos = 0, donations = 0, excused = 0
    var names = 0, photoFavorites = 0, masajid = 0, hidden = 0, bests = 0
    var total: Int {
        prayers + prayersMarked + sessions + azkar + goals + photos + donations + excused
            + names + photoFavorites + masajid + hidden + bests
    }
}

enum DataRestore {
    /// Counts only (nothing written).
    @MainActor static func plan(_ source: BackupSource, _ context: ModelContext) -> RestorePlan {
        run(source, context, write: false)
    }

    @MainActor @discardableResult
    static func apply(_ source: BackupSource, _ context: ModelContext) -> RestorePlan {
        let done = run(source, context, write: true)
        try? context.save()
        PrayerPhotoRevision.shared.bump()
        DayHistory.invalidate()
        SessionMemo.clear()
        // The Salah page re-reads the store and recounts the streaks, as after a widget's mark.
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        store?.set(true, forKey: SharedStore.widgetWroteStoreKey)
        store?.set(PrayerDay.start().timeIntervalSince1970, forKey: WidgetListMarks.markedDayKey)
        NotificationCenter.default.post(name: SharedStore.markedElsewhere, object: nil)
        return done
    }

    @MainActor private static func run(_ source: BackupSource, _ context: ModelContext, write: Bool) -> RestorePlan {
        let b = source.backup
        var plan = RestorePlan()

        // Azkar: built-ins are already here (matched by builtInID); yours by id.
        let zikrs = (try? context.fetch(FetchDescriptor<MantraModel>())) ?? []
        var zikrByID = Dictionary(zikrs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let builtIn = Dictionary(zikrs.compactMap { z in z.builtInID.map { ($0, z) } }, uniquingKeysWith: { a, _ in a })
        for z in b.azkar {
            if let id = z.builtInID, let here = builtIn[id] {
                zikrByID[z.id] = here
                // A built-in is already here; its photo / memo come back if it has none.
                if write {
                    if here.imageData == nil, let data = z.photo.flatMap(source.file) { here.imageData = data }
                    if here.audioData == nil, let data = z.memo.flatMap(source.file) { here.audioData = data }
                }
                continue
            }
            guard zikrByID[z.id] == nil else { continue }
            plan.azkar += 1
            guard write else { continue }
            let m = MantraModel(name: z.name, fullText: z.fullText, notes: z.notes)
            m.id = z.id
            m.quickAddStep = z.quickAddStep
            m.createdAt = z.createdAt
            m.builtInID = z.builtInID   // a built-in this build doesn't seed keeps its tag
            m.imageData = z.photo.flatMap(source.file)
            m.audioData = z.memo.flatMap(source.file)
            context.insert(m)
            zikrByID[z.id] = m
        }

        // Daily goals, by id; new ones go after this phone's own in the wheel.
        let tasks = (try? context.fetch(FetchDescriptor<TaskModel>())) ?? []
        var taskByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var nextOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
        for g in b.goals.sorted(by: { $0.sortOrder < $1.sortOrder }) where taskByID[g.id] == nil {
            plan.goals += 1
            guard write else { continue }
            let t = TaskModel(mantra: g.zikrID.flatMap { zikrByID[$0] }, isCountMode: g.isCountMode, goal: g.goal,
                              mantraName: g.mantraName, sortOrder: nextOrder)
            nextOrder += 1
            t.id = g.id
            t.customName = g.customName
            t.pausedAt = g.pausedAt
            t.reminderKind = g.reminderKind
            t.reminderTimeMinutes = g.reminderTimeMinutes
            t.reminderPrayer = g.reminderPrayer
            t.reminderOffsetMinutes = g.reminderOffsetMinutes
            t.reminderWeekdays = g.reminderWeekdays
            context.insert(t)
            taskByID[g.id] = t
        }

        // Sessions, by id.
        let sessionIDs = Set(((try? context.fetch(FetchDescriptor<SessionDataModel>())) ?? []).map(\.id))
        for s in b.sessions where !sessionIDs.contains(s.id) {
            plan.sessions += 1
            guard write else { continue }
            let row = SessionDataModel(title: s.title, sessionMode: s.sessionMode, targetMin: s.targetMin,
                                       targetCount: s.targetCount, totalCount: s.totalCount, startTime: s.startTime,
                                       secondsPassed: s.secondsPassed, avgTimePerClick: s.avgTimePerClick,
                                       tasbeehRate: s.tasbeehRate, task: s.goalID.flatMap { taskByID[$0] },
                                       mantra: s.zikrID.flatMap { zikrByID[$0] })
            row.id = s.id
            row.endedAsleep = s.endedAsleep
            context.insert(row)
        }

        // Prayers: one row per prayer per prayer day (CLAUDE.md); a day's prayer missing here is added, and one left
        // unmarked here takes the copy's mark. A prayer marked here is never touched.
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>())) ?? []
        var here: [String: PrayerModel] = [:]
        for r in rows {
            let key = r.dayKey + "|" + r.name
            if let kept = here[key], kept.isCompleted || !r.isCompleted { continue }
            here[key] = r
        }
        for p in b.prayers {
            let key = (p.dayKey ?? PrayerDay.key(forRow: p.name, startingAt: p.startTime)) + "|" + p.name
            if let r = here[key] {
                guard p.isCompleted, !r.isCompleted else { continue }
                plan.prayersMarked += 1
                if write { fill(r, from: p) }
                continue
            }
            plan.prayers += 1
            guard write else { continue }
            let r = PrayerModel(name: p.name, startTime: p.startTime, endTime: p.endTime, dateAtMake: p.dateAtMake)
            r.id = p.id
            if let k = p.dayKey { r.prayerDayKey = k }
            fill(r, from: p)
            context.insert(r)
            here[key] = r
        }

        // The days' scores, where this phone has none for that day.
        if write {
            let days = Set(((try? context.fetch(FetchDescriptor<DailyPrayerScore>())) ?? []).map { Calendar.current.startOfDay(for: $0.date) })
            for d in b.dayScores where !days.contains(Calendar.current.startOfDay(for: d.date)) {
                let row = DailyPrayerScore(date: d.date)
                row.averageScore = d.averageScore
                context.insert(row)
            }
        }

        // Prayer photos and their notes: files this phone doesn't have.
        let have = PrayerPhotos.files()
        for name in source.photoNames where !have.contains(name) {
            if !name.hasSuffix(".txt") { plan.photos += name.contains("-back.") ? 1 : 0 }
            guard write, let data = source.file("photos/" + name) else { continue }
            try? data.write(to: PrayerPhotos.directory.appending(path: name), options: .atomic)
        }

        // Donations, by id.
        let given = Set(SadaqahLog.shared.donations.map(\.id))
        for d in b.donations where !given.contains(d.id) {
            plan.donations += 1
            if write { SadaqahLog.shared.save(d) }
        }

        // Excused Mode: past stretches by id; one still running only if none runs here.
        var ranges = Excused.ranges
        let known = Set(ranges.map(\.id))
        for r in b.excused where !known.contains(r.id) {
            if r.end == nil && ranges.contains(where: { $0.end == nil }) { continue }
            plan.excused += 1
            ranges.append(r)
        }
        if write && plan.excused > 0 {
            // The running one stays last (Excused's rule).
            Excused.save(ranges.sorted { ($0.end == nil ? 1 : 0, $0.start) < ($1.end == nil ? 1 : 0, $1.start) })
        }

        // The lists you made: added to, never taken from.
        let d = UserDefaults.standard
        var learned = KnownNames.decode(d.string(forKey: KnownNames.key) ?? "")
        let newNames = Set(b.namesKnown ?? []).subtracting(learned)
        plan.names = newNames.count
        if write && !newNames.isEmpty { learned.formUnion(newNames); d.set(KnownNames.encode(learned), forKey: KnownNames.key) }

        let hearts = (b.photoFavorites ?? []).filter { !PrayerPhotoFavorites.shared.contains($0) }
        plan.photoFavorites = hearts.count
        if write { hearts.forEach { PrayerPhotoFavorites.shared.set($0, true) } }

        let starred = Set(MosqueFavorites.all.map(\.id))
        let newMasajid = (b.favoriteMosques ?? []).filter { !starred.contains($0.id) }
        plan.masajid = newMasajid.count
        if write && !newMasajid.isEmpty { MosqueFavorites.merge(newMasajid) }

        var hidden = Set(d.stringArray(forKey: MosqueHiding.key) ?? [])
        let newHidden = Set(b.hiddenMosques ?? []).subtracting(hidden)
        plan.hidden = newHidden.count
        if write && !newHidden.isEmpty {
            hidden.formUnion(newHidden)
            d.set(Array(hidden), forKey: MosqueHiding.key)
            NotificationCenter.default.post(name: MosqueHiding.changed, object: nil)
        }

        // A best streak that's higher in the copy.
        if let bests = b.bests {
            if bests.dayStreak > d.integer(forKey: "maxPrayerStreak") {
                plan.bests += 1
                if write {
                    d.set(bests.dayStreak, forKey: "maxPrayerStreak")
                    if let on = bests.dayStreakDate { d.set(on.timeIntervalSince1970, forKey: "dateOfMaxPrayerStreak") }
                }
            }
            if bests.inTimeStreak > d.integer(forKey: "maxOnTimeStreak") {
                plan.bests += 1
                if write { d.set(bests.inTimeStreak, forKey: "maxOnTimeStreak") }
            }
        }
        return plan
    }

    private static func fill(_ r: PrayerModel, from p: ShukrBackup.Prayer) {
        r.isCompleted = p.isCompleted
        r.timeAtComplete = p.timeAtComplete
        r.numberScore = p.numberScore
        r.englishScore = p.englishScore
        r.latPrayedAt = p.lat
        r.longPrayedAt = p.lon
        r.mosqueName = p.mosqueName
        r.recordedTimeAtComplete = p.recordedTimeAtComplete
        r.recordedLat = p.recordedLat
        r.recordedLon = p.recordedLon
    }
}

// MARK: - Reading a .zip

/// Just enough of the zip format to read shukr's own copies back (the system zips them — NSFileCoordinator
/// `.forUploading` — and iOS has no unzip API): the central directory, stored and deflated entries.
struct MiniZip {
    private struct Entry { let method: UInt16, compressed: Int, size: Int, localOffset: Int }
    private let bytes: Data
    private let entries: [String: Entry]
    var names: [String] { Array(entries.keys) }

    init?(_ data: Data) {
        bytes = data
        let n = data.count
        guard n >= 22 else { return nil }
        // The end of the central directory: its signature in the last 64 KB (a comment can follow it).
        var eocd: Int?
        var i = n - 22
        while i >= max(0, n - 65_557) {
            if Self.u32(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard let end = eocd else { return nil }
        let count = Int(Self.u16(data, end + 10))
        var at = Int(Self.u32(data, end + 16))
        var list: [String: Entry] = [:]
        for _ in 0..<count {
            guard at + 46 <= n, Self.u32(data, at) == 0x02014b50 else { return nil }
            let nameLen = Int(Self.u16(data, at + 28)), extra = Int(Self.u16(data, at + 30)), comment = Int(Self.u16(data, at + 32))
            guard at + 46 + nameLen <= n else { return nil }
            let name = String(decoding: data[data.startIndex + at + 46 ..< data.startIndex + at + 46 + nameLen], as: UTF8.self)
            list[name] = Entry(method: Self.u16(data, at + 10), compressed: Int(Self.u32(data, at + 20)),
                               size: Int(Self.u32(data, at + 24)), localOffset: Int(Self.u32(data, at + 42)))
            at += 46 + nameLen + extra + comment
        }
        entries = list
    }

    func data(_ name: String) -> Data? {
        guard let e = entries[name] else { return nil }
        let at = e.localOffset
        guard at + 30 <= bytes.count, Self.u32(bytes, at) == 0x04034b50 else { return nil }
        let start = at + 30 + Int(Self.u16(bytes, at + 26)) + Int(Self.u16(bytes, at + 28))
        guard start + e.compressed <= bytes.count else { return nil }
        let raw = bytes[bytes.startIndex + start ..< bytes.startIndex + start + e.compressed]
        switch e.method {
        case 0: return Data(raw)
        case 8:
            guard e.size > 0 else { return Data() }
            var out = Data(count: e.size)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, e.compressed, nil, COMPRESSION_ZLIB)
                }
            }
            return written == e.size ? out : nil
        default: return nil
        }
    }

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[d.startIndex + i]) | UInt16(d[d.startIndex + i + 1]) << 8
    }
    private static func u32(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(u16(d, i)) | UInt32(u16(d, i + 2)) << 16
    }
}
