import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct SettingsView: View {
    #if DEBUG
    @AppStorage("firstZikrChoice") private var firstZikrChoice = "cards"
    #endif
    @EnvironmentObject var viewModel: PrayerViewModel
    /// Whether notifications can arrive at all: off or not yet allowed hides the per-prayer tiles.
    @ObservedObject private var notificationHealth = NotificationHealth.shared
    private var remindersOff: Bool {
        notificationHealth.checked
            && (notificationHealth.authorization == .notDetermined || notificationHealth.issues.contains(.off))
    }
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
                            Button("Use My Location", action: SettingsLinks.app)
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
                        // The same per-prayer tiles as setup's, in Settings' look. Only while notifications can arrive
                        // (owner: "if reminders are off then no need to show this component. just show reminders are
                        // off... with a button to turn them on" — the rows above say so, with the button).
                        if !remindersOff {
                        // Back to the bells (owner, with the picture of the old row), keeping the dots: black for each
                        // notification it sends, grey otherwise.
                        HStack {
                            prayerCol(prayerName: "Fajr", notifIsOn: $fajrNotif, nudgeIsOn: $fajrNudges, dots: true)
                            Divider()
                            prayerCol(prayerName: "Dhuhr", notifIsOn: $dhuhrNotif, nudgeIsOn: $dhuhrNudges, dots: true)
                            Divider()
                            prayerCol(prayerName: "Asr", notifIsOn: $asrNotif, nudgeIsOn: $asrNudges, dots: true)
                            Divider()
                            prayerCol(prayerName: "Maghrib", notifIsOn: $maghribNotif, nudgeIsOn: $maghribNudges, dots: true)
                            Divider()
                            prayerCol(prayerName: "Isha", notifIsOn: $ishaNotif, nudgeIsOn: $ishaNudges, dots: true)
                        }
                        .padding(.vertical, 4)
                        }

                        if isNotifPopupVisible && !remindersOff {
                            NotificationDropdownInfo()
                        }
                    }
                    
                    
                    #if DEBUG
                    // MARK: - Live Activities (MY4R, research builds only until the feature ships)
                    LiveActivitySettingsSection()
                    #endif

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
                        #if DEBUG
                        // Dev builds: Zikr locked as a new person sees it, or open (ZikrLock; owner: "i wanna be able to
                        // test in my dev build").
                        Toggle(isOn: Binding(get: { !ZikrLock.shared.unlocked },
                                             set: { ZikrLock.shared.setLockedForTesting($0) })) {
                            Label("Zikr locked (test)", systemImage: "lock")
                        }
                        // Page 3's trial layouts, to see on the phone (decision first-zikr-choice).
                        Picker(selection: $firstZikrChoice) {
                            Text("One zikr").tag("one")
                            Text("Choose: cards").tag("cards")
                            Text("Choose: swipe").tag("swipe")
                        } label: {
                            Label("First zikr page (test)", systemImage: "rectangle.stack")
                        }
                        #endif
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
                                Label("Run setup from the start", systemImage: "arrow.counterclockwise.circle")
                            }
                        } footer: {
                            Text("Beta builds only: the whole first-run setup from the hadith page, filled in with your settings.")
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
    /// Settings: how many notifications it sends, as three dots under the bell — black for each one it sends, grey
    /// otherwise (owner: the old look, with the dots kept).
    var dots = false

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

                    if dots {
                        let sends = notifIsOn ? (nudgeIsOn ? 3 : 1) : 0
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i < sends ? Color.primary : Color.secondary.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .animation(.snappy(duration: 0.2), value: sends)
                    }

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
    @AppStorage("fajrNotif") private var fajrNotif = NotificationDefaults.notify("Fajr")
    @AppStorage("fajrNudges") private var fajrNudges = NotificationDefaults.nudges("Fajr")
    @AppStorage("maghribNotif") private var maghribNotif = NotificationDefaults.notify("Maghrib")
    @AppStorage("maghribNudges") private var maghribNudges = NotificationDefaults.nudges("Maghrib")
    /// Fajr or Maghrib on Nudge and too short today for a halfway one (their tile shows ● ○ ●).
    private var shortOnNudge: Bool {
        (fajrNotif && fajrNudges && hasNoHalfwayToday("Fajr")) || (maghribNotif && maghribNudges && hasNoHalfwayToday("Maghrib"))
    }
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

            if shortOnNudge {
                HStack {
                    Image(systemName: "circle.dotted")
                    Text("Fajr and Maghrib are usually too short for a halfway nudge.")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            }
            
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
    @ObservedObject private var betaAccess = WhatsNewAccess.shared
    @State private var showAlarmCheck = false
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
                Button("Open Settings", action: SettingsLinks.app)
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
                            // 5-minute steps (owner, 2026-09-29); before the end of Fajr from 10 (FajrAlarmRule).
                            Picker("", selection: $alarmOffsetMinutes) {
                                ForEach(FajrAlarmRule.minutes(isFajr: alarmIsFajr), id: \.self) { number in
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
                    // Beta: every alarm AlarmKit holds, checked against the rule, and the alarm's log (FajrAlarmKit.swift).
                    if FajrAlarms.supported && !isEditingAlarm && betaAccess.beta {
                        Button { showAlarmCheck = true } label: {
                            Label("Alarm check", systemImage: "checklist")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showAlarmCheck) {
                            NavigationStack {
                                FajrAlarmCheckView()
                                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAlarmCheck = false } } }
                            }
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
            let floored = FajrAlarmRule.clamp(alarmOffsetMinutes, isFajr: alarmIsFajr)
            if floored != alarmOffsetMinutes { alarmOffsetMinutes = floored }
        }
        // Picking the end of Fajr lifts 0 / 5 minutes to 10.
        .onChange(of: alarmIsFajr) { _, isFajr in
            let floored = FajrAlarmRule.clamp(alarmOffsetMinutes, isFajr: isFajr)
            if floored != alarmOffsetMinutes { alarmOffsetMinutes = floored }
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
                Text("It keeps itself topped up: each time you stop it, and whenever shukr runs, the next days are set. Snooze rings it again in \(FajrAlarms.snoozeMinutes) minutes.")
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


#if DEBUG
import ActivityKit

/// Settings → Live Activities (owner, 2026-10-11: "keep this setting different from the notifications … turn it on or
/// off for live activities for each prayer"): the notifications row's five columns, each the prayer's own symbol —
/// black when its window shows as a Live Activity, grey when not. While iOS has Live Activities off for shukr, only that
/// line and the way to Settings.
struct LiveActivitySettingsSection: View {
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var showInfo = false
    @State private var showTuner = false

    var body: some View {
        Section {
            if enabled {
                HStack {
                    ForEach(Array(LiveActivityPrefs.prayers.enumerated()), id: \.offset) { i, prayer in
                        if i > 0 { Divider() }
                        LiveActivityPrayerCol(prayer: prayer)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Label("Live Activities are off for shukr", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Button("Turn them on in Settings") { SettingsLinks.app() }
            }
            if showInfo && enabled {
                Text("A prayer that's on shows on your Lock Screen and in the Dynamic Island from the moment it starts — its ring, the time left and a button to mark it — until you mark it or the next prayer begins.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                showTuner = true
            } label: {
                Label("Tune the card's look", systemImage: "slider.horizontal.3")
            }
            .sheet(isPresented: $showTuner) { LATunerView() }
        } header: {
            HStack {
                Text("Live Activities")
                Spacer()
                Button { withAnimation { showInfo.toggle() } } label: {
                    Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.green)
            }
        }
        .task {
            for await on in ActivityAuthorizationInfo().activityEnablementUpdates { enabled = on }
        }
    }
}

/// One prayer: its name, its symbol (black = on, grey = off), "on" / "off" — a tap flips it.
private struct LiveActivityPrayerCol: View {
    let prayer: String
    @AppStorage private var on: Bool

    init(prayer: String) {
        self.prayer = prayer
        _on = AppStorage(wrappedValue: true, LiveActivityPrefs.key(prayer), store: UserDefaults(suiteName: SharedStore.appGroup))
    }

    var body: some View {
        Button {
            on.toggle()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in LAReal.plan(reason: "Settings: \(prayer) \(on ? "on" : "off")") }
        } label: {
            VStack {
                Text(prayer)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
                Image(systemName: prayerIcon(for: prayer))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(on ? Color.primary : Color.gray.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 22)
                Spacer()
                Text(on ? "on" : "off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: on)
    }
}

/// The Live Activity card's tuner (owner, 2026-10-11: "give me a tuner to adjust the ui layout, gradient, font size,
/// positions … easily labeled … and not hiding the ui so i can see the changes"). The very card the Lock Screen draws
/// (shared views), pinned at the top; its state picked under it; labelled sliders below. Every change is saved to the
/// app group at once; "Show on Lock Screen" redraws the real card and writes the config into la-test.log; "Copy" copies it.
struct LATunerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var t = LATuning.current
    @State private var kind = UserDefaults.standard.integer(forKey: "laTunerState")   // DEBUG -laTunerState N
    @State private var base = Date()
    @State private var note = ""

    private let kinds = ["Running", "Last ½ hr", "Marked", "Ended", "Island"]

    var body: some View {
        NavigationStack {
            Group { if UserDefaults.standard.bool(forKey: "laIslandGallery") { LAIslandGallery(t: t) } else {
            VStack(spacing: 0) {
                preview
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.30), Color(red: 0.05, green: 0.08, blue: 0.12)],
                                               startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
                Picker("State", selection: $kind) {
                    ForEach(kinds.indices, id: \.self) { Text(kinds[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .onChange(of: kind) { _, _ in base = Date() }
                if UserDefaults.standard.bool(forKey: "laFormatTest") { LAFormatTest() } else { Form { controls } }
            }
            } }
            .navigationTitle("Live Activity look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Copy config", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = t.json
                            note = "Copied — paste it to Sami"
                        }
                        Button("Show on Lock Screen", systemImage: "lock.iphone") { Task { await apply() } }
                        Button("Reset to the current look", systemImage: "arrow.counterclockwise", role: .destructive) {
                            t = LATuning(); note = "Reset"
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { UIPasteboard.general.string = t.json; note = "Copied — paste it to Sami" } label: {
                        Label("Copy config", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { Task { await apply() } } label: {
                        Label("Show on Lock Screen", systemImage: "lock.iphone").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .top) {
                    if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).offset(y: -18) }
                }
            }
            .onChange(of: t) { _, new in new.save(); note = "" }
            .onAppear {   // DEBUG -laTimeStyle N, -laWeight N (the sim's taps miss Menus)
                if UserDefaults.standard.object(forKey: "laWeight") != nil {
                    t.titleWeight = UserDefaults.standard.integer(forKey: "laWeight"); t.islandTitleWeight = t.titleWeight
                }
                if UserDefaults.standard.object(forKey: "laTimeStyle") != nil { t.timeLeftFormat = UserDefaults.standard.integer(forKey: "laTimeStyle") }
            }
        }
    }

    // MARK: The pinned preview

    private var sample: LATestAttributes.ContentState {
        let m: Double = 60
        switch kind {
        case 2: return .init(label: "Asr", start: base.addingTimeInterval(-25 * m), end: base.addingTimeInterval(115 * m), symbol: prayerIcon(for: "Asr"), markedAt: base)
        case 3: return .init(label: "Asr", start: base.addingTimeInterval(-145 * m), end: base.addingTimeInterval(-5 * m), symbol: prayerIcon(for: "Asr"))
        case 1 where UserDefaults.standard.object(forKey: "laPreviewLeft") != nil, 4 where UserDefaults.standard.object(forKey: "laPreviewLeft") != nil:   // DEBUG -laPreviewLeft seconds
            return .init(label: "Asr", start: base.addingTimeInterval(-110 * m), end: base.addingTimeInterval(UserDefaults.standard.double(forKey: "laPreviewLeft")), symbol: prayerIcon(for: "Asr"))
        case 1: return .init(label: "Asr", start: base.addingTimeInterval(-110 * m), end: base.addingTimeInterval(20 * m), symbol: prayerIcon(for: "Asr"))
        default: return .init(label: "Asr", start: base.addingTimeInterval(-40 * m), end: base.addingTimeInterval(100 * m), symbol: prayerIcon(for: "Asr"))
        }
    }

    @ViewBuilder private var preview: some View {
        let s = sample
        if kind == 4 {
            // The Dynamic Island opened up, on black.
            // Only roughly the island: iOS places the regions round the camera itself (see board island-rules.md).
            VStack(spacing: 14) {
                LAFoldedIsland(state: s, stale: false, t: t)
                HStack(alignment: .center, spacing: 12) {
                    LAIslandRingAndName(state: s, ended: false, t: t)
                    Spacer(minLength: 0)
                    LAIslandTrailing(state: s, n: 0, ended: false, t: t)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            }
            .frame(maxWidth: .infinity)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 10)
        } else {
            LALockCardBody(state: s, n: 0, ended: kind == 3, t: t)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    // MARK: The controls

    @ViewBuilder private var controls: some View {
        Section("Card") {
            row("Side padding", "space inside the card, left and right", \.cardPaddingSides, 0...40, 1)
            row("Top / bottom padding", "space inside the card, above and below", \.cardPaddingTopBottom, 0...40, 1)
            row("Minimum height", "the card is never shorter than this", \.cardMinHeight, 60...180, 1)
            row("Gap: ring → text", "space between the ring and the name", \.gapRingToText, 0...40, 1)
            row("Background grey", "0 = black, higher = lighter", \.cardSurfaceGrey, 0...0.3, 0.01)
        }
        Section("Ring") {
            row("Ring size", "the ring's box on the left", \.ringSize, 40...120, 1)
            row("Ring diameter", "share of the box the ring fills", \.ringArcDiameter, 0.5...1, 0.01)
            row("Soft band width", "the raised band behind the arc", \.ringBandWidth, 0...20, 0.5)
            row("Arc width", "the coloured progress line", \.ringArcWidth, 1...12, 0.5)
            row("Band lift", "the light on the band's top-left edge", \.ringBandLift, 0...0.3, 0.01)
            row("Prayer symbol size", "the sun / moon inside the ring", \.ringSymbolSize, 8...40, 1)
        }
        Section("Text") {
            Picker("Time left as", selection: Binding(get: { t.timeLeftFormat ?? LATimeLeft.standard }, set: { t.timeLeftFormat = $0 })) {
                ForEach(LATimeLeft.offered, id: \.self) { Text(LATimeLeft.styles[$0]).tag($0) }
            }
            row("Name size", "\"Asr\"", \.titleSize, 10...36, 1)
            Picker("Name weight", selection: Binding(get: { t.titleWeight ?? 2 }, set: { t.titleWeight = $0 })) {
                ForEach(LATuning.weightNames.indices, id: \.self) { Text(LATuning.weightNames[$0]).tag($0) }
            }
            row("Time left size", "\"1 hour, 40 minutes left\" · \"Prayed 4:31 PM\"", \.timeLeftSize, 8...24, 1)
            row("Small line size", "\"ends 6:48 PM\" · \"Perfect · 100\"", \.endsSize, 8...20, 1)
            row("Line spacing", "space between the three lines", \.lineSpacing, 0...12, 0.5)
            row("Move text up / down", "negative = up", \.textOffsetY, -20...20, 1)
        }
        Section("Glow (only once marked Perfect — pick Marked)") {
            row("Strength", "how strong the colour is at the ring", \.glowStrength, 0...0.6, 0.01)
            row("Reach", "how far it spreads before it's gone", \.glowReach, 0.1...1.2, 0.01)
            row("Centre left / right", "0 = left edge, 1 = right edge", \.glowCentreX, 0...1, 0.01)
            row("Centre up / down", "0 = top, 1 = bottom", \.glowCentreY, 0...1, 0.01)
        }
        Section("Buttons") {
            row("Symbol brightness", "1 = full white; lower = duller", \.symbolOpacity, 0.2...1, 0.05)
            row("Button size", "the soft round disc", \.buttonSize, 24...64, 1)
            row("Symbol size", "the circle / camera / beads inside", \.buttonSymbolSize, 8...32, 1)
            row("Gap between camera and beads", "after marking", \.buttonStackGap, 0...24, 1)
            row("Move buttons left / right", "positive = right", \.buttonOffsetX, -20...20, 1)
        }
        Section("15-second bar (after marking — pick Marked)") {
            row("Side inset", "space from the card's left and right edges", \.barSideInset, 0...60, 1)
            row("Bottom inset", "space from the card's bottom edge", \.barBottomInset, 0...30, 1)
            row("Thickness", "1 = the system's own", \.barThickness, 0.5...3, 0.1)
        }
        Section("Dynamic Island (opened up — pick Island)") {
            row("Ring size", "", \.islandRingSize, 30...90, 1)
            row("Name size", "", \.islandTitleSize, 10...30, 1)
            row("Line size", "", \.islandLineSize, 8...20, 1)
            row("Button size", "", \.islandButtonSize, 24...56, 1)
            row("Time size", "\"27m\" over the button, last half hour only", \.islandTimeSize, 12...36, 1)
            Picker("Name weight", selection: Binding(get: { t.islandTitleWeight ?? 2 }, set: { t.islandTitleWeight = $0 })) {
                ForEach(LATuning.weightNames.indices, id: \.self) { Text(LATuning.weightNames[$0]).tag($0) }
            }
            Picker("Layout", selection: Binding(get: { t.islandLayout ?? 1 }, set: { t.islandLayout = $0 })) {
                Text("Ring by the camera, name under").tag(0)
                Text("Ring + name together").tag(1)
                Text("One row under the camera").tag(2)
            }
        }
    }

    /// One labelled slider. Changed from the original: "was 16" beside the value and a reset arrow for just this one.
    private func row(_ title: String, _ hint: String, _ key: WritableKeyPath<LATuning, Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
        let value = Binding(get: { t[keyPath: key] }, set: { t[keyPath: key] = $0 })
        let original = LATuning()[keyPath: key]
        let changed = abs(t[keyPath: key] - original) > step / 2
        let fmt: (Double) -> String = { step < 1 ? String(format: "%.2f", $0) : String(format: "%.0f", $0) }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline)
                Spacer()
                if changed {
                    Text("was \(fmt(original))").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
                Text(fmt(t[keyPath: key]))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(changed ? .primary : .secondary)
                Button {
                    t[keyPath: key] = original
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.footnote)
                }
                .buttonStyle(.borderless)
                .disabled(!changed)
                .opacity(changed ? 1 : 0.25)
                .accessibilityLabel("Reset \(title)")
            }
            if !hint.isEmpty { Text(hint).font(.caption2).foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step)
        }
    }

    /// Saves, redraws the real cards (an update with the same content makes the widget extension render again, reading
    /// the new numbers), and writes the config into la-test.log so Sami can read it off the phone.
    private func apply() async {
        t.save()
        var n = 0
        for a in Activity<LATestAttributes>.activities where a.activityState == .active || a.activityState == .stale {
            await a.update(a.content)
            n += 1
        }
        LATestLog.add("tuning applied to \(n) card(s): " + t.json.replacingOccurrences(of: "\n", with: " "))
        note = n == 0 ? "Saved — no card on the Lock Screen right now" : "Saved and redrawn on the Lock Screen"
    }
}
#endif

#if DEBUG
/// DEBUG -laFormatTest: which self-updating formats give "2:36" / "27".
struct LAFormatTest: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([1630.0, 605.0, 595.0, 50.0], id: \.self) { left in
                let end = Date.now.addingTimeInterval(left)
                HStack {
                    Text("\(Int(left)) s").frame(width: 70, alignment: .leading)
                    LAMinutesLeft(end: end).foregroundStyle(.red).fontWeight(.semibold)
                    Text(timerInterval: Date.now...end, countsDown: true, showsHours: false).foregroundStyle(.secondary)
                }
            }
        }.font(.system(size: 17)).padding()
        Spacer()
    }
}
#endif

#if DEBUG
/// The island folded, drawn roughly as iOS does: a black pill with the camera in its middle, our two sides at its ends.
struct LAFoldedIsland: View {
    let state: LATestAttributes.ContentState
    let stale: Bool
    let t: LATuning
    var body: some View {
        HStack {
            LACompactLeading(state: state, stale: stale, t: t).padding(.leading, 9)
            Spacer(minLength: 0)
            LAEnds(state: state, stale: stale) { e in LACompactTrailing(state: state, ended: e) }.padding(.trailing, 12)
        }
        .frame(width: 230, height: 37)
        .background(Color.black, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

/// DEBUG -laIslandGallery: the island folded and opened in each state, for screenshots.
struct LAIslandGallery: View {
    let t: LATuning
    private let now = Date()
    private func state(start: Double, end: Double, marked: Bool = false) -> LATestAttributes.ContentState {
        .init(label: "Asr", start: now.addingTimeInterval(start * 60), end: now.addingTimeInterval(end * 60), symbol: prayerIcon(for: "Asr"),
              markedAt: marked ? now : nil)
    }
    private var rows: [(String, LATestAttributes.ContentState, Bool)] {
        [("Running · 1 hr 40 left", state(start: -40, end: 100), false),
         ("Last half hour · 27 left", state(start: -113, end: 27), false),
         ("Marked · Perfect", state(start: -20, end: 120, marked: true), false),
         ("Marked · later", state(start: -95, end: 45, marked: true), false),
         ("Ended, not marked", state(start: -145, end: -5), true)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folded").font(.headline).foregroundStyle(.white)
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    LAFoldedIsland(state: rows[i].1, stale: rows[i].2, t: t)
                    Text(rows[i].0).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
            Text("Opened").font(.headline).foregroundStyle(.white).padding(.top, 6)
            ForEach([1, 2, 3], id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rows[i].0).font(.caption).foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .center, spacing: 12) {
                        LAIslandRingAndName(state: rows[i].1, ended: false, t: t)
                        Spacer(minLength: 0)
                        LAIslandTrailing(state: rows[i].1, n: 0, ended: false, t: t)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .environment(\.colorScheme, .dark)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.30), Color(red: 0.05, green: 0.08, blue: 0.12)], startPoint: .top, endPoint: .bottom))
    }
}
#endif
