//
//  WatchBuildInfo.swift
//  shukrWatch
//
//  Which build is on the watch (owner, 2026-10-01: "how would i know if the watch app has the new
//  features right away"): the phone's BuildInfo line at the bottom of the watch's Settings —
//  "2.0 (14) · Oct 1, 11:16 AM · a9a32ad". The time is the executable's file date; the commit is the
//  `ShukrBuildStamp` Info.plist key (shukrWatchInfo.plist = $(SHUKR_BUILD_STAMP), which the device
//  builds and scripts/testflight.sh pass; empty in a plain Xcode build).
//

import Foundation

enum WatchBuildInfo {
    static let line: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        var parts = ["\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"]
        if let exe = Bundle.main.executableURL,
           let built = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            parts.append(built.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        if let s = info["ShukrBuildStamp"] as? String, !s.isEmpty, !s.hasPrefix("$(") { parts.append(s) }
        return parts.joined(separator: " · ")
    }()
}
