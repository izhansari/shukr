//
//  BuildInfo.swift
//  shukr
//
//  Which build is on the phone (owner, 2026-09-26: "some info that helps me know which code push
//  this is"). Shown small at the bottom of the hamburger menu and of Settings:
//  "2.0 (8) · Sep 26, 6:12 PM · ba98814+".
//  - The time is when the app's executable was built (its file date), so it's there for every
//    build, Xcode's included.
//  - The commit comes from the `ShukrBuildStamp` Info.plist key, filled from the
//    `SHUKR_BUILD_STAMP` build setting that the agent's device builds and scripts/testflight.sh pass
//    (short hash, "+" when there were uncommitted changes). Empty in a plain Xcode build.
//

import Foundation

enum BuildInfo {
    /// The ShukrBuildStamp ("ba98814", "ba98814+" with uncommitted changes), nil in a plain build.
    static let stamp: String? = {
        guard let s = Bundle.main.infoDictionary?["ShukrBuildStamp"] as? String, !s.isEmpty, !s.hasPrefix("$(") else { return nil }
        return s
    }()
    /// The commit this build was made from, without the "+".
    static var commit: String? { stamp.map { $0.hasSuffix("+") ? String($0.dropLast()) : $0 } }
    /// When the executable was built.
    static let builtAt: Date? = {
        guard let exe = Bundle.main.executableURL else { return nil }
        return (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }()

    static let line: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var parts = ["\(version) (\(build))"]
        if let builtAt {
            parts.append(builtAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        if let stamp { parts.append(stamp) }
        return parts.joined(separator: " · ")
    }()
}
