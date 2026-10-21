import Foundation
import SwiftData

#if DEBUG
/// `-dumpPrayerStates` (DEBUG): every prayer row and its PrayerState, one tab-separated line each, to
/// Library/Caches/prayer-states.tsv, so the metrics rethink can check the app against board/scoring-rethink/engines.py
/// on the same data (build plan: "the oracle").
enum PrayerStateDump {
    static func write(_ container: ModelContainer) {
        let context = ModelContext(container)
        guard let rows = try? context.fetch(FetchDescriptor<PrayerModel>()) else { return }
        let ranges = Excused.ranges, now = Date()
        var out = "day\tname\tstart\tend\tmarked\tcompleted\tscore\tstate\n"
        for row in rows.sorted(by: { ($0.dayKey, $0.startTime) < ($1.dayKey, $1.startTime) }) {
            out += [row.dayKey, row.name, "\(row.startTime.timeIntervalSince1970)", "\(row.endTime.timeIntervalSince1970)",
                    row.timeAtComplete.map { "\($0.timeIntervalSince1970)" } ?? "", row.isCompleted ? "1" : "0",
                    row.numberScore.map { "\($0)" } ?? "", "\(row.state(excusedRanges: ranges, now: now))"].joined(separator: "\t") + "\n"
        }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "prayer-states.tsv")
        try? out.write(to: url, atomically: true, encoding: .utf8)
        print("📋 prayer states: \(rows.count) rows → \(url.path)")

        // The weeks (PrayerMetrics), for the same check.
        let log = JourneyLog.build(in: context, ranges: ranges, now: now)
        let excused = Excused.Days(ranges)
        var weeks = "start\tinTime\tmadeUp\tnotMarked\texcused\ttoCome\tnoRecordDays\tstrong\tcomplete\n"
        for w in PrayerMetrics.weeks(in: log, excused: excused, now: now) {
            weeks += ["\(PrayerNotificationID.dayKey(w.start))", "\(w.inTime)", "\(w.madeUp)", "\(w.notMarked)", "\(w.excused)",
                      "\(w.toCome)", "\(w.noRecordDays)", w.strong ? "1" : "0", w.complete ? "1" : "0"].joined(separator: "\t") + "\n"
        }
        let streak = PrayerMetrics.strongWeeks(in: log, excused: excused, now: now)
        weeks += "# strongWeeks current=\(streak.current) best=\(streak.best) usual=\(PrayerMetrics.usualWeek(in: log, excused: excused, now: now).map(String.init) ?? "nil")"
        weeks += " typical=\(PrayerMetrics.typicalWeek(in: log, excused: excused, now: now).map { "\($0.then)->\($0.now)" } ?? "nil")\n"
        let weeksURL = url.deletingLastPathComponent().appending(path: "prayer-weeks.tsv")
        try? weeks.write(to: weeksURL, atomically: true, encoding: .utf8)
        print("📋 prayer weeks → \(weeksURL.path)")
    }
}
#endif
