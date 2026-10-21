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
    }
}
#endif
