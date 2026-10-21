//
//  PrayerTimesView+Demos.swift
//  shukr
//
//  The Salah page's DEBUG launch arguments (-demoWidgetUnmarkAfter, -demoLand, the masjid check, the seeds and the
//  screenshot / check states): each was a `.task { … }` in PrayerTimesView's body, now a function the body's
//  `.task { await … }` calls — the code inside unchanged, re-indented (cleanup-map tangle 1, step 3). DEBUG only.
//

#if DEBUG
import SwiftUI
import SwiftData
import WidgetKit

extension PrayerTimesView {
    func runDemoWidgetUnmark() async {
        // `-demoWidgetUnmarkAfter <seconds>`: what a marked row's tap in the widget's times list
        // does — the request for today's first marked prayer, then the widget hand-off (combine
        // with a page's demo arg, or move about the app meanwhile).
        let after = UserDefaults.standard.double(forKey: "demoWidgetUnmarkAfter")
        guard after > 0 else { return }
        try? await Task.sleep(for: .seconds(after))
        // With `-demoPauseScreen`: only once the session is really up (it opens late).
        if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
            for _ in 0..<40 where !CircleCover.active.contains("tasbeeh") { try? await Task.sleep(for: .milliseconds(250)) }
            try? await Task.sleep(for: .seconds(1))
        }
        if let p = viewModel.todaysPrayers.first(where: \.isCompleted) {
            UserDefaults(suiteName: SharedStore.appGroup)?
                .set("\(p.name)|\(p.startTime.timeIntervalSince1970)", forKey: WidgetListMarks.unmarkKey)
            openFromWidgetFlags()
        }
    }

    func runDemoLand() async {
        // `-demoLand salah|zikr|journey|settings` (owner, 2026-10-18: "skip this whole intro and opening animation so
        // we can land straight to the salah tab or whatever page the agents need to test"): the real app on its own
        // data, nothing seeded. Being a `-demo…` arg it already skips the welcome / opening, setup and the prompts;
        // the tour only comes after a setup, and ZikrLock reads `DemoLand.page` too.
        guard let page = DemoLand.page else { return }
        switch page {
        case "zikr":
            try? await Task.sleep(for: .seconds(1))   // the pager up (sooner, the change was lost)
            sharedState.go(to: .zikr, animated: false)
        case "journey":
            try? await Task.sleep(for: .seconds(1))   // the root up: Journey's push
            JourneyPresenter.shared.open = true
        case "settings":
            try? await Task.sleep(for: .seconds(1))   // the pager up (sooner, the change was lost)
            sharedState.go(to: .settings, animated: false)
        default: break   // salah: the launch page
        }
    }

    func runDemoMasjid() async {
        // Masjid detection check: a late Friday Dhuhr at your first favourite masjid (+ one
        // 400 m away) → the first should come back as Jumu'ah, scored Early; the second not.
        if ProcessInfo.processInfo.arguments.contains("-demoMasjidCheck"), let fav = MosqueFavorites.all.first {
            let cal = Calendar.current
            var friday = cal.startOfDay(for: Date())
            while cal.component(.weekday, from: friday) != 6 { friday = cal.date(byAdding: .day, value: -1, to: friday)! }
            let start = friday.addingTimeInterval(13 * 3600), end = start.addingTimeInterval(3 * 3600)
            let atMasjid = PrayerModel(name: "Dhuhr", startTime: start, endTime: end,
                                       latitude: fav.latitude + 0.0002, longitude: fav.longitude)
            let away = PrayerModel(name: "Asr", startTime: end, endTime: end.addingTimeInterval(7200),
                                   latitude: fav.latitude + 0.004, longitude: fav.longitude)
            for p in [atMasjid, away] {
                p.isCompleted = true
                p.setPrayerScore(atDate: p.startTime.addingTimeInterval(2.5 * 3600))
                context.insert(p)
            }
            NSLog("MASJIDCHECK before: \(atMasjid.displayName) \(atMasjid.numberScore ?? -1)")
            let days = await MasjidDetector.check([atMasjid, away], in: context)
            NSLog("MASJIDCHECK after: \(atMasjid.displayName) score=\(atMasjid.numberScore ?? -1) masjid=\(atMasjid.mosqueName ?? "nil") | away masjid=\(away.mosqueName ?? "nil") rescoredDays=\(days.count)")
            context.delete(atMasjid); context.delete(away); try? context.save()
        }
        // `-demoJumuahRow <masjid>` (with circle-check's clock on a Friday): today's Dhuhr marked at that masjid, the
        // list open, and its row's masjid line (decision jumuah-name-render B).
        if let masjid = UserDefaults.standard.string(forKey: "demoJumuahRow") {
            try? await Task.sleep(for: .seconds(2))
            guard let dhuhr = viewModel.todaysPrayers.first(where: { $0.name == "Dhuhr" }) else { return }
            dhuhr.mosqueName = masjid
            if !dhuhr.isCompleted {
                dhuhr.isCompleted = true
                dhuhr.timeAtComplete = dhuhr.startTime.addingTimeInterval(20 * 60)
            }
            try? context.save()
            sharedState.navPosition = .bottom
            PrayerListFold.shared.showDone = true
            try? await Task.sleep(for: .seconds(3))
            NotificationCenter.default.post(name: PrayerButton.demoMasjidLine, object: nil)
        }
        // What a Zikr-widget row tap does, without the widget: Zikr page, last task centred.
        if ProcessInfo.processInfo.arguments.contains("-demoZikrFocus") {
            try? await Task.sleep(for: .seconds(1.5))
            let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
            if let last = tasks.last {
                sharedState.horizontalPage = .zikr
                ZikrFocus.request(last.id.uuidString)
            }
        }
    }

    func runDemoSeeds() async {
        // Simulator check of the completion moment: launch with -demoPrayerCompletion. Uses
        // the dev "test prayer times" (minutes around now), opens the salah sheet, then
        // marks the current prayer and a missed one.
        if ProcessInfo.processInfo.arguments.contains("-demoPinRender") { await PickPinRender.run() }
        if ProcessInfo.processInfo.arguments.contains("-demoTasbeehRing") {
            // Writes the tasbeeh progress ring at 65 % to <app data>/tmp/tasbeeh-ring.png.
            let renderer = ImageRenderer(content: NeuCircularProgressView(progress: 0.65).padding(40).background(Color(.systemBackground)))
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "tasbeeh-ring.png"))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoShareCard") {
            // Writes today's ayah share card to <app data>/tmp/share-card.png.
            let vm = DailyAyahViewModel()
            try? await Task.sleep(for: .seconds(1))
            if let ayah = vm.currentAyah {
                let name = vm.surahs.first(where: { $0.number == ayah.surah })?.englishName ?? "Surah \(ayah.surah)"
                let card = AyahShareCard(arabic: ayah.arabic, english: ayah.english, translator: ayah.translator,
                                         reference: "\(name) · \(ayah.surah):\(ayah.ayah)")
                var lightGrain = card; lightGrain.style = .grain; lightGrain.darkBase = false
                if let data = lightGrain.render()?.pngData() {
                    try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "share-card-grain-light.png"))
                }
                for style in AyahShareStyle.allCases {
                    var styled = card; styled.style = style
                    if let data = styled.render()?.pngData() {
                        try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "share-card-\(style.rawValue).png"))
                    }
                }

            }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoMosques") || UserDefaults.standard.string(forKey: "demoMapLayer") != nil {
            try? await Task.sleep(for: .seconds(2.5))
            showQiblaMap = true   // the real map (the circle's arrow); mosque mode / `-demoMapLayer` from there
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoZikrMedia") {
            // Alhamdulillah with a sample photo + memo; its page opens unless `-demoPauseScreen`
            // (then the pause card shows them). `-demoZikrPane memo|photo` picks the tab.
            try? await Task.sleep(for: .seconds(1))
            let m = ZikrMediaDemo.seed(in: context)
            if !ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") { demoMantra = m; return }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoNewZikr") {
            // A new zikr's card: editing, every box empty (its placeholders).
            try? await Task.sleep(for: .seconds(1))
            demoNewZikr = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoZikrEmpty") {
            // A zikr's page by name (`-demoZikrName <name>`, default Astaghfirullah — no photo / memo).
            try? await Task.sleep(for: .seconds(1))
            let name = UserDefaults.standard.string(forKey: "demoZikrName") ?? "Astaghfirullah"
            if let m = MantraModel.find(named: name, in: context) { demoMantra = m; return }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoExplore") { demoExplore = true }
        Excused.applyDebugArgs()   // -demoExcused N / -demoExcusedOff
        if ProcessInfo.processInfo.arguments.contains("-demoSadaqah") { demoSadaqah = true }
        // `-yourDataExportNow`: Your Data's copy made at launch into tmp/YourData (pull it with devicectl: the store
        // itself sits outside what devicectl may copy). Nothing else changes.
        if ProcessInfo.processInfo.arguments.contains("-yourDataExportNow") {
            let url = await DataExport.makeCopy(context)
            print("📦 Your Data copy:", url?.path ?? "failed")
        }
        if ProcessInfo.processInfo.arguments.contains("-demoScheduledNotifications") {
            try? await Task.sleep(for: .seconds(1.5))
            demoScheduled = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoWhatsNew") {
            // The What's new page; `-demoWhatsNewTopic <id>` opens that card's detail.
            try? await Task.sleep(for: .seconds(1))
            demoWhatsNew = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoMantraPage") {
            try? await Task.sleep(for: .seconds(1))
            showMantrasPage = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoHealthThenCompass") {
            // With `-healthPretend off`: once the reminders card is up, a Qibla widget tap
            // arrives (the flag + the activation path) — the card must close and the map open.
            for _ in 0..<40 where !healthCardAppeared { try? await Task.sleep(for: .milliseconds(250)) }
            print("HEALTHTEST card up=\(healthCardAppeared)")
            try? await Task.sleep(for: .seconds(1))
            UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetCompass")
            openFromWidgetFlags()
            try? await Task.sleep(for: .seconds(2.5))
            print("HEALTHTEST after: card=\(healthCard != nil) map=\(showQiblaMap) canLand=\(WelcomeTarget.canLand)")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoZikrHistory") {
            // `-demoHistorySeed`: this month's days with sessions of different lengths (the month ring's heat map).
            if ProcessInfo.processInfo.arguments.contains("-demoHistorySeed"),
               ((try? context.fetchCount(FetchDescriptor<SessionDataModel>())) ?? 0) == 0 {
                let today = PrayerDay.start(), day = Calendar.current.component(.day, from: today)
                let minutes = [3, 0, 12, 1, 6, 0, 25, 2, 9, 0, 4, 15, 0, 7, 1, 18, 5, 0, 11, 2, 8, 0, 3, 20, 6, 0, 10, 4, 1, 14, 2]
                for d in 0..<day where minutes[d % minutes.count] > 0 {
                    guard let start = Calendar.current.date(byAdding: .day, value: d - (day - 1), to: today)?
                        .addingTimeInterval(10 * 3600) else { continue }
                    let secs = Double(minutes[d % minutes.count] * 60)
                    context.insert(SessionDataModel(title: "Subhanallah", sessionMode: 0, targetMin: 0, targetCount: 0,
                                                    totalCount: Int(secs / 1.5), startTime: start, secondsPassed: secs,
                                                    avgTimePerClick: 1.5, tasbeehRate: "1.5s",
                                                    mantra: MantraModel.find(named: "Subhanallah", in: context)))
                }
                try? context.save()
            }
            try? await Task.sleep(for: .seconds(1))
            showZikrHistory = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoDailyAyah") {
            // The Daily Ayah page (+ `-demoAyahUnrevealed`, `-demoAyahReveal`; screenshots).
            try? await Task.sleep(for: .seconds(1))
            showDailyAyahPage = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoSettings") {
            try? await Task.sleep(for: .seconds(1.5))   // once the pager is up
            SettingsPresenter.shared.show()   // Settings (screenshots)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartPreview") {
            // What Settings → My Dev Stuff → Preview prayer begins does (from Settings).
            SettingsPresenter.shared.show()
            try? await Task.sleep(for: .seconds(2))
            NotificationCenter.default.post(name: PrayerStartPreview.request, object: nil)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoManyTasks") {
            // Six zikr tasks, one with a very long name (the Zikr widget's rows; simulator).
            try? await Task.sleep(for: .seconds(1))
            let existing = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
            if existing < 6 {
                let names = [("Alhamdulillah", "After Fajr, before the morning walk to the masjid"), ("Astaghfirullah", ""),
                             ("Subhanallah", "Evening"), ("Allahu Akbar", ""), ("Alhamdulillah", "Before bed"),
                             ("Astaghfirullah", "After Isha")]
                for (i, (mantra, own)) in names.prefix(6 - existing).enumerated() {
                    let t = TaskModel(mantra: MantraModel.find(named: mantra, in: context),
                                      isCountMode: true, goal: [100, 33, 1000, 34, 50, 70][i], sortOrder: existing + i)
                    t.customName = own.isEmpty ? nil : own
                    context.insert(t)
                }
                try? context.save()
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoZikrPage") {
            // The Zikr page's circle wheel, with a few tasks if there are none (simulator).
            try? await Task.sleep(for: .seconds(1))
            if ((try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0) == 0 {
                for (i, (name, count, goal)) in [("Alhamdulillah", true, 100), ("Astaghfirullah", true, 33),
                                                 ("Subhanallah", false, 10)].enumerated() {
                    context.insert(TaskModel(mantra: MantraModel.find(named: name, in: context),
                                             isCountMode: count, goal: goal, sortOrder: i))
                }
                try? context.save()
            }
            sharedState.horizontalPage = .zikr
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPostSalah") {
            try? await Task.sleep(for: .seconds(1))
            sharedState.isDoingPostNamazZikr = true
            if SessionHandoff.shared.openInPlace() {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { showTasbeehPage = true }
            } else {
                showTasbeehPage = true
            }
            return
        }
        if UserDefaults.standard.object(forKey: "demoTasbeehCount") != nil {
            // A freestyle session for `-demoTasbeehCount` (tasbeehView counts it); `-demoTasbeehTarget N`: a count goal
            // of N instead, so the ring fills (the battery check).
            try? await Task.sleep(for: .seconds(1))
            let target = UserDefaults.standard.integer(forKey: "demoTasbeehTarget")
            sharedState.selectedMode = target > 0 ? 2 : 0
            if target > 0 { sharedState.targetCount = String(target) }
            showTasbeehPage = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
            // A 33-count Alhamdulillah session, paused (tasbeehView counts and pauses it).
            // `-demoPauseZikr <name>` counts another zikr (e.g. one with a slower usual pace).
            try? await Task.sleep(for: .seconds(1))
            // `-demoLongZikr`: a zikr with a long card (the built-ins' texts, several times over, and a long note —
            // nothing typed from memory), to see how the pause screen holds it.
            if ProcessInfo.processInfo.arguments.contains("-demoLongZikr") {
                let longName = UserDefaults.standard.string(forKey: "demoLongZikrName") ?? "Long morning azkar"
                if MantraModel.find(named: longName, in: context) == nil {
                    let builtIns = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? [])
                        .filter { $0.builtInID != nil && !$0.fullText.isEmpty }
                    let body = Array(repeating: builtIns.map(\.fullText).joined(separator: "\n"), count: 3)
                        .joined(separator: "\n")
                    let m = MantraModel(name: longName, fullText: body,
                                        notes: "Said each morning after Fajr, slowly, one line at a time. My teacher asked me to keep it short on busy days, but to read every line on the weekend and to think about what each one means before moving on to the next.")
                    context.insert(m)
                    try? context.save()
                }
                // With `-demoZikrMedia` too: the same sample memo and photo as Alhamdulillah's.
                if ProcessInfo.processInfo.arguments.contains("-demoZikrMedia"),
                   let source = ZikrMediaDemo.seed(in: context),
                   let long = MantraModel.find(named: longName, in: context) {
                    long.imageData = source.imageData
                    long.audioData = source.audioData
                    try? context.save()
                }
                UserDefaults.standard.set(longName, forKey: "demoPauseZikr")
            }
            let zikrName = UserDefaults.standard.string(forKey: "demoPauseZikr") ?? "Alhamdulillah"
            if let mantra = MantraModel.find(named: zikrName, in: context) {
                if mantra.fullText.isEmpty && zikrName == "Alhamdulillah" {
                    mantra.fullText = "الْحَمْدُ لِلَّهِ\nAl-ḥamdu lillāh — all praise is for Allah"
                    mantra.notes = "Read after every salah, 33 times."
                }
                sharedState.mantraForSession = mantra
            }
            sharedState.titleForSession = zikrName
            sharedState.selectedMode = 2
            sharedState.targetCount = "33"
            showTasbeehPage = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoNames") {
            try? await Task.sleep(for: .seconds(1))
            showNamesPage = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoJourneyFlightRun") { return }   // its own task, below (Release too)
        if ProcessInfo.processInfo.arguments.contains("-demoInsights") || ProcessInfo.processInfo.arguments.contains("-demoJourney") {
            // Journey (`-demoJourneySeed` fills ~100 earlier days first; `-demoJourneyMonth N`, `-demoJourneyDay N`).
            #if DEBUG
            JourneySeed.seedIfAsked(context)
            #endif
            try? await Task.sleep(for: .seconds(1))
            JourneyPresenter.shared.open = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPrayerListOpen") {
            // The prayer list up (to tap its rows); with `-demoPrayerStart`, its prayers to come too.
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
            if !ProcessInfo.processInfo.arguments.contains("-demoPrayerStart") { return }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoMarkAll") {
            // Every one of today's started prayers marked, the list up: the day's page (all five once Isha is on —
            // pair with circle-check's fake clock late in the evening).
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
            // `-demoKeepCurrent YES`: all but the prayer on now (the list's looks with done, now and coming rows).
            let keepCurrent = UserDefaults.standard.bool(forKey: "demoKeepCurrent")
            // `-demoMarkMixed`: each marked at its own point in its window (Fajr after it = Qaza, Asr late, the rest
            // early or on time) — a day page with mixed grades. Pair with a fake clock after Isha starts.
            let mixed = ProcessInfo.processInfo.arguments.contains("-demoMarkMixed")
            let at: [String: Double] = ["Fajr": 1.4, "Dhuhr": 0.25, "Asr": 0.7, "Maghrib": 0.1, "Isha": 0.12]
            for prayer in viewModel.todaysPrayers where !prayer.isCompleted && prayer.startTime <= Date()
                && !(keepCurrent && prayer.endTime > Date()) {
                try? await Task.sleep(for: .seconds(0.6))
                if mixed, let f = at[prayer.name] {
                    let span = prayer.endTime.timeIntervalSince(prayer.startTime)
                    let when = prayer.startTime.addingTimeInterval(f > 1 ? span + 40 * 60 : span * f)
                    viewModel.markFromJourney(prayer, at: min(when, Date().addingTimeInterval(-60)))
                } else {
                    viewModel.togglePrayerCompletion(for: prayer)
                }
            }
            // `-demoShowDone YES`: the "N done" fold open, so the done rows show too.
            if UserDefaults.standard.bool(forKey: "demoShowDone") {
                try? await Task.sleep(for: .seconds(1.5))
                PrayerListFold.shared.showDone = true
            }
            // `-demoDayFacts`: the day page's back has something of everything — notes on Fajr, Asr and Maghrib (the
            // owner's picture), places on Dhuhr, Asr and Maghrib, one zikr session today.
            if ProcessInfo.processInfo.arguments.contains("-demoDayFacts") {
                let notes = ["Fajr": "so tireddddddd but thankful",
                             "Asr": "asr on top of the mountain today and it was really nice i enjoyed praying with beautiful views sA",
                             "Maghrib": "love praying maghrib early. especially because its one of the prayers with a short window and towards the night as a wind down i love it."]
                for prayer in viewModel.todaysPrayers where prayer.isCompleted {
                    // `-demoLongNotes`: each note six times over (the notes card's scrolling).
                    let long = ProcessInfo.processInfo.arguments.contains("-demoLongNotes")
                    if let text = notes[prayer.name] {
                        PrayerPhotos.setNote(PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name),
                                             long ? Array(repeating: text, count: 6).joined(separator: " ") : text)
                    }
                    if ["Dhuhr", "Asr", "Maghrib"].contains(prayer.name), prayer.latPrayedAt == nil {
                        prayer.latPrayedAt = 35.79 + (prayer.name == "Asr" ? 0.02 : 0)
                        prayer.longPrayedAt = -78.78 - (prayer.name == "Maghrib" ? 0.03 : 0)
                    }
                }
                // One session today, not one more per launch.
                let dayStart = PrayerDay.start()
                let today = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
                if today.isEmpty, let zikr = try? context.fetch(FetchDescriptor<MantraModel>()).first {
                    let session = SessionDataModel(title: zikr.name, sessionMode: 0, targetMin: 0, targetCount: 0, totalCount: 33,
                                                   startTime: Date().addingTimeInterval(-3600), secondsPassed: 70,
                                                   avgTimePerClick: 2.1, tasbeehRate: "", mantra: zikr)
                    context.insert(session)
                }
                try? context.save()
                NotificationCenter.default.post(name: .journeyChanged, object: nil)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoDayMilestones") {
            // Streak (fake 12) in the top bar, perfect day in the list.
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
            try? await Task.sleep(for: .seconds(1.5))
            NotificationCenter.default.post(name: .prayerStreakContinued, object: 12)
            NotificationCenter.default.post(name: .perfectDay, object: true)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPrayerStart") {
            // A prayer comes into its window 6 s after launch (simulator only): test prayer
            // times, then Asr's window closed and Maghrib moved to start in 6 s.
            try? await Task.sleep(for: .seconds(1))
            // The loaded prayer day's rows, moved in memory (works at any hour; test prayer
            // times fell outside the day after midnight).
            let now = Date()
            // `-demoPrayerStartPrayer Fajr` picks which prayer starts (default Maghrib); Fajr
            // starts from the day-summary circle.
            let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
            let target = order.firstIndex(of: UserDefaults.standard.string(forKey: "demoPrayerStartPrayer") ?? "Maghrib") ?? 3
            for p in viewModel.todaysPrayers {
                p.isCompleted = false
                let i = order.firstIndex(of: p.name) ?? 0
                if i < target { p.startTime = now.addingTimeInterval(-3600); p.endTime = now.addingTimeInterval(-60); p.isCompleted = true }
                // `-demoPrayerStartAgo <s>`: already that far into its window instead of starting in 6 s.
                else if i == target {
                    let ago = UserDefaults.standard.double(forKey: "demoPrayerStartAgo")
                    p.startTime = now.addingTimeInterval(ago > 0 ? -ago : 6); p.endTime = p.startTime.addingTimeInterval(1800)
                }
                else { p.startTime = now.addingTimeInterval(3600 * Double(i - target)); p.endTime = p.startTime.addingTimeInterval(1800) }
            }
            viewModel.contentChanged()
            // `-demoPrayerStartThenMark`: mark it 4 s after it starts → the circle moves on to the
            // next (not started) prayer and the track shrinks back to dashed after the sweep.
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartThenMark") {
                // `-demoPrayerStartSheetOpen`: with the prayer list up (the list's path; marking
                // Isha then completes the day).
                if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartSheetOpen") {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
                    try? await Task.sleep(for: .seconds(8))
                } else {
                    try? await Task.sleep(for: .seconds(10))
                }
                if let now = viewModel.relevantPrayer, now.status() == .current {
                    viewModel.togglePrayerCompletion(for: now)
                }
                return
            }
            // `-demoPrayerStartOnZikr`: be on the Zikr page when it starts (must not play).
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartOnZikr") {
                sharedState.horizontalPage = .zikr
            }
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-demoPrayerCompletion") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        viewModel.useTestPrayers = true
        viewModel.fetchPrayerTimes(cameFrom: "demoPrayerCompletion")
        viewModel.loadTodaysPrayerObjects()
        withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
        for name in ["Asr", "Dhuhr", "Fajr"] {
            try? await Task.sleep(for: .seconds(3))
            if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }), !prayer.isCompleted {
                viewModel.togglePrayerCompletion(for: prayer)
            }
        }
    }
}
#endif
