import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    /// The header's back chevron. Passed in rather than read from `sharedState`, so this big
    /// Form doesn't re-render on every page turn (it only ever wrote `horizontalPage`).
    var onBack: () -> Void = {}
    var refetchOnLeave = true
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    
    // The compass reads this from the app-group suite (QiblaSettings); writing it to the standard
    // suite here is why the stepper never changed anything.
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var qiblaSensitivity: Double = 3.5
    
    @AppStorage("fajrNotif") var fajrNotif: Bool = NotificationDefaults.notify("Fajr")
    @AppStorage("dhuhrNotif") var dhuhrNotif: Bool = NotificationDefaults.notify("Dhuhr")
    @AppStorage("asrNotif") var asrNotif: Bool = NotificationDefaults.notify("Asr")
    @AppStorage("maghribNotif") var maghribNotif: Bool = NotificationDefaults.notify("Maghrib")
    @AppStorage("ishaNotif") var ishaNotif: Bool = NotificationDefaults.notify("Isha")

    @AppStorage("fajrNudges") var fajrNudges: Bool = NotificationDefaults.nudges("Fajr")
    @AppStorage("dhuhrNudges") var dhuhrNudges: Bool = NotificationDefaults.nudges("Dhuhr")
    @AppStorage("asrNudges") var asrNudges: Bool = NotificationDefaults.nudges("Asr")
    @AppStorage("maghribNudges") var maghribNudges: Bool = NotificationDefaults.nudges("Maghrib")
    @AppStorage("ishaNudges") var ishaNudges: Bool = NotificationDefaults.nudges("Isha")
    
    @AppStorage("didShowAlarmSetupAlert") private var didShowAlarmSetupAlert: Bool = false
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmEnabled: Bool = false
    #if DEBUG
    @AppStorage(SalahSheetDrag.key) private var salahSheetFollows = SalahSheetDrag.defaultOn
    @AppStorage(WidgetSpeedTest.stillRingKey, store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var widgetStillRing = false
    @AppStorage(WidgetSpeedTest.fewestEntriesKey, store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var widgetFewestEntries = false
    #endif
        
//    @AppStorage("calculationMethod") var calculationMethod: Int = 2
//    @AppStorage("school") var school: Int = 0
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0

    
    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    
    
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1 //prayerstreak_flag
    @State private var isNotifPopupVisible: Bool = false
    @State private var isStreakPopupVisible: Bool = false
    
    @State private var rotationAngle: Double = 0 // For rotating the symbol
    
    // for the floating message
    @State private var showFloatingMessage = false // State to control visibility
    
    // For minimizing and expanding the devSection
    /// DEBUG: tap the "Sneak Peek" header, or launch with `-devStuff`.
    @State private var showDevStuff = ProcessInfo.processInfo.arguments.contains("-devStuff")
    /// DEBUG: the compass's sources, rate and accuracy under the Salah circle (compass audit 2026-09-30).
    @AppStorage("compassDebug") private var compassDebug = false
    @State private var showCityPicker = false
    @State private var refreshState: RefreshState = .idle
    /// When the city was last worked out (the location row's "Updated 2 min ago").
    @AppStorage("locationUpdatedAt") private var locationUpdatedAt: Double = 0
    @AppStorage("tasbeehRingStyle") private var tasbeehRingStyle = TasbeehRingStyle.fine.rawValue
    @State private var showWhatsNew = false
    @State private var showRingPlayground = false
    @State private var showNextPlayground = false
    @AppStorage(ZikrWheelStyle.key) private var zikrWheelStyle = ZikrWheelStyle.gentle.rawValue
    @AppStorage(MosqueIconStyle.key) private var mosqueIconStyle = MosqueIconStyle.finder.rawValue
    /// DEBUG / TestFlight only: Run setup again (the same gate as What's new).
    @ObservedObject private var betaAccess = WhatsNewAccess.shared
    /// What Automatic currently resolves to (re-read when the stored country changes).
    @AppStorage(AutoMethod.countryKey, store: UserDefaults(suiteName: SharedStore.appGroup)) private var autoCountry = ""
    private var automaticLabel: String {
        _ = autoCountry   // re-read when the country (and so the resolved method) changes
        return "Automatic (\(AutoMethod.shortName(AutoMethod.resolved())))"
    }
    @AppStorage(PrayerDotStyle.key) private var prayerDotStyle = PrayerDotStyle.muted.rawValue
    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true

    // For choosing the sheet's content when clicking on the sneak peek stuff
    @State private var selectedUpcomingFeature: sneakPeekItem?
    /// The sneak-peek sheet's one height (the longest description fits at the usual text size).
    private static let sneakPeekHeight: CGFloat = 320
    @State private var showFeatureSheet: Bool = false

    // Create an array of sneakPeekItems.
    let upcomingFeatures: [sneakPeekItem] = [
        sneakPeekItem(image: "lightbulb.max.fill", title: "Hadith Motivator", description: "Sometimes we lose sight of the intention behind our actions and just go through the motions. A daily Hadith page would be a cool way to stay reminded of our purpose in this dunya"),
        sneakPeekItem(image: "fork.knife", title: "Food Finder", description: "Finding food is hard. Finding halal food - even harder. I wanna partner with another organization for this iA (cough cough HalalEatsNC?!)"),
        sneakPeekItem(image: "character.book.closed", title: "Quranic Vocab", description: "Explore and learn common words from the Quran to make it easier to focus during prayer."),
        sneakPeekItem(image: "gift", title: "Sadaqah Links", description: "A list of trustworthy links to help the ummah. Ideally, Apple Pay integration and donation history in app would be nice!")
    ]
    
    // Define a model for each suggestion.
    struct sneakPeekItem: Identifiable {
        let id = UUID()
        let image: String
        let title: String
        let description: String
    }
    
    let calculationMethods = [
        (1, "University of Islamic Sciences, Karachi"), // .karachi
        (2, "Islamic Society of North America"), // .northAmerica
        (3, "Muslim World League"), // .muslimWorldLeague
        (4, "Umm Al-Qura University, Makkah"), // .ummAlQura
        (5, "Egyptian General Authority of Survey"), // .egyptian
        (7, "Institute of Geophysics, University of Tehran"), // .tehran
        (8, "Gulf Region"), // .dubai
        (9, "Kuwait"), // .kuwait
        (10, "Qatar"), // .qatar
        (11, "Majlis Ugama Islam Singapura, Singapore"), // .singapore
        (12, "Union Organization islamic de France"), // .other
        (13, "Diyanet İşleri Başkanlığı, Turkey"), // .turkey
        (14, "Spiritual Administration of Muslims of Russia") // .other
    ]
    
    let schools = [
        (0, "Shafi'i"),
        (1, "Hanafi")
    ]
    
    
    
    
    
    
    
    
    
    
    // MARK: - Refresh location

    /// What Refresh Location is doing (owner, settings-cleanup-1: "make it obvious that the refresh button was pressed").
    private enum RefreshState: Equatable { case idle, working, done, failed(String) }

    /// The whole row is the button (it was only the words, and "sometimes it's not even clickable"): a light tap
    /// buzz, a spinner while the place and times update, then "Updated just now" or what went wrong.
    private var refreshLocationRow: some View {
        Button {
            guard refreshState != .working else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeInOut(duration: 0.2)) { refreshState = .working }
            Task { @MainActor in
                // At least a beat of spinner: a cached answer comes back at once and the tap looked like nothing.
                async let minimum: Void = { try? await Task.sleep(for: .milliseconds(700)) }()
                let result = await viewModel.refreshLocationNow()
                await minimum
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch result {
                    case .success:
                        refreshState = .done
                        locationUpdatedAt = Date().timeIntervalSince1970
                    case .failure(let why): refreshState = .failed(why.message)
                    }
                }
                if case .success = result { triggerSomeVibration(type: .success) }
                // Then quiet again, so "just now" never goes stale on the page.
                try? await Task.sleep(for: .seconds(5))
                if refreshState != .working { withAnimation(.easeInOut(duration: 0.3)) { refreshState = .idle } }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.cityName ?? "Finding your city…")
                        .foregroundStyle(.primary)
                    locationCaption
                        .font(.caption)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                ZStack {
                    if refreshState == .working {
                        ProgressView()
                    } else {
                        Image(systemName: refreshState == .done ? "checkmark" : "arrow.clockwise")
                            .foregroundStyle(refreshState == .done ? Color.green : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 24)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Updates your location and prayer times")
    }

    /// "Updated 2 min ago", or what went wrong; nothing before the first update is known.
    @ViewBuilder private var locationCaption: some View {
        switch refreshState {
        case .failed(let why):
            Text(why).foregroundStyle(.orange)
        case .working:
            Text("Updating…").foregroundStyle(.secondary)
        default:
            if locationUpdatedAt > 0 {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(Self.updatedPhrase(Date(timeIntervalSince1970: locationUpdatedAt), now: context.date))")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "just now" under a minute, else "2 min ago" / "3 hr ago" / "yesterday".
    private static func updatedPhrase(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f.localizedString(for: date, relativeTo: now)
    }

    var body: some View {
        ZStack{
            VStack{
                // Page header: back to the main page, title, light/dark/auto toggle.
                HStack {
                    Button(action: {
                        onBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Text("Settings")
                        .font(.headline)
                    
                    Spacer()
                    
                    ColorModeToggleButton(showFloatingMessage: $showFloatingMessage)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                ScrollViewReader { proxy in
                Form {
                    
                    //MARK: - Location Info
                    Section(header: Text("Location").id("settingsTop")) {
                        // (Latitude / longitude are gone: the city says it — owner, settings-cleanup-1.)
                        if envLocationManager.isAuthorized {
                            // One row: the city, when it was last updated, and the row itself refreshes it
                            // (decision location-row B).
                            refreshLocationRow
                        } else {
                            if let cityName = viewModel.cityName {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text("City")
                                    Spacer()
                                    Text(cityName)
                                }
                            } else {
                                Text("Fetching city...")
                            }
                            // No location permission: prayer times come from a picked city.
                            Button("Choose City") { showCityPicker = true }
                                .tint(.green)
                            Button("Use My Location") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .tint(.green)
                        }
                    }
                    .onChange(of: viewModel.cityName) { _, name in
                        // A real place only: "Error fetching city" / "Unknown" aren't an update (Bradley's review).
                        if let name, !name.isEmpty, name != "Unknown", !name.hasPrefix("Error") {
                            locationUpdatedAt = Date().timeIntervalSince1970
                        }
                    }
                    .sheet(isPresented: $showCityPicker) {
                        CityPickerSheet()
                            .environmentObject(envLocationManager)
                    }
                    
                    
                    // Prayer photos' settings (Show where, Space used) live in Memories' own settings (owner).

                    //MARK: - Notifications
                    Section(header: headerWithInfoButton(title: "Notifications", isPopupVisible: $isNotifPopupVisible) ) {
                        // Will they actually arrive? (NotificationHealth: off / held for the Scheduled
                        // Summary / Time Sensitive / Background App Refresh.)
                        NotificationHealthRows()
                        HStack {
                            prayerCol(prayerName: "Fajr", notifIsOn: $fajrNotif, nudgeIsOn: $fajrNudges)
                            Divider()
                            prayerCol(prayerName: "Dhuhr", notifIsOn: $dhuhrNotif, nudgeIsOn: $dhuhrNudges)
                            Divider()
                            prayerCol(prayerName: "Asr", notifIsOn: $asrNotif, nudgeIsOn: $asrNudges)
                            Divider()
                            prayerCol(prayerName: "Maghrib", notifIsOn: $maghribNotif, nudgeIsOn: $maghribNudges)
                            Divider()
                            prayerCol(prayerName: "Isha", notifIsOn: $ishaNotif, nudgeIsOn: $ishaNudges)
                        }
                        .padding(.vertical)
                        
                        if isNotifPopupVisible{
                            NotificationDropdownInfo()
                        }
                    }
                    
                    
                    // MARK: - Daily Alarm
                    AlarmSettingsView()
                        .id(SettingsJump.fajrAlarm)
                    
                    
                    
                    //MARK: - Prayer Streak Settings 
//                    Section(header: headerWithInfoButton(title: "Streak Settings", isPopupVisible: $isStreakPopupVisible) ) { //prayerstreak_flag
//                        Picker("Streak Type", selection: $prayerStreakMode) {
//                            Text("Level 1").tag(1)
//                            Text("Level 2").tag(2)
//                            Text("Level 3").tag(3)
//                        }
//                        .pickerStyle(.segmented)
//                        
//                        if isStreakPopupVisible{
//                            StreakDropdownInfo()
//                        }
//                    }

                    
                    
                    // (The Masjid section — duas when you arrive and leave — is parked: it didn't fire until the app was
                    // opened (owner, settings-cleanup-1). `MasjidArrival.parked` turns it off for anyone who had it on.)

                    //MARK: - Calculation Method
                    Section(header: Text("Calculation Method")) {
                        Picker("Method", selection: $calculationMethod) {
                            // Follows the country you're in (AutoMethod) — the setup's default.
                            Text(automaticLabel).tag(AutoMethod.automatic)
                            ForEach(calculationMethods, id: \.0) { method in
                                Text(method.1).tag(method.0)
                            }
                        }
                        Picker("School", selection: $school) {
                            ForEach(schools, id: \.0) { school in
                                Text(school.1).tag(school.0)
                            }
                        }
                        
                        // Qibla sensitivity: ± buttons that repeat (and speed up) while held.
                        HStack {
                            Image(systemName: "location.north.line")
                            Text("Qibla Accuracy: ± \(qiblaSensitivity, specifier: "%.1f")°")
                                .monospacedDigit()
                            Spacer()
                            HoldRepeatStepper(value: $qiblaSensitivity,
                                              in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                                              step: 0.5)
                        }
                        
                    }
                    .onChange(of: calculationMethod) { _, new in
                        viewModel.fetchPrayerTimes(cameFrom: "onChange calculationMethod")
                        WidgetCenter.shared.reloadAllTimelines()
                        WatchSync.shared.send()
                    }
                    .onChange(of: school) { _, new in
                        viewModel.fetchPrayerTimes(cameFrom: "onChange school")
                        WidgetCenter.shared.reloadAllTimelines()
                        WatchSync.shared.send()
                    }
                    
                    
                    
                    // The first-run tour again, for everyone (Tour.swift).
                    Section {
                        Button {
                            NotificationCenter.default.post(name: TourRuntime.start, object: nil)
                        } label: {
                            Label("Show me around again", systemImage: "hand.point.up.left")
                        }
                        // The tour ends here (audit J): its last bubble points at this row.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("tourAgainRow", $0) }
                        // The first freestyle session's tips again (owner: a way to see them without the whole tour).
                        CountingTipsAgainRow()
                    }
                    .id("tourAgainRow")
                    // The tour's Settings card (v2): the top on arrival — the page has come to rest by then (scrolling
                    // mid-swipe stalled the pager, Sami's round D run) — then this row for its last step.
                    // The day page's "Set a Fajr alarm ›": the alarm row, once the page is at rest (DaySummary.swift).
                    .onChange(of: SettingsJump.shared.count) { _, _ in
                        withAnimation(.smooth(duration: CircleMotion.standard)) {
                            proxy.scrollTo(SettingsJump.shared.target, anchor: .center)
                        }
                    }
                    .onChange(of: TourRuntime.shared.settingsScroll.1) { _, _ in
                        let to = TourRuntime.shared.settingsScroll.0
                        withAnimation(.smooth(duration: CircleMotion.standard)) {
                            proxy.scrollTo(to == .top ? "settingsTop" : "tourAgainRow", anchor: to == .top ? .top : .center)
                        }
                    }

                    if betaAccess.available {
                        // (Lock Screen time left is "27m" for good — owner, settings-cleanup-1; the picker is gone.)
                        Section {
                            Button {
                                NotificationCenter.default.post(name: FirstRunSetup.rerun, object: nil)
                            } label: {
                                Label("Run setup again", systemImage: "arrow.counterclockwise.circle")
                            }
                        } footer: {
                            Text("Beta builds only: the first-run setup, filled in with your settings.")
                        }
                    }
                    // The watch's pinch log (watch-pinch-log), for any TestFlight install with one: the only pinch watch
                    // is a TestFlight one, with no feedback pull.
                    if betaAccess.beta, let log = WatchSync.pinchLog {
                        Section {
                            ShareLink(item: log) {
                                Label("Send watch pinch log", systemImage: "applewatch.radiowaves.left.and.right")
                            }
                        } footer: {
                            Text("Beta builds: what the watch's pinch did in your last sessions, for the team.")
                        }
                    }

                    //MARK: - Suggestions / Up and Coming
//                    Section(header: Text("Sneak Peek...")) {
//                        
//                        sectionWithChevronButton(image: "map", title: "Masjid Map", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "lightbulb.max.fill", title: "Hadith Motivator", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "fork.knife", title: "Food Finder", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "character.book.closed", title: "Quranic Words", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "gift", title: "Sadqah Links", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "figure.2.left.holdinghands", title: "Support Muslim Brands", isPopupVisible: .constant(false))
//                        
//                        Button("Suggest Feature") {
//                            // control a popup or send to an external link?
//                        }
//                    }
                    
                    Section {
                        ForEach(upcomingFeatures) { feature in
                            HStack {
                                Image(systemName: feature.image)
                                    .frame(width: 24)
                                Text(feature.title)
                                Spacer()
                                Button(action: {
                                    // Set the selected suggestion so the sheet appears.
                                    selectedUpcomingFeature = feature
//                                    showFeatureSheet = true
                                }) {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                    } header: {
                        Text("Sneak Peek...")
                            #if DEBUG
                            .onTapGesture { withAnimation { showDevStuff.toggle() } }   // My Dev Stuff (owner)
                            #endif
                    } footer: {
                        // Which build this is (BuildInfo), under the last section users see.
                        BuildLineButton { showWhatsNew = true }   // → What's new (DEBUG / TestFlight)
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            // The pager ignores the bottom safe area, so the page scrolled to its end
                            // put the build line on the home bar (owner: tapping it woke Siri). The home
                            // bar's ~34 pt plus ~40 of air.
                            .padding(.bottom, 76)
                    }

                    
                    //MARK: - Dev Stuff
                    #if DEBUG
                    // My Dev Stuff, grouped (owner, settings-cleanup-1: "it's a lot of stuff in there and it's not really
                    // ordered"). Pickers for looks already decided stay only where the app still reads them.
                    if showDevStuff {
                        Section {
                            Button("Ring playground…") { showRingPlayground = true }
                            Button("NEXT label playground…") { showNextPlayground = true }
                            // Plays the prayer-begins moment on the Salah circle (visual only: no test
                            // times, no prayer rows or notifications touched).
                            Button("Preview prayer begins", systemImage: "play.circle") {
                                NotificationCenter.default.post(name: PrayerStartPreview.request, object: nil)
                            }
                        } header: { Text("Dev · Playgrounds") }

                        Section {
                            Picker("Tasbeeh ring", selection: $tasbeehRingStyle) {
                                ForEach(TasbeehRingStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            Picker("Zikr wheel", selection: $zikrWheelStyle) {
                                ForEach(ZikrWheelStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            Picker("Prayer list dot", selection: $prayerDotStyle) {
                                ForEach(PrayerDotStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            // A prayer that hasn't started: "NEXT" above it, or the dashed ring alone.
                            Picker("Next prayer", selection: $showNextLabel) {
                                Text("NEXT + dashed ring").tag(true)
                                Text("Dashed ring only").tag(false)
                            }
                            .onChange(of: showNextLabel) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
                            Picker("Mosque icon", selection: $mosqueIconStyle) {
                                ForEach(MosqueIconStyle.allCases) { style in
                                    Label(style.title, systemImage: style.button(on: false)).tag(style.rawValue)
                                }
                            }
                        } header: { Text("Dev · Looks (decided; still read)") }

                        Section {
                            // Every notification shukr sends, to this phone 6 s apart (lock it to see).
                            Button("Send notification samples") { Task { await NotificationSamples.send() } }
                            Button("Reset Autopilot Fajr Alert") {
                                didShowAlarmSetupAlert = false
                                alarmEnabled = false
                            }
                        } header: { Text("Dev · Notifications & alarm") }

                        Section {
                            // Prayers widget speed test: flip one, tap the home widget, feel the difference.
                            Toggle("Still ring (no live fill)", isOn: $widgetStillRing)
                                .onChange(of: widgetStillRing) { WidgetCenter.shared.reloadAllTimelines() }
                            Toggle("Fewest updates", isOn: $widgetFewestEntries)
                                .onChange(of: widgetFewestEntries) { WidgetCenter.shared.reloadAllTimelines() }
                        } header: { Text("Dev · Widget") }

                        Section {
                            // The Salah sheet: the finger drags it (a ScrollView) or a swipe pops it (the old way).
                            Toggle("Salah sheet: follows the finger", isOn: $salahSheetFollows)
                        } header: { Text("Dev · Salah sheet") }

                        Section {
                            Toggle("Compass debug (under the Salah circle)", isOn: $compassDebug)
                            Toggle("Location printer", isOn: $viewModel.locationPrints)
                            Toggle("Scheduling printer", isOn: $viewModel.schedulePrints)
                            Toggle("Calculation printer", isOn: $viewModel.calculationPrints)
                        } header: { Text("Dev · Compass, location & logs") }

                        Section {
                            Toggle("Use test prayer times", isOn: $viewModel.useTestPrayers)
                                .onChange(of: viewModel.useTestPrayers) { _, _ in
                                    viewModel.fetchPrayerTimes(cameFrom: "toggle Use Test Prayer Times")
                                }
                        } header: {
                            Text("Dev · Test data")
                        } footer: {
                            if viewModel.useTestPrayers { Text("Using test times with short intervals.") }
                        }
                    }
                    #endif
                    
                }
                #if DEBUG
                .task {   // `-settingsScrollTo lockTime`: Settings opened on the Lock Screen time-left picker
                    guard UserDefaults.standard.string(forKey: "settingsScrollTo") == "lockTime" else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    proxy.scrollTo("lockTime", anchor: .center)
                }
                #endif
                }
            }
            floatingMessageView(showFloatingMessage: $showFloatingMessage)
        }
        .sheet(isPresented: $showNextPlayground) {
            #if DEBUG
            NextLabelPlayground()
            #endif
        }
        .sheet(isPresented: $showRingPlayground) { RingPlaygroundView() }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView().stageCover("whatsNew") }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoRingPlayground") {
                try? await Task.sleep(for: .seconds(1.5))
                showRingPlayground = true
            }
            if ProcessInfo.processInfo.arguments.contains("-demoNextPlayground") {
                try? await Task.sleep(for: .seconds(1.5))
                showNextPlayground = true
            }
            // `-demoSneakPeek <0…3>` (with -demoSettings): that sneak-peek item's sheet (screenshots).
            if UserDefaults.standard.object(forKey: "demoSneakPeek") != nil {
                let i = UserDefaults.standard.integer(forKey: "demoSneakPeek")
                try? await Task.sleep(for: .seconds(1.5))
                if upcomingFeatures.indices.contains(i) { selectedUpcomingFeature = upcomingFeatures[i] }
            }
        }
        #endif
        .sheet(item: $selectedUpcomingFeature) { feature in
            ScrollView{
                VStack(spacing: 10) {
                // Feature image
                Image(systemName: feature.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .symbolRenderingMode(.monochrome) // Makes the SF Symbol render in a single, monochrome color
                    .foregroundColor(.primary) // Use primary or secondary to avoid the default accent color
                    .padding(.top, 20)
                
                // Title
                Text(feature.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                Text(feature.description)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Spacer()
            }
                
            .padding()
            }
            // One height for all four, fitting the longest text (owner: "food finder opens in large sheet. make it match
            // the others" — with three detents the sheet could open at another one than the rest). The text scrolls if a
            // large text size needs more.
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.height(Self.sneakPeekHeight)])
            .presentationDragIndicator(.visible)  // shows the grab handle at the top

        }

        // The status-bar strip above this page is painted by the pager (PrayerTimesAndTracker),
        // because pages are clipped to the pager's frame and can't reach it from here.
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground))
        .navigationBarBackButtonHidden(false)
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ColorModeToggleButton(showFloatingMessage: $showFloatingMessage)

            }
        }
        // The pushed Settings only: the pager's page refetches when it's paged away from (PrayerTimesAndTracker). Under a
        // pushed page (Your tasks) the pager's copy was told disappear / appear on every update, the fetch published,
        // and the two fed each other at 100 % CPU.
        .onDisappear {
            guard refetchOnLeave else { return }
            viewModel.fetchPrayerTimes(cameFrom: "onDisappear SettingsView")
        }
    }
    
    
                
    
}


//MARK: - Helper Views

struct floatingMessageView: View {
    @Binding var showFloatingMessage: Bool
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    
    private func capsule(for mode: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: mode == 0 ? "sun.max.fill" : mode == 1 ? "moon.fill" : "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.green)
            Text(mode == 0 ? "Light mode" : mode == 1 ? "Dark mode" : "Auto · follows the sun")
                .font(.system(size: 15, weight: .regular, design: .rounded))
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .mapGlass(Capsule())
        .fixedSize()
    }

    var body: some View {
        // Drops in just under the header, right below the toggle that was tapped — at the bottom
        // of the screen it sat on the home indicator and was easy to miss (owner, 2026-09-25).
        VStack{
            // Glass capsule with the mode's symbol (2026-09-25; was an outlined box). One capsule
            // per mode, crossfaded: morphing one capsule's width while its text swapped drew it
            // off-centre for a moment on each switch (owner).
            ZStack {
                ForEach([0, 1, 2], id: \.self) { mode in
                    if mode == colorModeToggleNew {
                        capsule(for: mode)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: colorModeToggleNew)
            .opacity(showFloatingMessage ? 1 : 0.0)
            .scaleEffect(showFloatingMessage ? 1 : 0.9, anchor: .top)
            .offset(y: showFloatingMessage ? 0 : -12)
            .padding(.top, 52)
            .zIndex(1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFloatingMessage)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

struct ColorModeToggleButton: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    @Binding var showFloatingMessage: Bool
    @State private var dismissWorkItem: DispatchWorkItem? // Manage the dismissal timer

    @AppStorage("modeToggleNew") private var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = Auto
    
    var body: some View {
        Button(action: toggleColorMode) {
            Image(systemName: currentSymbol)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
        }
    }
    
    /// Computed property for the current SF Symbol
    private var currentSymbol: String {
        switch colorModeToggleNew {
        case 0: return "sun.min" // Light mode
        case 1: return "moon" // Dark mode
        case 2: return viewModel.isDaytime ? "sun.max.circle" : "moon.circle"
        default: return "circle.lefthalf.filled"
        }
    }
    
    /// Toggle color mode and update the rotation angle
    private func toggleColorMode() {
        withAnimation {
            colorModeToggleNew = (colorModeToggleNew + 1) % 3
        }
        showTemporaryMessage(workItem: &dismissWorkItem, boolToShow: $showFloatingMessage, delay: 2)
    }
}


struct headerWithInfoButton: View {
    var image: String? = nil
    let title: String
    @Binding var isPopupVisible: Bool
    var body: some View {
        HStack {
//            Text("Notifications")
            if let imageName = image {
                Image(systemName: imageName)
                    .frame(width: 24)
            }
            Text(title)
            Spacer()
            Button(action: {
                withAnimation {
                    isPopupVisible.toggle()
                }
            }) {
                Image(systemName: /*isPopupVisible ? "xmark.circle" :*/ "info.circle")
                    .foregroundColor(.green)
            }
        }
    }
}

//struct sectionWithChevronButton: View {
//    var image: String? = nil
//    let title: String
//    let description: String
//    @Binding var isPopupVisible: Bool
//    
//    var body: some View {
//        HStack {
////            Text("Notifications")
//            if let imageName = image {
//                Image(systemName: imageName)
//                    .frame(width: 24)
//            }
//            Text(title)
//            Spacer()
//            Button(action: {
//                withAnimation {
//                    isPopupVisible.toggle()
//                }
//            }) {
//                Image(systemName: "chevron.right")
//                    .foregroundColor(.secondary)
//            }
//        }
//        .sheet(isPresented: $isPopupVisible) {
//            VStack {
//                Text(title)
//                    .font(.title)
//                    .padding()
//                Text(description)
//                    .padding()
//                Button("Close") {
//                    isPopupVisible = false
//                }
//                .padding()
//            }
//        }
//    }
//}


/// One prayer's notifications: a single button that cycles off → start → nudge (nudge includes the
/// start). Also used by the first-run setup's Reminders step (with its sage `accent`).
struct prayerCol: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    let prayerName: String
    @Binding var notifIsOn: Bool
    @Binding var nudgeIsOn: Bool
    var accent: Color = .primary

    var body: some View {
            // Unified Bell Button
            Button(action:{
                if !notifIsOn {
                    notifIsOn = true
                    nudgeIsOn = false
                } else if notifIsOn && !nudgeIsOn {
                    notifIsOn = true
                    nudgeIsOn = true
                } else {
                    notifIsOn = false
                    nudgeIsOn = false
                }
                performBellVibration()
            }) {
                VStack{
                    Text(prayerName)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    Spacer()
                    
                    Image(systemName: notifIsOn ?  (nudgeIsOn ? "bell.badge.fill" : "bell.fill") : "bell.slash.fill" )
                        .foregroundColor(notifIsOn ? accent : .gray)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    

                    Spacer()
                    
                    Text(notifIsOn ?  (nudgeIsOn ? "nudge" : "start") : "off" )

                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: notifIsOn) { _, _ in
                viewModel.fetchPrayerTimes(cameFrom: "onChange notifIsOn")
            }
            .onChange(of: nudgeIsOn) { _, _ in
                viewModel.fetchPrayerTimes(cameFrom: "onChange nudgeIsOn")
            }
    }

    private func performBellVibration() {
        let generator1 = UIImpactFeedbackGenerator(style: .medium)
        let generator2 = UIImpactFeedbackGenerator(style: .light)

        generator1.prepare()
        generator2.prepare()

        generator1.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator2.impactOccurred()
        }
    }
}




struct NotificationDropdownInfo: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            HStack{
                Image(systemName: "bell.slash.fill")
                Text("Off: No notifications will be sent for this prayer.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Image(systemName: "bell.fill")
                Text("Start: One notification when the prayer starts.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Image(systemName: "bell.badge.fill")
                // What NotificationScheduler sends: Mid = halfway through the window, End = 30 min before it ends.
                Text("Nudge: If you haven't marked the prayer yet, you also get a notification halfway through its time and with 30 minutes left.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
        }
        HStack{

            Text("Test Start")
                .frame(maxWidth: .infinity)
                .onTapGesture{
                    let content = UNMutableNotificationContent()
                    content.categoryIdentifier = "Round1_Snooze" // Associate the category

                    let randPrayerName = viewModel.orderedPrayerNames.randomElement()!
                    content.title = "\(randPrayerName) 🟢"
                    content.subtitle = "Pray by \(shortTimePM(Date()))"
                    content.body = "\(randPrayerName) has started"
                    content.sound = UNNotificationSound.default
                    content.interruptionLevel = .timeSensitive
                    addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            Divider()
            Spacer()

            Text("Test Nudge")
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    let content = UNMutableNotificationContent()
                    content.categoryIdentifier = "Round1_Snooze" // Associate the category

                    let randPrayerName = viewModel.orderedPrayerNames.randomElement()!
                    let randNudge = [
                        (title: "\(randPrayerName) 🟡", body: "Halfway through \(randPrayerName)"),
                        (title: "\(randPrayerName) 🔴", body: "Only 30 minutes left")
                    ]
                        .randomElement()!
                    content.title = randNudge.title
                    content.subtitle = "Pray by \(shortTimePM(Date().addingTimeInterval(45 * 60)))"
                    content.body = randNudge.body
                    content.sound = UNNotificationSound.default
                    content.interruptionLevel = .timeSensitive
                    addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)

        }
        .padding(.horizontal)

    }
    
    func addToNotificationCenterBySeconds(identifier: String, content: UNMutableNotificationContent, sec: Double){
        let center = UNUserNotificationCenter.current()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Error \(identifier): \(error.localizedDescription)")
            }
        }
        print("✅ Scheduled \(identifier): in \(sec)s")
    }
}

struct StreakDropdownInfo: View {
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            HStack{
                Text("Level 1: Counts kazas")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Text("Level 2: counts prayers completed during prayer window")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Text("Level 3: counts prayers before 75% of time")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
        }
    }
}


struct AlarmSettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    // Whether or not to show the informational text section
    @State private var isAlarmInfoVisible: Bool = false
    
    // Local state to manage alert presentation
    @State private var isShowingShortcutAlert: Bool = false
    
    // To minimize the editing basically
    @State private var isEditingAlarm: Bool = false
    
    // For reference and shown at bottom while setting the alarm
    @State private var nextFajrTime: Date = Date()
    @State private var nextSunriseTime: Date = Date()
    
    // Persisted state (using AppStorage so the values remain between launches)
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmEnabled: Bool = false
    
    @AppStorage("alarmOffsetMinutes", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmOffsetMinutes: Int = 0
    @AppStorage("alarmIsBefore", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsBefore: Bool = true
    @AppStorage("alarmIsFajr", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsFajr: Bool = true
    @AppStorage("alarmTimeSetFor", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var alarmTimeSetFor: String = ""
    @AppStorage("alarmDescription", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var alarmDescription: String = ""
    
    // A flag to remember if user has already seen the “setup required” alert
    @AppStorage("didShowAlarmSetupAlert") private var didShowAlarmSetupAlert: Bool = false
    /// iOS 26.1+: shukr sets the alarm itself (AlarmKit); the Shortcut steps aside.
    @AppStorage(FajrAlarms.activeKey, store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var alarmKitActive = false
    @State private var alarmKitRefused = false
    
    // ------------------------------------------
    // MARK: - Computed Helpers
    // ------------------------------------------
    
    /// Checks if the user has *actually* chosen “After Sunrise” (which is disallowed).
    private var isAlarmAfterSunrise: Bool {
        // isBefore = false => After
        // isFajr = false => Sunrise
        return (!alarmIsBefore && !alarmIsFajr)
    }
    
    private var shortcutURL: URL? {
        
        if let url = URL(string: "https://www.icloud.com/shortcuts/6ebcfeb12813483992687461d027fd14"){
            return url
        }
        else {
            return nil
        }
    }
    
    private var timeOfCalcAlarmText: String {
        let ref = alarmIsFajr ? nextFajrTime : nextSunriseTime
        let offsetSeconds = alarmIsBefore ? -Double(alarmOffsetMinutes)*60 : Double(alarmOffsetMinutes)*60
        let calcDate = ref.addingTimeInterval(offsetSeconds)
        let day = Calendar.current.isDateInToday(calcDate) ? "today" : "tomorrow"
        return "Alarm \(day) \(shortTimePM(calcDate))"
//        return "\(shortTime(alarmIsFajr ? nextFajrTime : nextSunriseTime)) \(alarmIsBefore ? "-" : "+") \(alarmOffsetMinutes)m = \(shortTimePM(calcDate))"
//        return "is \(shortTimePM(calcDate))"
//        return alarmIsFajr ? "\(shortTimePM(calcDate)) (Fajr is at \(shortTimePM(nextFajrTime)))" : "\(shortTimePM(calcDate)) (Sunrise at \(shortTimePM(nextSunriseTime)))"
//        return "\(shortTimePM(calcDate))"
    }
    
    private var fajrTimeRangeText: String {
//        return "(Fajr is \(shortTime(nextFajrTime)) - \(shortTimePM(nextSunriseTime)))"
//        return alarmIsFajr ? shortTimePM(nextFajrTime) : shortTimePM(nextSunriseTime)
        // "Start" / "End" of Fajr (owner, 2026-09-28), not "Fajr" / "Sunrise".
        return alarmIsFajr ? "Fajr starts \(shortTimePM(nextFajrTime))" : "Fajr ends \(shortTimePM(nextSunriseTime))"
    }
    
    // ------------------------------------------
    // MARK: - Body
    // ------------------------------------------
    
    var body: some View {
        
        Section(header:
                    HStack {
            Text("Alarm Settings")
            Spacer()
            Button(action: {
                withAnimation {
                    isAlarmInfoVisible.toggle()
                }
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.green)
            }
        }
        ) {
            
            // Toggle to enable/disable alarm
            HStack {
                Image(systemName: "alarm")
//                    .foregroundColor(.gray)
                
                Toggle("Schedule Daily Fajr Alarm", isOn: Binding(
                    get: { self.alarmEnabled },
                    set: { newValue in
                        // Animate changes
                        withAnimation {
                            self.alarmEnabled = newValue
                        }
                        // iOS 26.1+: shukr sets real alarms itself (asks once); no Shortcut.
                        if FajrAlarms.supported {
                            Task { @MainActor in
                                if newValue {
                                    if !(await FajrAlarms.enable()) {
                                        withAnimation { alarmEnabled = false }
                                        alarmKitRefused = true
                                    }
                                } else {
                                    await FajrAlarms.plan(reason: "switched off")
                                }
                            }
                            return
                        }
                        // If user just turned it ON and has never seen the alert, show it now
                        if newValue && !didShowAlarmSetupAlert {
                            isShowingShortcutAlert = true
                            didShowAlarmSetupAlert = true
                        }
                    }
                ))
            }
            .alert("Alarms are off for shukr", isPresented: $alarmKitRefused) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("To set your Fajr alarm, allow shukr to schedule alarms in Settings.")
            }
            // Present an alert the first time user toggles the alarm ON
            .alert("Shortcut Required", isPresented: $isShowingShortcutAlert) {
                Button("Get Shortcut") {
                    if let shortcutURL {
                        UIApplication.shared.open(shortcutURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    didShowAlarmSetupAlert = false
                    alarmEnabled = false
                }
            } message: {
                Text("This only works if you set up a shortcut automation. Tap “Get Shortcut” to install it, then tap the info button above for setup steps.")
            }
            
            // If alarm is enabled, show the detail controls
            if alarmEnabled {
                if isEditingAlarm{
                    VStack{
                        
                        HStack {
                            // 5-minute steps (owner, 2026-09-29).
                            Picker("", selection: $alarmOffsetMinutes) {
                                ForEach(Array(stride(from: 0, through: 60, by: 5)), id: \.self) { number in
                                    Text("\(number) min").tag(number)
                                }
                            }
                            .pickerStyle(.wheel)
                            
                            // Picker for "Before"/"After"
                            Picker("", selection: $alarmIsBefore) {
                                Text("Before").tag(true)
                                // Only show "After" if user picked Fajr
                                if alarmIsFajr {
                                    Text("After").tag(false)
                                }
                            }
                            .pickerStyle(.wheel)
                            
                            // Picker for the start / end of Fajr (stored as alarmIsFajr true / false)
                            Picker("", selection: $alarmIsFajr) {
                                Text("Start").tag(true)
                                // Only show "End" if user picked "Before"
                                if alarmIsBefore {
                                    Text("End").tag(false)
                                }
                            }
                            .pickerStyle(.wheel)
                            
                        }
                        .frame(height: 100) // Adjust this value to your preferred height
                        .clipped() // This ensures the picker doesn't overflow its frame
                        
                        // The result big, the Fajr time under it as the proof (owner, 2026-09-29).
                        Text(timeOfCalcAlarmText)
                            .font(.headline.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.green)   // Settings' green (owner, note C9FB37FF)

                        Text(fajrTimeRangeText)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    // The divider under the wheels runs the card's full width (it started at the
                    // centred text, ~200 pt in — owner).
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    
                }
                    
                    Button(action: {
                        withAnimation {
                            isEditingAlarm.toggle()
                            do{
                                let calculatedAlarm = try PrayerUtils.calculateAlarmDescription()
                                let resultTime = calculatedAlarm.time
                                alarmTimeSetFor = shortTimePM(resultTime)
                                alarmDescription = calculatedAlarm.description
                            }
                            catch{
                                print("Error: \(error.localizedDescription)")
                            }
                        }
                        // A new rule: the alarms ahead move with it.
                        if !isEditingAlarm { Task { await FajrAlarms.plan(reason: "rule changed") } }
                    }) {
                        HStack {
                            Text(isEditingAlarm ? "Save" : alarmDescription)
                                .foregroundStyle(isEditingAlarm ? Color.green : Color.gray)
                                .font(isEditingAlarm ? .body.weight(.medium) : .subheadline)
                            Spacer()
                            Image(systemName: isEditingAlarm ? "square.and.arrow.down" : "pencil") // Add the pencil icon here
                                .foregroundStyle(isEditingAlarm ? Color.green : Color.gray) // Match the color with text
                        }
                        .contentShape(Rectangle())   // the whole row taps, not just the text
                    }
                    // Plain: keep our colours and the full-width hit area. iOS 26 restyles a
                    // Form's buttons (tint + label-only hit area), which broke this row's look.
                    .buttonStyle(.plain)

                    // iOS 26.1+: who sets it. shukr (AlarmKit) — how far ahead; or still the
                    // Shortcut (from before) — one tap to let shukr take over.
                    if FajrAlarms.supported && !isEditingAlarm {
                        // shukr sets it: nothing more to say here (owner, settings-cleanup-1: no "every day through …"
                        // line, no test alarm).
                        if !alarmKitActive {
                            Button {
                                Task { @MainActor in
                                    if !(await FajrAlarms.enable()) { alarmKitRefused = true }
                                }
                            } label: {
                                Label("Let shukr set it (no Shortcut needed)", systemImage: "alarm.waves.left.and.right")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
            
            // Info Block
            if isAlarmInfoVisible {
                alarmInfoView
            }
        }
        .onAppear{
            // nil until there's a location (no GPS fix yet at first launch); Settings is mounted
            // at launch, so a force unwrap here crashed the app.
            if let sunrise = viewModel.getNextPrayerTime(for: "sunrise") { nextSunriseTime = sunrise }
            if let fajr = viewModel.getNextPrayerTime(for: "fajr") { nextFajrTime = fajr }
            // 5-minute steps: an older value (e.g. 7) snaps to the nearest step.
            if alarmOffsetMinutes % 5 != 0 { alarmOffsetMinutes = min(60, Int((Double(alarmOffsetMinutes) / 5).rounded()) * 5) }
        }
        .onChange(of: alarmEnabled){_, newValue in
                if newValue {
                    isEditingAlarm = true
            }
        }
    }

    // ------------------------------------------
    // MARK: - Info Section
    // ------------------------------------------
    
    /// iOS 26.1+: how shukr's own alarm works; older: the Shortcut steps.
    @ViewBuilder
    private var alarmInfoView: some View {
        if FajrAlarms.supported {
            VStack(alignment: .leading, spacing: 8) {
                Text("Information:")
                Text("Set the rule once. shukr sets a real alarm for every day ahead, each at the right time as Fajr moves through the year. It rings like any alarm, even on silent or in a Focus.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("It keeps itself topped up: each time you stop it, and whenever shukr runs, the next days are set. Tap “I'm up — open Fajr” on the alarm to go straight to Fajr.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Had the Shortcut automation? It no longer makes an alarm while shukr sets it — no need to delete it.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Where to see it: alarms an app sets (Apple's AlarmKit) don't appear in the Clock app's list — only Clock's own do. When it rings it takes over the Lock Screen like any alarm, with \"shukr\" under the title, even on silent or in a Focus (and on your Apple Watch if it's paired).")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        } else {
            shortcutInfoView
        }
    }


    /// A quick informational view about how to use the alarm feature and set up the shortcuts.
    @ViewBuilder
    private var shortcutInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            Text("No more mental math to set up daily Fajr alarms! Define your rules once. I'll dynamically set daily Fajr alarms for you!")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "1.circle")
                Text("Add iOS shortcut with button below")
//                Text("Click here to add the iOS shortcut")
                    .font(.caption)
                    .foregroundColor(/*.blue*/ .gray)
//                    .underline()
//                    .onTapGesture {
//                        if let shortcutURL {
//                            UIApplication.shared.open(shortcutURL)
//                        }
//                    }
            }
            .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "2.circle")
                Text("Open the iOS Shortcuts App > Automations Tab > Add New")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "3.circle")
                Text("On the sheet > Select 'Time of Day' > 10:00 PM, Daily > Run Immediately > Select this new shortcut")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            Divider()
            
            HStack{

                Text("Add iOS Shortcut")
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        if let shortcutURL {
                            UIApplication.shared.open(shortcutURL)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)

            }
            .padding(.horizontal)

        }
    }
}


/// A ± control whose buttons repeat while held — one step on touch-down, then after 0.4 s a
/// step every 0.12 s, and after 1.5 s every 0.05 s — for values a long way apart, like the
/// qibla accuracy's 1…15° in 0.5° steps. SwiftUI's Stepper needed a press per step.
struct HoldRepeatStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var timer: Timer?
    @State private var pressedAt: Date?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 0) {
            button("minus", direction: -1)
            Divider().frame(height: 18)
            button("plus", direction: 1)
        }
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { stop() }
    }

    private func button(_ symbol: String, direction: Double) -> some View {
        let atLimit = direction < 0 ? value <= range.lowerBound : value >= range.upperBound
        return Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(atLimit ? Color.secondary.opacity(0.4) : Color.primary)
            .frame(width: 44, height: 32)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if pressedAt == nil {                 // touch-down: one step, start repeating
                            pressedAt = Date()
                            bump(direction)
                            start(direction)
                        } else if abs(drag.translation.height) > 12 || abs(drag.translation.width) > 12 {
                            stop()                            // finger drifted: it's a scroll, not a hold
                        }
                    }
                    .onEnded { _ in stop() }
            )
    }

    private func bump(_ direction: Double) {
        let next = min(max(value + direction * step, range.lowerBound), range.upperBound)
        guard next != value else { return }
        value = next
        triggerSomeVibration(type: .light)
    }

    private func start(_ direction: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let pressedAt else { return }
            let held = Date().timeIntervalSince(pressedAt)
            // 0.4 s grace, then every 0.12 s, then every 0.05 s after 1.5 s.
            let interval: TimeInterval = held < 1.5 ? 0.12 : 0.05
            if held >= 0.4, Int((held - 0.4) / 0.05) % Int(interval / 0.05) == 0 { bump(direction) }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pressedAt = nil
    }
}
