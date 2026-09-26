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
    static let line: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var parts = ["\(version) (\(build))"]
        if let exe = Bundle.main.executableURL,
           let built = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            parts.append(built.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        if let stamp = info["ShukrBuildStamp"] as? String, !stamp.isEmpty, !stamp.hasPrefix("$(") {
            parts.append(stamp)
        }
        return parts.joined(separator: " · ")
    }()
}
