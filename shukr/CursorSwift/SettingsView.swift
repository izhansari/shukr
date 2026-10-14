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
    /// Settings → Reminders' switch: which side shows (kept), and whether each side needs a look (its orange dot).
    @AppStorage("settings.remindersTab") private var remindersTab = ReminderSwitch.notifications
    @State private var liveActivitiesOn = LiveActivitySetupStep.systemEnabled
    private var notificationsNeedYou: Bool {
        #if DEBUG
        if let d = UserDefaults.standard.string(forKey: "demoReminderBadge") { return d == "both" || d == "notifications" }   // -demoReminderBadge notifications|liveActivities|both
        #endif
        return notificationHealth.checked && (notificationHealth.authorization == .notDetermined || !notificationHealth.issues.isEmpty)
    }
    private var liveActivitiesNeedYou: Bool {
        #if DEBUG
        if let d = UserDefaults.standard.string(forKey: "demoReminderBadge") { return d == "both" || d == "liveActivities" }
        #endif
        return !liveActivitiesOn
    }
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
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var qiblaSensitivity: Double = 5
    
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
    @AppStorage(LiveActivityLook.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var liveActivityLookRaw = LiveActivityLook.system.rawValue
    @State private var isAppearanceInfoVisible = false
    @AppStorage("widgetStyle", store: UserDefaults(suiteName: SharedStore.appGroup)) private var widgetStyleRaw = "system"   // WidgetStyle (shukrWidget/AppIntent.swift)
    
    
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1 //prayerstreak_flag
    @State private var isNotifPopupVisible: Bool = false
    /// Prayer Times' ⓘ: what a method, a madhab and the qibla's accuracy are (owner, decision settings-times-explainer A).
    @State private var isTimesInfoVisible = false
    @State private var isStreakPopupVisible: Bool = false
    
    @State private var rotationAngle: Double = 0 // For rotating the symbol
    
    // for the floating message
    @State private var showFloatingMessage = false // State to control visibility
    @State private var modeMessageWork: DispatchWorkItem?
    
    // For minimizing and expanding the devSection
    /// DEBUG: tap the "Sneak Peek" header, or launch with `-devStuff`.
    @State private var showDevStuff = ProcessInfo.processInfo.arguments.contains("-devStuff")
    @AppStorage(ExplorePageVariant.key) private var exploreVariant = ExplorePageVariant.simple.rawValue
    /// DEBUG: the compass's sources, rate and accuracy under the Salah circle (compass audit 2026-09-30).
    @AppStorage("compassDebug") private var compassDebug = false
    @State private var showCityPicker = false
    @State private var refreshState: RefreshState = .idle
    /// When the city was last worked out (the location row's "Updated 2 min ago").
    @AppStorage("locationUpdatedAt") private var locationUpdatedAt: Double = 0
    @AppStorage("tasbeehRingStyle") private var tasbeehRingStyle = TasbeehRingStyle.fine.rawValue
    @State private var showWhatsNew = false
    @State private var showRingPlayground = false
    @State private var showLiveActivitySetup = false
    @State private var showLATuner = false
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
        sneakPeekItem(image: "character.book.closed", title: "Quranic Vocab", description: "Explore and learn common words from the Quran to make it easier to focus during prayer.")
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
            // One line like Method and Madhab beside it (owner): "Location" + its refresh symbol, the city on the right
            // in the pickers' value type; when it was updated sits under the card (`locationFooter`).
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color(.label))   // the page's other leading symbols' color (owner)
                    .frame(width: 24)
                Text("Location")
                    .foregroundStyle(.primary)
                ZStack {
                    if refreshState == .working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: refreshState == .done ? "checkmark" : "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(refreshState == .done ? Color.green : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 20)
                Spacer(minLength: 8)
                // (No "Location updated" line any more — owner. A failed refresh says why here, in orange, for its few
                // seconds; the spinner and ✓ by "Location" show the rest.)
                Group {
                    if case .failed(let why) = refreshState {
                        Text(why).foregroundStyle(.orange)
                    } else {
                        Text(viewModel.cityName ?? "Finding…").foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Updates your location and prayer times")
    }


    /// The switch's sides: Notifications · Live Activities (iOS 26+) · Fajr Alarm, each with its orange dot.
    private var reminderSides: [ReminderSwitch.Side] {
        var sides = [ReminderSwitch.Side(id: ReminderSwitch.notifications, title: "Notifications", needsYou: notificationsNeedYou)]
        if PrayerLiveActivities.supported {
            sides.append(.init(id: ReminderSwitch.liveActivities, title: "Live Activities", needsYou: liveActivitiesNeedYou))
        }
        sides.append(.init(id: ReminderSwitch.fajrAlarm, title: "Fajr Alarm", needsYou: fajrAlarmStatus.needsYou))
        return sides
    }
    /// The side showing (a Live Activities pick kept from a newer iOS falls back to Notifications).
    private var shownReminderTab: String {
        remindersTab == ReminderSwitch.liveActivities && !PrayerLiveActivities.supported ? ReminderSwitch.notifications : remindersTab
    }
    @State private var fajrAlarmStatus = FajrAlarmStatus.shared
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: SharedStore.appGroup)) private var fajrAlarmOn = false

    /// Under the Reminders card (decision reminders-status-row B): how far ahead the side showing is set up.
    /// "12 scheduled through Sun, Oct 18" (owner): how many, and how far.
    private var remindersFooter: String? {
        func line(_ n: Int, _ through: Date) -> String { "\(n) scheduled through \(Self.throughDay(through))" }
        if shownReminderTab == ReminderSwitch.fajrAlarm {
            guard fajrAlarmOn, FajrAlarms.isActive, !fajrAlarmStatus.needsYou, let through = fajrAlarmStatus.through else { return nil }
            return line(fajrAlarmStatus.count, through)
        } else if shownReminderTab == ReminderSwitch.liveActivities {
            guard liveActivitiesOn else { return nil }
            if let through = laStatus.through { return line(laStatus.held, through) }
            return laStatus.held == 0 && LiveActivityPrefs.prayers.contains(where: LiveActivityPrefs.isOn) ? "None waiting right now" : nil
        } else if !remindersOff, let through = notificationHealth.scheduledThrough {
            return line(notificationHealth.scheduledCount, through)
        }
        return nil
    }
    @State private var laStatus = LiveActivityStatus.shared
    /// The card's last line, small and grey; where it leads, the row's chevron says so.
    private func footerLine(_ line: String) -> some View {
        Text(line)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
    }

    /// "Fri, Oct 23".
    private static func throughDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Settings' header — back, title — laid over the list, as a system bar is (owner: the see-through top of Your
    /// Notifications): the list scrolls on under it, softened at the edge (iOS 26's scroll edge effect via `safeAreaBar`;
    /// a bar material before).
    private var settingsHeader: some View {
        HStack {
            // Glass circles (owner), as iOS 26's own bar buttons — our own glass, not the system toolbar's
            // (that left ghost circles on Memories).
            Button(action: {
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .barGlass(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            
            Spacer()
            
            Text("Settings")
                .font(.headline)
            
            Spacer()

            // (No look button up here any more — Appearance → App does it, owner. An empty slot keeps the
            // title centred.)
            Color.clear.frame(width: 44, height: 44)
    }
    .padding(.horizontal)
    .padding(.top, 8)
    }

    /// Room for the tour's panel over the page while its Settings chapter is here: from where the page's content starts
    /// on this screen to the panel's measured bottom (any phone, any text size — no fixed number).
    private var tourRoomNow: CGFloat {
        let tour = TourRuntime.shared
        guard tour.active, tour.step == .settings, tour.phase != .go,
              let panel = TourTargets.shared.frame("topPanel"), panel.height < 320, listTop > 0 else { return 0 }
        return max(0, (panel.maxY + 4 - listTop).rounded())
    }
    /// The room kept: it only grows within the chapter (the panel's height changes with each to-do; the page shouldn't
    /// move up and down with it), back to 0 once the chapter's over.
    @State private var tourRoom: CGFloat = 0
    /// Where the page's content starts, in screen points: the bottom of its top bar.
    @State private var listTop: CGFloat = 0

    var body: some View {
        ZStack{
            VStack{
                ScrollViewReader { proxy in
                Form {
                    
                    //MARK: - Prayer Times: where you are and how the times are worked out (owner: Location and Calculation
                    // Method made one section)
                    Section {
                        // (Latitude / longitude are gone: the city says it — owner, settings-cleanup-1.)
                        if envLocationManager.isAuthorized {
                            // One row: the city, when it was last updated, and the row itself refreshes it
                            // (decision location-row B).
                            refreshLocationRow
                        } else {
                            if let cityName = viewModel.cityName {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .frame(width: 24)
                                    Text("Location")
                                    Spacer()
                                    Text(cityName).foregroundStyle(.secondary).lineLimit(1)
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
                        // The method, the school and the qibla's accuracy, under the place (owner: one section, Prayer Times).
                        Picker(selection: $calculationMethod) {
                            // Follows the country you're in (AutoMethod) — the setup's default.
                            Text(automaticLabel).tag(AutoMethod.automatic)
                            ForEach(calculationMethods, id: \.0) { method in
                                Text(method.1).tag(method.0)
                            }
                        } label: {
                            // A symbol each, in the qibla row's column (owner: the section reads uniform).
                            HStack(spacing: 12) {
                                Image(systemName: "angle").frame(width: 24)   // sun.horizon is a prayer's (owner)
                                Text("Method")
                            }
                        }
                        Picker(selection: $school) {
                            ForEach(schools, id: \.0) { school in
                                Text(school.1).tag(school.0)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed").frame(width: 24)
                                Text("Madhab")
                            }
                        }
                        
                        // Qibla sensitivity: ± buttons that repeat (and speed up) while held.
                        HStack(spacing: 12) {
                            Image(systemName: "location.north.line")
                                .frame(width: 24)
                            // One line like the rows above it (owner): "Qibla", its value in the pickers' grey, then − +.
                            Text("Qibla")
                            Spacer(minLength: 8)
                            Text("± \(qiblaSensitivity.formatted(.number.precision(.fractionLength(0...1))))°")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HoldRepeatStepper(value: $qiblaSensitivity,
                                              in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                                              step: 0.5)
                        }
                        // Excused from prayer (Excused.swift; decision excused-where B: Settings only).
                        ExcusedSettingsRow()
                    } header: {
                        headerWithInfoButton(title: "Prayer Times", isPopupVisible: $isTimesInfoVisible).id("settingsTop")
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

                    //MARK: - Reminders: notifications and Live Activities in one section, a switch on top (owner, decision
                    // settings-alerts E): only the side picked shows — its status row, its five prayers, and on the Live
                    // Activities side Card Appearance; a side with something wrong wears an orange dot on the switch.
                    // Before iOS 26 there's no Live Activities side and no switch.
                    Section {
                        // The switch, in the card (owner: not apart from its component). Its separator isn't hidden but
                        // painted in the card's own colour, edge to edge: hidden, a hairline seam of the page showed
                        // under it whenever the card landed on a fractional pixel (the bug the owner first met with the
                        // Fajr alarm).
                        ReminderSwitch(tab: $remindersTab, sides: reminderSides)
                            // The tour's Settings chapter: where its try-its are, and when they happen.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                if TourRuntime.shared.active { TourTargets.shared.set("remindersSwitch", frame) }
                            }
                            .onChange(of: remindersTab) { _, side in TourRuntime.shared.event(.reminderTab(side)) }
                            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                            .listRowSeparatorTint(Color(.secondarySystemGroupedBackground))
                            .alignmentGuide(.listRowSeparatorLeading) { _ in -12 }   // the card's edges (the row is 12 in)
                            .alignmentGuide(.listRowSeparatorTrailing) { d in d.width + 12 }
                        if shownReminderTab == ReminderSwitch.liveActivities {
                            LiveActivitySettingsRows(showInfo: false)
                        } else if shownReminderTab == ReminderSwitch.fajrAlarm {
                            // Fajr Alarm lives here now (owner): its own section is gone.
                            AlarmSettingsView()
                        } else {
                            // Will they actually arrive? (NotificationHealth: off / held for the Scheduled
                            // Summary / Time Sensitive / Background App Refresh.)
                            NotificationHealthRows()
                            // The same per-prayer tiles as setup's, in Settings' look. Only while notifications can
                            // arrive (owner: "if reminders are off then no need to show this component…").
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
                            // The tour's first Reminders try-it: a bell (it's put back after).
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                if TourRuntime.shared.active { TourTargets.shared.set("reminderBells", frame) }
                            }
                            .onDisappear { TourTargets.shared.clear("reminderBells") }
                            }
                        }
                        // How far ahead the side showing is set up — inside the card, its last line (owner), on every side.
                        // On the notifications side the line is also the way into Your Notifications, the next one on its
                        // right (owner: no thick row of its own; "show it leads somewhere" — the chevron).
                        // Every side: how many and how far, a chevron to the list (owner). Notifications → Your Notifications,
                        // Live Activities → the cards waiting, the alarm → Alarm check (beta builds).
                        if let line = remindersFooter {
                            switch shownReminderTab {
                            case ReminderSwitch.notifications:
                                NavigationLink { YourRemindersView() } label: { footerLine(line) }
                            case ReminderSwitch.fajrAlarm where betaAccess.beta:
                                NavigationLink { FajrAlarmCheckView() } label: { footerLine(line) }
                            case ReminderSwitch.fajrAlarm:
                                footerLine(line)
                            default:
                                NavigationLink { ScheduledLiveActivitiesPage() } label: { footerLine(line) }
                            }
                        }
                    } header: {
                        headerWithInfoButton(title: "Reminders", isPopupVisible: $isNotifPopupVisible)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                if TourRuntime.shared.active { TourTargets.shared.set("remindersHeader", frame) }
                            }
                            .onChange(of: isNotifPopupVisible) { _, open in TourRuntime.shared.event(.remindersInfo(open: open)) }
                    }
                    .id("liveActivities")


                    
                    
                    
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

                    
                    
                    
                    //MARK: - Appearance: every look in one place (owner, settings-appearance): the app's, the Live Activity
                    // card's (was Reminders → Card Appearance); widgets follow the iPhone (nothing of ours to set).
                    Section {
                        Picker(selection: $colorModeToggleNew) {
                            Text("System").tag(3)
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                            Text("Sun").tag(2)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.lefthalf.filled").frame(width: 24)
                                Text("App")
                            }
                        }
                        .onChange(of: colorModeToggleNew) { _, _ in
                            // The little pill under the header, as the old top-right button showed (owner).
                            showTemporaryMessage(workItem: &modeMessageWork, boolToShow: $showFloatingMessage, delay: 2)
                        }
                        if PrayerLiveActivities.supported {
                            NavigationLink {
                                // It hands its pick back: a write through its own handle on the app group didn't reach this
                                // row (owner: "doesn't show it when changing and coming back").
                                LiveActivityAppearancePage { liveActivityLookRaw = $0 }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "platter.filled.bottom.iphone").frame(width: 24)
                                    Text("Live Activity card").lineLimit(1).layoutPriority(1)   // never two lines
                                    Spacer(minLength: 8)
                                    Text((LiveActivityLook(rawValue: liveActivityLookRaw) ?? .system).title)
                                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                }
                            }
                        }
                        // Every Prayers widget's look (decision widget-style-shared A): the widget's own settings say
                        // "Change in shukr Settings" — iOS never lets the app change those. A page with the widget as its
                        // preview, as Live Activity card and Icon have (owner, 2026-10-14).
                        NavigationLink {
                            PrayersWidgetAppearancePage { widgetStyleRaw = $0 }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.grid.2x2").frame(width: 24)
                                Text("Prayers widget")   // only the Prayers widget follows it (owner: not all widgets)
                                Spacer(minLength: 8)
                                Text((WidgetStyle(rawValue: widgetStyleRaw) ?? .system).title).foregroundStyle(.secondary)
                            }
                        }
                        AppIconRow()
                    } header: {
                        // What each look means is in the ⓘ (owner: not as text under the section).
                        headerWithInfoButton(title: "Appearance", isPopupVisible: $isAppearanceInfoVisible)
                    }

                    // Explore shukr (owner, settings-explore): the features people don't find. The simple page by default
                    // (ExploreSimple.swift, ask settings-explore-lean); the others, Frank's original too, from My Dev Stuff (owner: "keep it as something in the dev
                    // settings that I can change back to"). A count only when something's new.
                    Section {
                        // Give to Causes (Sadaqah.swift; owner, 2026-10-13): vetted charities and community groups + a private
                        // log. Out of Sneak Peek now it's real; in Settings, not ☰ (owner).
                        NavigationLink { SadaqahPage() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gift").frame(width: 24)
                                Text("Give to Causes")   // never reads as shukr asking for money (owner)
                            }
                        }
                        NavigationLink {
                            switch ExplorePageVariant(rawValue: exploreVariant) ?? .simple {
                            case .simple: ExploreSimplePage()
                            case .grouped: ExploreGroupedPage()
                            case .showcase: ExploreShowcasePage()
                            case .lean: ExploreLeanPage()
                            case .original: ExploreShukrPage()
                            }
                        } label: {
                            let variant = ExplorePageVariant(rawValue: exploreVariant) ?? .simple
                            let newCount = switch variant {
                            case .simple, .grouped: ExploreGrouped.newCount
                            case .showcase: ExploreShowcase.newCount
                            case .lean: ExploreLean.newCount
                            case .original: 0
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").frame(width: 24)
                                Text("Explore shukr")
                                Spacer()
                                if newCount > 0 {
                                    Text("\(newCount) new")
                                        .font(.system(.caption, design: .rounded, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.sage))
                                }
                            }
                        }
                    } header: {
                        Text("More")
                    }

                    // The tours again, for everyone (Tour.swift, CountTips.swift), under their own label (owner).
                    Section(header: Text("Tours")) {
                        Button {
                            NotificationCenter.default.post(name: TourRuntime.start, object: nil)
                        } label: {
                            Label {
                                Text("Take the app tour again")
                            } icon: {
                                Image(systemName: "hand.point.up.left").foregroundStyle(Color(.label))
                            }
                        }
                        .tint(Color(.label))   // the qibla row's colors, no blue on this page (owner)
                        // The tour ends here (audit J): its last bubble points at this row.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("tourAgainRow", $0) }
                        // The Zikr tour again (owner): the Zikr page locked as a new person sees it, and there.
                        ZikrTourAgainRow()
                        // The tour's words, editable with the panel drawn (owner; beta builds).
                        if betaAccess.beta {
                            NavigationLink {
                                TourCopyTuner()
                            } label: {
                                Label {
                                    Text("Tour copy")
                                } icon: {
                                    Image(systemName: "character.cursor.ibeam").foregroundStyle(Color(.label))
                                }
                            }
                        }
                    }
                    .id("tourAgainRow")
                    // The tour's Settings card (v2): the top on arrival — the page has come to rest by then (scrolling
                    // mid-swipe stalled the pager, Sami's round D run) — then this row for its last step.
                    // The day page's "Set a Fajr alarm ›": the alarm row, once the page is at rest (DaySummary.swift).
                    .onChange(of: SettingsJump.shared.count) { _, _ in
                        let target = SettingsJump.shared.target
                        let side = target == SettingsJump.fajrAlarm ? ReminderSwitch.fajrAlarm
                            : target == SettingsJump.liveActivities ? ReminderSwitch.liveActivities
                            : target == SettingsJump.notifications ? ReminderSwitch.notifications : nil
                        if let side { remindersTab = side }
                        withAnimation(.smooth(duration: CircleMotion.standard)) {
                            proxy.scrollTo(side != nil ? "liveActivities" : target, anchor: .center)
                        }
                    }
                    .onChange(of: TourRuntime.shared.settingsScroll.1) { _, _ in
                        let to = TourRuntime.shared.settingsScroll.0
                        withAnimation(.smooth(duration: CircleMotion.standard)) {
                            // The top: the first header asked for well down the page, so the scroll stops at the page's own
                            // start (its margin under the tour's panel kept) — `.top` pinned it under the panel.
                            proxy.scrollTo(to == .top ? "settingsTop" : "tourAgainRow", anchor: to == .top ? UnitPoint(x: 0.5, y: 0.3) : .center)
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
                            // Moved here from the page (owner, settings cleanup 2026-10-12).
                            Button {
                                NotificationCenter.default.post(name: FirstRunSetup.rerun, object: nil)
                            } label: {
                                Label("Run setup from the start", systemImage: "arrow.counterclockwise.circle")
                            }
                            // The first freestyle session's tips again (was under Tours; the Zikr tour took its place).
                            CountingTipsAgainRow()
                            // Zikr locked as a new person sees it, or open (ZikrLock; owner: "i wanna be able to test
                            // in my dev build").
                            Toggle(isOn: Binding(get: { !ZikrLock.shared.unlocked },
                                                 set: { ZikrLock.shared.setLockedForTesting($0) })) {
                                Label("Zikr locked (test)", systemImage: "lock")
                            }
                            // Page 3's trial layouts (decision first-zikr-choice); release builds always show cards.
                            Picker(selection: $firstZikrChoice) {
                                Text("One zikr").tag("one")
                                Text("Choose: cards").tag("cards")
                                Text("Choose: swipe").tag("swipe")
                            } label: {
                                Label("First zikr page (test)", systemImage: "rectangle.stack")
                            }
                            // The Live Activity card's tuner (was under Live Activities on the page).
                            Button("Live Activity card tuner…") { showLATuner = true }
                            // Explore shukr's page: the showcase (default), the lean one, or Frank's original (owner: "keep it as
                            // something in the dev settings that I can change back to").
                            Picker(selection: $exploreVariant) {
                                ForEach(ExplorePageVariant.allCases) { Text($0.label).tag($0.rawValue) }
                            } label: {
                                Label("Explore page", systemImage: "sparkles")
                            }
                        } header: { Text("Dev · Setup, zikr & Live Activity") }

                        Section {
                            Button("Ring playground…") { showRingPlayground = true }
                            // The setup's Live Activity page on its own, its words editable from its ⚙ (owner).
                            Button("Live Activity setup page…") { showLiveActivitySetup = true }
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
                // The tour's panel sits over the page's top: while its Settings chapter is on, the page starts under it
                // (owner: the swipe in seemed to land mid-page — the page's top was under the panel).
                .contentMargins(.top, tourRoom, for: .scrollContent)
                .animation(.smooth(duration: CircleMotion.standard), value: tourRoom)
                .onChange(of: tourRoomNow, initial: true) { _, now in tourRoom = now == 0 ? 0 : max(tourRoom, now) }
                #if DEBUG
                .task {   // `-settingsScrollTo lockTime`: Settings opened on the Lock Screen time-left picker
                    guard let to = UserDefaults.standard.string(forKey: "settingsScrollTo") else { return }   // + liveActivities
                    try? await Task.sleep(for: .seconds(2.5))
                    proxy.scrollTo(to, anchor: .center)
                }
                #endif
                }
                .modifier(OverListHeader {
                    settingsHeader
                        // The page's content starts under this bar (its 6 pt padding below): the tour's room is measured
                        // from here.
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY + 6 } action: { listTop = $0 }
                })
            }
            floatingMessageView(showFloatingMessage: $showFloatingMessage)
        }
        .sheet(isPresented: $showNextPlayground) {
            #if DEBUG
            NextLabelPlayground()
            #endif
        }
        .sheet(isPresented: $showRingPlayground) { RingPlaygroundView() }
        // The Reminders switch's dots, live (owner: turned off in iOS, back through the app switcher, no badge until a
        // force quit): iOS's own change streams while the page lives, plus one re-read each time the app comes back —
        // nothing polls. Notifications are re-read on every return by the app (shukrApp).
        .task {
            guard PrayerLiveActivities.supported else { return }
            for await on in ActivityAuthorizationInfo().activityEnablementUpdates where liveActivitiesOn != on { liveActivitiesOn = on }
        }
        .task { await notificationHealth.refresh() }   // was NotificationHealthRows' own (see there)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            fajrAlarmStatus.refresh()
            if PrayerLiveActivities.supported {
                let on = ActivityAuthorizationInfo().areActivitiesEnabled
                if liveActivitiesOn != on { liveActivitiesOn = on }
            }
        }
        .infoModal(isPresented: $isAppearanceInfoVisible, title: "Appearance", symbol: "circle.lefthalf.filled") {
            AppearanceInfo()
        }
        .infoModal(isPresented: $isTimesInfoVisible, title: "Prayer Times", symbol: "clock") {
            PrayerTimesInfo(qibla: qiblaSensitivity)
        }
        // Reminders' ⓘ: a floating card for the side showing (owner: tooltips as a frosted modal).
        .infoModal(isPresented: $isNotifPopupVisible,
                   title: shownReminderTab == ReminderSwitch.liveActivities ? "Live Activities"
                        : shownReminderTab == ReminderSwitch.fajrAlarm ? "Fajr Alarm" : "Notifications",
                   symbol: shownReminderTab == ReminderSwitch.liveActivities ? "platter.filled.bottom.iphone"
                        : shownReminderTab == ReminderSwitch.fajrAlarm ? "alarm" : "bell") {
            if shownReminderTab == ReminderSwitch.liveActivities {
                LiveActivityInfo()
            } else if shownReminderTab == ReminderSwitch.fajrAlarm {
                FajrAlarmInfo()
            } else {
                NotificationDropdownInfo()
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showLiveActivitySetup) { LiveActivitySetupPreview() }
        .sheet(isPresented: $showLATuner) { LATunerView() }
        #endif
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
            // `-demoSneakPeek <0…2>` (with -demoSettings): that sneak-peek item's sheet (screenshots).
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
            Image(systemName: mode == 0 ? "sun.max.fill" : mode == 1 ? "moon.fill" : mode == 3 ? "iphone" : "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.green)
            Text(mode == 0 ? "Light mode" : mode == 1 ? "Dark mode" : mode == 3 ? "System · follows your iPhone" : "Sun · light after Fajr, dark at Maghrib")
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
                ForEach([0, 1, 2, 3], id: \.self) { mode in
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
                let wasOn = notifIsOn, wasNudge = nudgeIsOn
                defer { TourRuntime.shared.bellTapped(prayerName, wasOn: wasOn, wasNudge: wasNudge) }   // the tour puts it back
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
                        .frame(height: dots ? 22 : nil)   // Live Activities' columns match it

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
    /// The preview's setting: the row last tapped (Nudge to begin, as setup's page opens).
    @State private var shown = 2

    /// A small version of setup's notifications page (owner: "baby versions of their onboarding pages"): its line, its
    /// preview (Asr), and Off / Start / Nudge, each playing in the preview when tapped.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Not just when it starts: if you haven’t prayed, we’ll nudge you at halfway and 30 minutes left.")
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScaledToFit { NotificationDemo(prayer: "Asr", state: shown) }
            VStack(spacing: 2) {
                choice(0, symbol: "bell.slash.fill", title: "Off", text: "No notifications for this prayer.")
                choice(1, symbol: "bell.fill", title: "Start", text: "One when the prayer starts.")
                // What NotificationScheduler sends: Mid = halfway through the window, End = 30 min before it ends.
                choice(2, symbol: "bell.badge.fill", title: "Nudge",
                       text: "If unmarked, one halfway through and another when 30 minutes left.")
            }
            if shortOnNudge {
                InfoModalRow(symbol: "circle.dotted", title: "Short prayers",
                             text: "Fajr and Maghrib are usually too short for a halfway nudge.")
                    .padding(.horizontal, 8)   // in the choices' column
            }
            Text("Tap a prayer's bell to change it.")
                .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private func choice(_ state: Int, symbol: String, title: String, text: String) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            withAnimation(.easeInOut(duration: 0.2)) { shown = state }
        } label: {
            InfoModalRow(symbol: symbol, title: title, text: text)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.sage.opacity(shown == state ? 0.14 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(shown == state ? .isSelected : [])
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


/// Reminders' Fajr Alarm side (owner, 2026-10-12: "put fajr alarm in reminders tab switcher"): refused in iOS Settings →
/// the warning row and its way back; else a status row with the switch, and while on the rule on one line (− / + minutes,
/// before / after, start / end) with the proof under it — the alarm and Fajr's own time, the gap between them (decision
/// fajr-tab-height C3: about the other two sides' height; the wheels made it twice as tall). A change is saved and
/// re-planned a beat after it.
struct AlarmSettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    
    // Local state to manage alert presentation
    @State private var isShowingShortcutAlert: Bool = false
    
    
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
    @State private var alarmKitRefused = false
    
    /// The side's alerts and watchers, on its first row (a real one): on the Group they made an empty, zero-height row
    /// in the List — the hairline under the switch (owner: "a bug … when i first made the fajr alarm").
    private func hooked<V: View>(_ row: V) -> some View {
        row
        .alert("Alarms are off for shukr", isPresented: $alarmKitRefused) {
            Button("Open Settings", action: SettingsLinks.app)
            Button("Not now", role: .cancel) {}
            } message: {
            Text("To set your Fajr alarm, allow shukr to schedule alarms in Settings.")
            }
            // Before iOS 26.1: the first switch-on says the Shortcut is needed.
            .alert("Shortcut Required", isPresented: $isShowingShortcutAlert) {
            Button("Get Shortcut") {
                if let shortcutURL { UIApplication.shared.open(shortcutURL) }
            }
            Button("Cancel", role: .cancel) {
                didShowAlarmSetupAlert = false
                alarmEnabled = false
            }
            } message: {
            Text("Your iPhone needs iOS 26.1 for shukr to set this alarm itself. Until then, a Shortcut sets it each night: tap “Get Shortcut”, then follow the steps under the alarm.")
            }
            // The wheels stopped: the row's words and the alarms ahead follow (no Save any more).
            .onChange(of: ruleKey) { _, _ in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                saveRule()
            }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { status.refresh() } }
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
    }

    /// As the other two sides open (owner, decision fajr-tab-height C3): the state in a line, its switch on the right.
    private var statusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "alarm")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(alarmEnabled ? Color(.systemGreen) : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(alarmEnabled ? "Fajr alarm is on" : "Fajr alarm is off").font(.system(.body, design: .rounded))
                Text(alarmEnabled ? "Every morning, moving with Fajr" : "Turn it on to wake up for Fajr")
                    .font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Fajr alarm", isOn: Binding(
                get: { alarmEnabled },
                set: { newValue in
                    withAnimation { alarmEnabled = newValue }
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
                            status.refresh()
                        }
                        return
                    }
                    if newValue && !didShowAlarmSetupAlert {
                        isShowingShortcutAlert = true
                        didShowAlarmSetupAlert = true
                    }
                }
            )).labelsHidden()
        }
        .padding(.vertical, 2)
    }

    /// The rule on one line (decision fajr-tab-height C3): the minutes with − / +, before / after and start / end as small
    /// menus; under it, in the same row, the proof (owner: "showing the calculated time as well as the Fajr time, so someone
    /// can double check"): the alarm and Fajr's own time with the gap the rule makes between them.
    private var ruleControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                minutesStepper
                Menu {
                    Picker("Before or after", selection: $alarmIsBefore) {
                        Text("before").tag(true)
                        if alarmIsFajr { Text("after").tag(false) }
                    }
                } label: { pill(alarmIsBefore ? "before" : "after") }
                .tint(.primary)   // our pill, not the accent's blue
                Menu {
                    // The start / end of Fajr (stored as alarmIsFajr true / false).
                    Picker("Start or end of Fajr", selection: $alarmIsFajr) {
                        Text("Fajr starts").tag(true)
                        if alarmIsBefore { Text("Fajr ends").tag(false) }
                    }
                } label: { pill(alarmIsFajr ? "Fajr starts" : "Fajr ends") }
                .tint(.primary)
            }
            .frame(maxWidth: .infinity)   // centred in the card (owner: equal room both sides)
            .font(.system(.subheadline, design: .rounded))
            timeline
        }
        .padding(.bottom, 4)
        // Close under the switch (owner: less room between them); the row's sides as the card's other rows.
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
    }

    /// 5-minute steps (owner, 2026-09-29); before the end of Fajr from 10 (FajrAlarmRule).
    private var minutesStepper: some View {
        let steps = FajrAlarmRule.minutes(isFajr: alarmIsFajr)
        let i = steps.firstIndex(of: alarmOffsetMinutes) ?? 0
        return HStack(spacing: 0) {
            Button { if i > 0 { alarmOffsetMinutes = steps[i - 1]; triggerSomeVibration(type: .light) } } label: {
                Image(systemName: "minus").frame(width: 36, height: 34).contentShape(Rectangle())
            }
            .disabled(i == 0)
            Text("\(alarmOffsetMinutes) min")
                .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 56)
                .contentTransition(.numericText())
            Button { if i < steps.count - 1 { alarmOffsetMinutes = steps[i + 1]; triggerSomeVibration(type: .light) } } label: {
                Image(systemName: "plus").frame(width: 36, height: 34).contentShape(Rectangle())
            }
            .disabled(i >= steps.count - 1)
        }
        .buttonStyle(.borderless)   // each its own target in a List row
        .foregroundStyle(.primary)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .animation(.snappy(duration: 0.2), value: alarmOffsetMinutes)
    }

    private func pill(_ word: String) -> some View {
        HStack(spacing: 3) {
            Text(word)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .foregroundStyle(.primary)
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(height: 34)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    /// The alarm, the gap, then Fajr (or Fajr first when it rings after the start).
    private var timeline: some View {
        let ref = alarmIsFajr ? nextFajrTime : nextSunriseTime
        let alarm = ref.addingTimeInterval((alarmIsBefore ? -1 : 1) * Double(alarmOffsetMinutes) * 60)
        let alarmEnd = (time: shortTimePM(alarm), word: "Alarm", green: true)
        let fajrEnd = (time: shortTimePM(ref), word: alarmIsFajr ? "Fajr starts" : "Fajr ends", green: false)
        let (first, last) = alarmIsBefore || alarmOffsetMinutes == 0 ? (alarmEnd, fajrEnd) : (fajrEnd, alarmEnd)
        func end(_ e: (time: String, word: String, green: Bool), leading: Bool) -> some View {
            VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
                Text(e.time).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(e.green ? Color.green : .primary)   // Settings' green (owner, note C9FB37FF)
                    .contentTransition(.numericText())
                Text(e.word).font(.caption2).foregroundStyle(.secondary)
            }
        }
        return HStack(spacing: 8) {
            end(first, leading: true)
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 2)
                Text(alarmOffsetMinutes == 0 ? "same time" : "\(alarmOffsetMinutes) min")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(Color(.secondarySystemGroupedBackground))
                    .contentTransition(.numericText())
            }
            end(last, leading: false)
        }
        .animation(.snappy(duration: 0.25), value: ruleKey)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alarm \(shortTimePM(alarm)), \(alarmOffsetMinutes) minutes \(alarmIsBefore ? "before" : "after") Fajr \(alarmIsFajr ? "starts" : "ends") at \(shortTimePM(ref))")
    }

    /// The row's words for the Shortcut (alarmTimeSetFor / alarmDescription) and the alarms ahead.
    private func saveRule() {
        if let calc = try? PrayerUtils.calculateAlarmDescription() {
            if alarmTimeSetFor != shortTimePM(calc.time) { alarmTimeSetFor = shortTimePM(calc.time) }
            if alarmDescription != calc.description { alarmDescription = calc.description }
        }
        Task { await FajrAlarms.plan(reason: "rule changed"); status.refresh() }
    }

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
    
    // ------------------------------------------
    // MARK: - Body
    // ------------------------------------------
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = FajrAlarmStatus.shared
    @State private var saveTask: Task<Void, Never>?

    /// The rule in words for the row: "20 min before Fajr starts", "When Fajr ends".
    private var ruleText: String {
        let edge = alarmIsFajr ? "starts" : "ends"
        return alarmOffsetMinutes == 0 ? "When Fajr \(edge)" : "\(alarmOffsetMinutes) min \(alarmIsBefore ? "before" : "after") Fajr \(edge)"
    }
    private var ruleKey: [Int] { [alarmOffsetMinutes, alarmIsBefore ? 1 : 0, alarmIsFajr ? 1 : 0] }

    /// Before iOS 26.1 shukr can't set an alarm itself: a Shortcut does, each night (the owner's flow from the original
    /// app — the alert on first switch-on, three steps, the link; setup only says it needs the update).
    private var shortcutSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your iPhone needs iOS 26.1 for shukr to set this alarm itself. Until you update, a Shortcut sets it each night:")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            shortcutStep(1, "Get the Shortcut below and add it")
            shortcutStep(2, "In Shortcuts, open Automation and tap +")
            shortcutStep(3, "Choose Time of Day: 10:00 PM, Daily, Run Immediately, then pick “Shukr - Auto Fajr Alarm”")
            Button {
                didShowAlarmSetupAlert = true
                if let shortcutURL { UIApplication.shared.open(shortcutURL) }
            } label: {
                Label("Get the Shortcut", systemImage: "square.and.arrow.down")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
    private func shortcutStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color.sage)
                .frame(width: 20, height: 20).background(Circle().fill(Color.sage.opacity(0.15)))
            Text(text).font(.system(.subheadline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        Group {
            if FajrAlarms.supported && status.allowed != true {
                // Not allowed yet (asks, and turns the alarm on) or refused in iOS Settings (the way back there): as the
                // notifications side says each.
                let refused = status.allowed == false
                hooked(HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(refused ? "Alarms are off" : "Alarms aren’t allowed yet")
                            .font(.system(.body, design: .rounded)).foregroundStyle(.primary)
                        Text(refused ? "Off for shukr in iOS Settings" : "Allow them so shukr can wake you for Fajr")
                            .font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2))
                Button {
                    guard !refused else { SettingsLinks.app(); return }
                    Task { @MainActor in
                        if await FajrAlarms.enable() {
                            withAnimation { alarmEnabled = true }   // allowed: on, and its rule shows
                        } else {
                            alarmKitRefused = true
                        }
                        status.refresh()
                    }
                } label: {
                    Text(refused ? "Turn on alarms" : "Allow alarms")
                        .font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(Color.sage)
                }
            } else {
                hooked(statusRow)
                    // No line between the switch and its rule (owner): painted in the card's colour, not hidden — a hidden
                    // separator left a hairline seam of the page (see the Reminders switch).
                    .listRowSeparatorTint(alarmEnabled ? Color(.secondarySystemGroupedBackground) : nil)
                if alarmEnabled {
                    ruleControls
                    if !FajrAlarms.supported { shortcutSteps }
                    // (No "Let shukr set it" row — owner: only someone who set it up on the Shortcut before iOS 26.1 ever saw
                    // it, and switching the alarm off and on does the same.)
                    // (Alarm check is the card's last line now — "Next …" and its chevron, as on the notifications side.)
                }
            }
        }
    }


}


/// AlarmKit's answer and how far ahead it's set, for the Fajr Alarm side, its dot on the switch and the line under it.
@MainActor @Observable final class FajrAlarmStatus {
    static let shared = FajrAlarmStatus()
    private(set) var allowed: Bool? = FajrAlarmStatus.readAllowed
    private(set) var through: Date? = FajrAlarms.scheduledThrough
    /// The next time it rings (from the rule, as the alarms are set).
    private(set) var next: Date? = FajrAlarms.dates(days: 2).first?.alarm
    /// Fajr alarms set ahead (test alarms left out).
    private(set) var count = FajrAlarmStatus.heldCount
    private static var heldCount: Int { FajrAlarms.scheduled().filter { !$0.test && ($0.date ?? .distantPast) > Date() }.count }
    /// DEBUG `-demoFajrAlarmAllowed`: reads as allowed (the simulator's alarms are refused; screenshots of the on side).
    private static var readAllowed: Bool? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoFajrAlarmAllowed") { return true }
        #endif
        return FajrAlarms.allowed
    }
    /// iOS has spoken through its update stream: that answer stands (a plain read could be the stale one).
    @ObservationIgnored private var heardFromIOS = false
    func refresh() {
        let t = FajrAlarms.scheduledThrough
        if through != t { through = t }
        let n = FajrAlarms.dates(days: 2).first?.alarm
        if next != n { next = n }
        let c = Self.heldCount
        if count != c { count = c }
        guard !heardFromIOS else { return }
        let a = Self.readAllowed
        if allowed != a { allowed = a }
    }
    /// One watcher for the app's life: iOS's own updates, the moment the answer changes.
    private init() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-demoFajrAlarmAllowed") else { return }
        #endif
        FajrAlarms.watchAuthorization { [weak self] answer in
            guard let self else { return }
            self.heardFromIOS = true
            if self.allowed != answer { self.allowed = answer }
            let t = FajrAlarms.scheduledThrough
            if self.through != t { self.through = t }
        }
    }
    /// Not allowed yet, or refused in iOS Settings (the switch's orange dot — owner: "the permission was never given
    /// or it was turned off, but we're not putting a badge on that"), as notifications count "not allowed yet".
    var needsYou: Bool { FajrAlarms.supported && allowed != true }
}

/// Reminders' ⓘ on the Fajr Alarm side: iOS 26.1+ a small version of setup's alarm page; older, the Shortcut's steps.
struct FajrAlarmInfo: View {
    @AppStorage("alarmOffsetMinutes", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmOffsetMinutes: Int = 0
    @AppStorage("alarmIsBefore", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsBefore: Bool = true
    @AppStorage("alarmIsFajr", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsFajr: Bool = true
    private var shortcutURL: URL? { URL(string: "https://www.icloud.com/shortcuts/6ebcfeb12813483992687461d027fd14") }

    var body: some View { alarmInfoView }

    // ------------------------------------------
    // MARK: - Info Section
    // ------------------------------------------
    
    /// iOS 26.1+: how shukr's own alarm works; older: the Shortcut steps.
    @ViewBuilder
    private var alarmInfoView: some View {
        if FajrAlarms.supported {
            // A small version of setup's Fajr alarm page (owner): its line, the ringing alarm over this rule's time
            // through the year, then the rest said shorter so it fits a 6.1" phone.
            VStack(alignment: .leading, spacing: 14) {
                Text("Set it once. It moves with Fajr every day, so there’s nothing to do before bed.")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScaledToFit {
                    AlarmDemo(days: AlarmDemo.upcoming(offset: alarmOffsetMinutes, isBefore: alarmIsBefore, isFajr: alarmIsFajr),
                              isFajr: alarmIsFajr,
                              rule: AlarmDemo.ruleWords(offset: alarmOffsetMinutes, isBefore: alarmIsBefore, isFajr: alarmIsFajr))
                }
                InfoModalRow(symbol: "alarm", title: "A real alarm",
                             text: "It rings even on silent or in a Focus, and on a paired Apple Watch. Snooze rings it again in \(FajrAlarms.snoozeMinutes) minutes.")
                InfoModalRow(symbol: "clock.arrow.circlepath", title: "It tops itself up",
                             text: "Stopping it, or opening shukr, sets the next days.")
                InfoModalRow(symbol: "eye", title: "Not in the Clock app",
                             text: "Alarms an app sets aren't in Clock's list. When it rings, \"shukr\" shows under the title.")
                InfoModalRow(symbol: "square.stack.3d.up.slash", title: "Had the Shortcut?",
                             text: "It no longer makes an alarm, so there's no need to delete it.")
            }
        } else {
            shortcutInfoView
        }
    }


    /// A quick informational view about how to use the alarm feature and set up the shortcuts.
    @ViewBuilder
    private var shortcutInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
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


import ActivityKit

/// Settings → Live Activities (owner, 2026-10-11: "keep this setting different from the notifications … turn it on or
/// off for live activities for each prayer"). Like Notifications (owner: "keep it consistent"): a status row in
/// NotificationHealthRows' look — on, with how many windows are waiting and the next; or off for shukr in iOS, with the
/// way back — then, while on, the five columns, each the prayer's own symbol (black = its window shows, grey = not).
/// iOS 26+ only (scheduled starts); the section isn't shown before.
/// Settings → Tours → Take the zikr tour again (owner): the Zikr tab locked again as a new person sees it (ZikrLock), and
/// the pager on it, where its lock page starts the tour. Its own view, so Settings' big Form never reads shared state.
struct ZikrTourAgainRow: View {
    @Environment(SharedStateClass.self) private var sharedState
    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            // Replayed, never locked again (owner): on the Zikr page first, so the lock's page arrives there.
            Task { @MainActor in
                _ = await sharedState.navigate(to: .zikr)
                ZikrLock.shared.replay()
            }
        } label: {
            Label {
                Text("Take the zikr tour again")
            } icon: {
                Image(systemName: "hands.and.sparkles").foregroundStyle(Color(.label))
            }
        }
        .tint(Color(.label))
    }
}

/// Settings → Appearance → Icon (owner: "lets them choose the light or the dark icon … just call it icon"; then "make it
/// be its own page like how live activities is … show a graphic"): System (the main AppIcon — iOS picks light or dark
/// with the phone; "System", as the other pickers say), Light or Dark always (the alternate sets AppIcon-Light /
/// AppIcon-Dark: one image each, no dark appearance, plus the T3 tinted; ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
/// iOS shows its own "You have changed the icon" alert.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var detail: String {
        switch self {
        case .system: "Light or dark with your iPhone."
        case .light: "Always the light icon."
        case .dark: "Always the dark icon."
        }
    }
    /// The alternate icon's name; nil = the main icon.
    var iconName: String? {
        switch self {
        case .system: nil
        case .light: "AppIcon-Light"
        case .dark: "AppIcon-Dark"
        }
    }
    static var current: AppIconChoice {
        allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .system
    }
    /// The look pages' choice rows (Icon, Card look): tighter than a Form's default (owner: "way too big").
    static let rowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

    /// A pick made on the Icon page is set when the page closes; if the app was closed from the page instead, it waits
    /// here and is set at the next launch (owner: "handle the close-app case").
    static let pendingKey = "appIcon.pending"
    private static var launchChecked = false
    static func applyPendingAtLaunch() {
        guard !launchChecked else { return }
        launchChecked = true
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        guard let c = AppIconChoice(rawValue: raw), c != current, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(c.iconName) { _ in
            Task { @MainActor in AppIconState.shared.refresh() }
        }
    }
}

/// What the Icon row shows, read again whenever the icon may have changed (the row is built at launch, before a pending
/// pick is set, and Settings stays alive behind the pager).
@MainActor @Observable final class AppIconState {
    static let shared = AppIconState()
    private(set) var choice = AppIconChoice.current
    func refresh() { choice = AppIconChoice.current }
    func show(_ c: AppIconChoice) { choice = c }
}

/// The Appearance row: "Icon" and the pick, pushing the page (as Live Activity card does).
struct AppIconRow: View {
    private var choice: AppIconChoice { AppIconState.shared.choice }
    var body: some View {
        NavigationLink {
            AppIconPage { AppIconState.shared.show($0) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "app").frame(width: 24)
                Text("Icon")
                Spacer(minLength: 8)
                Text(choice.title).foregroundStyle(.secondary)
            }
        }
        .onAppear { AppIconState.shared.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            AppIconState.shared.refresh()
        }
    }
}

/// The page: the three icons side by side, the pick in the middle and full size, then the three choices as a list.
/// Picking slides the row along (owner: the old picture swapped only the middle icon between two blanks — "looks like
/// there's two"). Nothing changes on the phone until the page closes (owner: "see all the options first"): only then
/// is the icon set, so iOS's "You have changed the icon" alert comes once, on the way out.
struct AppIconPage: View {
    var picked: (AppIconChoice) -> Void = { _ in }
    @State private var choice = AppIconChoice.current
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Section {
                AppIconCarousel(choice: choice, scheme: scheme) { pick($0) }
                    .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(AppIconChoice.allCases) { option in
                    Button {
                        pick(option)
                    } label: {
                        HStack(spacing: 14) {
                            AppIconThumb(choice: option, scheme: scheme)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == choice {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.sage)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(AppIconChoice.rowInsets)
                }
            } footer: {
                Text("A tinted Home Screen keeps the tinted icon whichever you pick.")
            }
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { choice = AppIconChoice.current }
        .onDisappear(perform: apply)
    }

    private func pick(_ c: AppIconChoice) {
        guard c != choice else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { choice = c }
        UISelectionFeedbackGenerator().selectionChanged()
        // Kept until it's set, in case the app is closed from this page.
        if c == AppIconChoice.current { UserDefaults.standard.removeObject(forKey: AppIconChoice.pendingKey) }
        else { UserDefaults.standard.set(c.rawValue, forKey: AppIconChoice.pendingKey) }
    }

    /// On the way out: the pick becomes the icon (iOS's alert then shows over Settings), and the row says so.
    private func apply() {
        UserDefaults.standard.removeObject(forKey: AppIconChoice.pendingKey)
        let c = choice, before = AppIconChoice.current
        guard c != before, UIApplication.shared.supportsAlternateIcons else { return }
        picked(c)
        UIApplication.shared.setAlternateIconName(c.iconName) { error in
            guard error != nil else { return }
            Task { @MainActor in picked(before) }
        }
    }
}

/// The three icons in a row on a soft wallpaper that follows the pick (light behind the light icon, dark behind the
/// dark; System, the phone's own): the picked one centred and full size, the others smaller and faded beside it, the
/// row sliding to the pick. A tap on a side icon picks it.
private struct AppIconCarousel: View {
    let choice: AppIconChoice
    let scheme: ColorScheme
    let pick: (AppIconChoice) -> Void
    private let size: CGFloat = 76
    private let step: CGFloat = 112

    private var dark: Bool {
        switch choice {
        case .system: scheme == .dark
        case .light: false
        case .dark: true
        }
    }

    var body: some View {
        let index = CGFloat(AppIconChoice.allCases.firstIndex(of: choice) ?? 0)
        ZStack {
            // Two wallpapers, faded between (a gradient's colours don't animate).
            LinearGradient(colors: [Color(red: 0.80, green: 0.87, blue: 0.83), Color(red: 0.62, green: 0.74, blue: 0.68)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(dark ? 1 : 0)
            HStack(spacing: 0) {
                ForEach(AppIconChoice.allCases) { c in
                    let on = c == choice
                    Button { pick(c) } label: {
                        VStack(spacing: 8) {
                            AppIconThumb(choice: c, scheme: scheme, corner: size * 0.225)
                                .frame(width: size, height: size)
                                .shadow(color: .black.opacity(dark ? 0.45 : 0.16), radius: on ? 8 : 4, y: on ? 4 : 2)
                                .scaleEffect(on ? 1 : 0.68)
                            Text(c.title)
                                .font(.system(size: 13, weight: on ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(dark ? Color.white : .black.opacity(0.75))
                                .offset(y: on ? 0 : -10)
                        }
                        .opacity(on ? 1 : 0.5)
                        .frame(width: step)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(c.title) icon")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .offset(x: (1 - index) * step)
            .padding(.top, 18)
        }
        .frame(height: 200)
        .clipped()
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(choice.title).fontWeight(.semibold)
                Text("·")
                Text("Home Screen")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle((dark ? Color.white : .black).opacity(0.7))
            .contentTransition(.opacity)
            .padding(.leading, 18).padding(.top, 14)
        }
    }
}

/// The small icon beside each choice: System half light, half dark on the diagonal.
private struct AppIconThumb: View {
    let choice: AppIconChoice
    let scheme: ColorScheme
    var corner: CGFloat = 8.5
    var body: some View {
        Group {
            switch choice {
            case .light: Image("IconPreviewLight").resizable()
            case .dark: Image("IconPreviewDark").resizable()
            case .system:
                ZStack {
                    Image("IconPreviewDark").resizable()
                    Image("IconPreviewLight").resizable().mask(DiagonalHalf())
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
    /// The top-left half of a square, cut on the diagonal.
    private struct DiagonalHalf: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            }
        }
    }
}

/// Reminders' switch (owner, decision settings-alerts E): iOS's own segmented control (owner: "so it feels right and
/// familiar"; a hand-made one didn't take taps in its List row), with a small orange dot laid over the end of a side's name
/// when something there is wrong, so it's found from the other side.
struct ReminderSwitch: View {
    static let notifications = "notifications", liveActivities = "liveActivities", fajrAlarm = "fajrAlarm"
    /// Leaving the app puts Settings → Reminders back on Notifications for the next visit (owner: on leaving the app,
    /// not the page). Not during the tour, which switches it itself. Written only on change (a bound @AppStorage).
    static func resetWhenLeaving() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard !TourRuntime.shared.active,
                      UserDefaults.standard.string(forKey: "settings.remindersTab") ?? notifications != notifications else { return }
                UserDefaults.standard.set(notifications, forKey: "settings.remindersTab")
            }
        }
    }
    struct Side { let id: String; let title: String; let needsYou: Bool }
    @Binding var tab: String
    let sides: [Side]

    /// The system's segmented control (owner: "real liquid glass that does the animation"): on iOS 26 its picked segment
    /// turns into a Liquid Glass bubble you can press and drag between sides — a hand-made switch can't follow the finger.
    var body: some View {
        Picker("Reminders", selection: $tab.animation(.snappy(duration: 0.3))) {
            ForEach(sides, id: \.id) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
        // The control can't hold a badge: each segment carries an invisible copy of its title with the dot at its corner.
        .overlay {
            HStack(spacing: 0) {
                ForEach(sides, id: \.id) { badge($0.title, $0.needsYou) }
            }
            .allowsHitTesting(false)
        }
        .accessibilityValue(sides.filter(\.needsYou).map { "\($0.title) needs attention" }.joined(separator: ", "))
    }

    private func badge(_ title: String, _ needsYou: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .hidden()
            .overlay(alignment: .topTrailing) {
                if needsYou {
                    Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: 9, y: -3)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// Appearance's ⓘ (owner): setup's three swatches — a tap picks, as the madhab tiles do in Prayer Times' — then what each
/// look means, the Live Activity card's, and the widgets'.
struct AppearanceInfo: View {
    @AppStorage("modeToggleNew") private var mode = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach([(0, "Light"), (1, "Dark"), (2, "Sun")], id: \.0) { tag, title in
                    Button {
                        guard mode != tag else { return }
                        withAnimation(.easeInOut(duration: 0.3)) { mode = tag }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 6) {
                            AppearanceSwatch(tag: tag)
                                .frame(height: 84)
                                .overlay(RoundedRectangle(cornerRadius: 18)
                                    .stroke(mode == tag ? Color.sage : Color.secondary.opacity(0.25), lineWidth: mode == tag ? 2 : 1))
                            Text(title).font(.system(.subheadline, design: .rounded, weight: mode == tag ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == tag ? .isSelected : [])
                }
            }
            InfoModalRow(symbol: "iphone", title: "System", text: "Follows your iPhone's light or dark mode.")
            InfoModalRow(symbol: "sun.max", title: "Light and Dark", text: "The app stays that way all day.")
            InfoModalRow(symbol: "circle.lefthalf.filled", title: "Sun",
                         text: "Light after Fajr, dark at Maghrib.")
            InfoModalRow(symbol: "platter.filled.bottom.iphone", title: "Live Activity card",
                         text: "Its own look on your Lock Screen. System follows your iPhone; Sun is light after Fajr, dark at Maghrib.")
            InfoModalRow(symbol: "square.grid.2x2", title: "Prayers widget",
                         text: "Every Prayers widget on your Home Screen. System follows your iPhone; Sun is light after Fajr, dark at Maghrib. Other widgets and the Lock Screen follow your iPhone.")
        }
    }
}

/// Prayer Times' ⓘ (owner: the setup explains the method and madhab well and Settings lost it): what a method is, the
/// setup's shadow drawings with today's Asr for each madhab, and what the qibla's ± means.
struct PrayerTimesInfo: View {
    // The same keys as the Prayer Times rows: a tap on a madhab picks it (owner), and Settings' own onChange re-plans.
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var method: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var school: Int = 0
    let qibla: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoModalRow(symbol: "angle", title: "Method",
                         text: "Fajr and Isha are timed by how far the sun is below the horizon. Each method uses its own angles, so pick the one your masjid uses. Automatic follows the country you're in.")
            VStack(alignment: .leading, spacing: 10) {
                InfoModalRow(symbol: "book.closed", title: "Madhab",
                             text: "It only moves Asr: Asr begins when a post's shadow reaches its own length, or twice its length. Tap yours.")
                HStack(spacing: 10) {
                    madhab("Shafi'i", lengths: 1, school: 0)
                    madhab("Hanafi", lengths: 2, school: 1)
                }
            }
            InfoModalRow(symbol: "location.north.line", title: "Qibla Accuracy",
                         text: "How close the arrow must point to count as facing the qibla: ± \(qibla.formatted(.number.precision(.fractionLength(0...1))))° means up to \(qibla.formatted(.number.precision(.fractionLength(0...1))))° either side. Lower is stricter.")
        }
    }

    private func madhab(_ name: String, lengths: CGFloat, school s: Int) -> some View {
        let picked = school == s
        let asr = todaysTimes(method: method, school: s)?.asr
        return Button {
            guard school != s else { return }
            withAnimation(.snappy(duration: 0.25)) { school = s }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: { VStack(spacing: 3) {
            ShadowSketch(lengths: lengths, picked: picked).frame(height: 40)
            Text(name).font(.system(.subheadline, design: .rounded, weight: picked ? .semibold : .regular))
            Text(asr.map { "Asr \($0.formatted(date: .omitted, time: .shortened))" } ?? "Asr")
                .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(picked ? Color.sage : .clear, lineWidth: 1.2))
        .overlay(alignment: .topTrailing) {
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(picked ? Color.sage : Color.secondary.opacity(0.4))
                .padding(6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// Reminders' ⓘ on the Live Activities side.
struct LiveActivityInfo: View {
    @State private var copy = LASetupCopy.shared
    /// A small version of setup's Live Activities page (owner): its line, its moving card, and what to know about it.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy[.subtitle])
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScaledToFit { LiveActivityDemo(prayer: "Asr", veil: .none, copy: copy) }
            InfoModalRow(symbol: "checkmark.circle", title: "Mark it there",
                         text: "It counts like marking it in shukr; then the card offers a photo and Tasbih Fatimah.")
            // iOS holds 5 (PrayerLiveActivities) — why "Scheduled through" here only reaches a day or two (owner: say so).
            InfoModalRow(symbol: "clock.arrow.circlepath", title: "Kept coming",
                         text: LASetupCopy.fiveAtATime)
            Text("Tap a prayer to turn its card on or off.")
                .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

/// What iOS holds of shukr's cards, for the Live Activities side and the line under its card.
@MainActor @Observable final class LiveActivityStatus {
    static let shared = LiveActivityStatus()
    private(set) var held = 0
    private(set) var next: Date?
    private(set) var through: Date?
    func refresh() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))   // a toggle's re-plan first
            let s = PrayerLiveActivities.status()
            if held != s.held { held = s.held }
            if next != s.next { next = s.next }
            if through != s.through { through = s.through }
        }
    }
}

/// Settings → Reminders → Live Activities → the card's last line: Your Live Activities, in Your Notifications' shape
/// (owner, 2026-10-14): on / off and what's waiting, iOS's five as a bar, why only five and how it tops itself up, then
/// every prayer card iOS holds for shukr, by day — its window, and whether it's on now or still to come.
struct ScheduledLiveActivitiesPage: View {
    struct Card: Identifiable {
        let id: String
        let name: String
        let start: Date
        let end: Date
        let marked: Bool
        func state(_ now: Date) -> State {
            marked ? .marked : now >= start && now < end ? .onNow : now >= end ? .ended : .waiting
        }
    }
    enum State { case onNow, waiting, marked, ended }
    /// iOS's room for one app's Live Activities.
    static let limit = 5

    @State private var cards: [Card] = []
    @State private var loaded = false
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var why: Why?
    enum Why { case limit, topsUp }

    private var green: Color { Color(.systemGreen) }

    var body: some View {
        List {
            Section {
                statusRow
                slotsBar
                ReminderWhyLink(symbol: "questionmark.circle", title: "Why only \(Self.limit)?") { why = .limit }
                ReminderWhyLink(symbol: "arrow.triangle.2.circlepath", title: "Tops itself up") { why = .topsUp }
            }
            Section {
                if loaded && cards.isEmpty {
                    Text("None waiting right now. Opening shukr sets up the next ones.").foregroundStyle(.secondary)
                }
                ForEach(days, id: \.self) { day in
                    let list = cards.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
                    ReminderDayHeading(title: Self.dayTitle(day), count: "\(list.count) card\(list.count == 1 ? "" : "s")")
                    ForEach(list) { row($0) }
                }
            } header: { Text("Coming up") }
        }
        .reminderPageTitle("Your Live Activities")
        .task { load(); LiveActivityStatus.shared.refresh() }
        .refreshable { load() }
        // Back in Settings, its line counts what this page showed (a card can end in between).
        .onDisappear { LiveActivityStatus.shared.refresh() }
        .infoModal(isPresented: Binding(get: { why == .limit }, set: { if !$0 { why = nil } }),
                   title: "Why only \(Self.limit)?", symbol: "questionmark.circle") {
            ReminderExplainer(head: "iOS lets each app hold \(Self.limit) Live Activities at a time. shukr fills them with your next prayers.", points: [
                .init(big: "Your next prayers", small: "Each prayer you've turned on gets a card, set up ahead to start by itself when its time comes.", symbol: "calendar", warn: false),
                .init(big: "One card per prayer", small: "It runs from the prayer's start to its end, and Isha's until 11:59 PM.", symbol: "platter.filled.bottom.iphone", warn: false),
                .init(big: "Marked cards make room", small: "Once you mark a prayer, its card ends a few seconds later and the next one can take its place.", symbol: "checkmark.circle", warn: false),
                .init(big: "Prayers you've turned off", small: "They don't use a card, so the \(Self.limit) reach further ahead.", symbol: "bell.slash", warn: false),
            ])
        }
        .infoModal(isPresented: Binding(get: { why == .topsUp }, set: { if !$0 { why = nil } }),
                   title: "Tops itself up", symbol: "arrow.triangle.2.circlepath") {
            ReminderExplainer(head: "Your prayer cards keep coming.", points: [
                .init(big: "Opening shukr", small: "Any time you open the app, the free spots fill with your next prayers.", symbol: "iphone", warn: false),
                .init(big: "Marking a prayer", small: "From the card, a widget or the app: its card steps aside and the next one is added.", symbol: "checkmark.circle", warn: false),
                .init(big: "Kept on time", small: "As each card starts, iOS wakes shukr, so the cards still to come keep the right times.", symbol: "arrow.triangle.2.circlepath", warn: false),
                .init(big: "The last card tells you", small: "When it's the last one waiting, it says \u{201C}open shukr to keep prayer cards coming.\u{201D}", symbol: "exclamationmark.bubble", warn: false),
            ])
        }
    }

    /// On (what's waiting, the next, how far) or off in iOS Settings (orange, the way back).
    private var statusRow: some View {
        guard enabled else {
            return ReminderPageStatus(good: false, title: "Live Activities are off", subtitle: "Off for shukr in iOS Settings",
                                      note: "Needs a look", action: SettingsLinks.app)
        }
        let now = Date()
        let next = cards.map(\.start).filter { $0 > now }.min()
        let through = cards.map(\.start).max()
        let onNow = cards.filter { $0.state(now) == .onNow }.count
        let waiting = cards.filter { $0.state(now) == .waiting }.count
        var parts: [String] = []
        if onNow > 0 { parts.append("\(onNow) on now") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if let next { parts.append("next " + Self.when(next)) }
        if let through { parts.append("through " + through.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
        let none = LiveActivityPrefs.prayers.contains(where: LiveActivityPrefs.isOn) ? "None waiting right now" : "No prayers turned on"
        return ReminderPageStatus(good: true, title: "Live Activities are on",
                                  subtitle: cards.isEmpty ? none : parts.joined(separator: " · "))
    }

    /// The five, in parts: on now, still to come, marked (ending), and what's free.
    private var slotsBar: some View {
        let now = Date()
        func n(_ s: State) -> Int { cards.filter { $0.state(now) == s }.count }
        let onNow = n(.onNow), waiting = n(.waiting), marked = n(.marked) + n(.ended)
        let used = min(cards.count, Self.limit)
        let free = max(Self.limit - used, 0)
        return ReminderSlotsBar(caption: "\(used) of \(Self.limit) in use" + (free > 0 ? " · \(free) free" : ""),
                                limit: Self.limit,
                                parts: [.init(count: onNow, color: green, label: "On now"),
                                        .init(count: waiting, color: Color(.systemTeal), label: "Coming up"),
                                        .init(count: marked, color: Color(.systemGray3), label: "Marked")])
    }

    private var days: [Date] {
        var seen: [Date] = []
        for c in cards {
            let d = Calendar.current.startOfDay(for: c.start)
            if !seen.contains(d) { seen.append(d) }
        }
        return seen
    }

    /// Your Notifications' prayer row: the Salah list's grey symbol, the name, its window; the state on the right.
    private func row(_ c: Card) -> some View {
        let state = c.state(Date())
        let word = switch state { case .onNow: "On now"; case .waiting: "Waiting"; case .marked: "Marked"; case .ended: "Ended" }
        return HStack(spacing: 12) {
            Image(systemName: prayerSymbol(c.name)).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                Text("\(c.start.formatted(date: .omitted, time: .shortened)) – \(c.end.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(word)
                .font(.subheadline.weight(state == .onNow ? .semibold : .regular))
                .foregroundStyle(state == .onNow ? green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() {
        if #available(iOS 26.0, *) {
            cards = Activity<PrayerWindowAttributes>.activities
                .filter { $0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale }
                .map { a in
                    let st = a.content.state
                    return Card(id: a.id, name: st.label, start: st.start, end: st.end, marked: st.markedAt != nil)
                }
                .sorted { $0.start < $1.start }
        }
        enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        loaded = true
    }

    /// "4:50 PM" today, else "Thu 5:41 AM".
    private static func when(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Today", "Tomorrow", else "Wed, Oct 14".
    static func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// The Live Activities side alone, in its own Section (DEBUG -laSettingsPreview).
struct LiveActivitySettingsSection: View {
    var body: some View { Section("Live Activities") { LiveActivitySettingsRows(showInfo: false) } }
}

/// Reminders' Live Activities side: its status row (as Notifications'), the five prayers in the bells' layout so a switch
/// between the sides only swaps icons, then Card Appearance.
struct LiveActivitySettingsRows: View {
    /// The section's ⓘ is open: this side's explanation under it.
    let showInfo: Bool
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var status = LiveActivityStatus.shared
    var body: some View {
        Group {
            // On: no row (decision reminders-status-row B) — "Scheduled through …" sits under the card. Off: this row,
            // in the warning style, with its way back.
            if !enabled { statusRow }
            if !enabled {
                Button(action: SettingsLinks.app) {
                    Text("Turn on Live Activities").font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(Color.sage)
                }
            } else {
                HStack {
                    ForEach(Array(LiveActivityPrefs.prayers.enumerated()), id: \.offset) { i, prayer in
                        if i > 0 { Divider() }
                        LiveActivityPrayerCol(prayer: prayer) { refresh() }
                    }
                }
                .padding(.vertical, 4)
                // (The card's look moved to Settings → Appearance — owner, settings-appearance.)
            }
        }
        .task {
            refresh()
            for await on in ActivityAuthorizationInfo().activityEnablementUpdates {
                enabled = on
                if on { PrayerLiveActivities.plan(reason: "Live Activities turned on") }
                refresh()
            }
        }
    }

    private func refresh() { status.refresh() }

    /// Notifications' status row: a light symbol in green (or soft orange), a rounded title, a light detail.
    private var statusRow: some View {
        let title = enabled ? "Live Activities are on" : "Live Activities are off"
        let detail: String = {
            guard enabled else { return "Turned off for shukr in iOS Settings" }
            guard status.held > 0 else {
                return LiveActivityPrefs.prayers.contains(where: LiveActivityPrefs.isOn) ? "None waiting right now" : "No prayers turned on"
            }
            let when = status.next.map { " · next " + $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? ""
            return "\(status.held) waiting\(when)"
        }()
        return HStack(spacing: 14) {
            Image(systemName: enabled ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(enabled ? Color(.systemGreen) : Color.orange.opacity(0.9))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded)).foregroundStyle(.primary)
                Text(detail).font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Settings → Live Activities → Card look (owner, 2026-10-12): the Lock Screen card's own look, apart from the app's —
/// System · Light · Dark · Follows the sun, as the widgets offer — over the setup page's moving card (Frank's
/// `LiveActivityDemo`), which changes as one is picked. Cards already waiting are corrected at once (`plan`).
struct LiveActivityAppearancePage: View {
    /// Called with each pick, for the Settings row (see where it's pushed).
    var picked: (String) -> Void = { _ in }
    @AppStorage(LiveActivityLook.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var raw = LiveActivityLook.system.rawValue
    /// The moving card waits until the page has slid in (owner: "lag when opening"): it starts after the push.
    @State private var started = false
    @Environment(\.colorScheme) private var system
    @State private var copy = LASetupCopy.shared
    /// Follows the sun: which prayer the card shows (Asr light, Maghrib dark).
    @State private var prayer = "Asr"
    private var look: LiveActivityLook { LiveActivityLook(rawValue: raw) ?? .system }
    private var scheme: ColorScheme { look.dark(for: prayer).map { $0 ? .dark : .light } ?? system }

    var body: some View {
        Form {
            Section {
                LiveActivityDemo(prayer: prayer, veil: .none, copy: copy, look: scheme, paused: !started)
                    .animation(.easeInOut(duration: 0.35), value: scheme)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
                if look == .sun {
                    Picker("Prayer", selection: $prayer.animation(.easeInOut(duration: 0.35))) {
                        Text("Asr").tag("Asr")
                        Text("Maghrib").tag("Maghrib")
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                ForEach(LiveActivityLook.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { raw = option.rawValue }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == look {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.sage)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(AppIconChoice.rowInsets)
                }
            } footer: {
                Text("Cards already on your Lock Screen change right away.")
            }
        }
        .navigationTitle("Card look")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: raw) { _, new in
            picked(new)
            PrayerLiveActivities.plan(reason: "card look: \(look.title)")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            started = true
        }
        .onAppear {   // DEBUG `-laLook light|dark|sun|system`: the page opened on one (the sim's taps miss rows)
            #if DEBUG
            if let l = UserDefaults.standard.string(forKey: "laLook"), LiveActivityLook(rawValue: l) != nil { raw = l }
            #endif
        }
    }
}

/// Settings → Appearance → Prayers widget (owner, 2026-10-14: as Live Activity card and Icon do): the real Prayers widget
/// (`RealPrayersWidget`, Explore's preset day) as the preview, changing as one of System · Light · Dark · Sun is picked;
/// every Prayers widget follows at once.
struct PrayersWidgetAppearancePage: View {
    /// Called with each pick, for the Settings row.
    var picked: (String) -> Void = { _ in }
    @AppStorage(WidgetStyle.sharedKey, store: UserDefaults(suiteName: SharedStore.appGroup)) private var raw = WidgetStyle.system.rawValue
    /// Sun: which time the preview shows (day light, after Maghrib dark).
    @State private var night = false
    @Environment(\.colorScheme) private var scheme
    private var style: WidgetStyle { WidgetStyle(rawValue: raw) ?? .system }
    /// What the preview draws: Sun as the time picked shows it.
    private var shown: WidgetStyle { style == .auto ? (night ? .dark : .light) : style }

    var body: some View {
        Form {
            Section {
                RealPrayersWidget(style: shown)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40).padding(.bottom, 18)
                    .animation(.easeInOut(duration: 0.35), value: shown)
                    // What's shown and where, top left — as the Icon and Card look pages label theirs (owner).
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Text(style.title).fontWeight(.semibold)
                            Text("·")
                            Text("Home Screen")
                        }
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle((scheme == .dark ? Color.white : .black).opacity(0.7))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: style)
                        .padding(.leading, 4).padding(.top, 14)
                    }
                    // A wallpaper behind it, as Explore's pictures have (a dark widget on the dark row was lost).
                    .listRowBackground(LinearGradient(colors: scheme == .dark
                        ? [Color(red: 0.17, green: 0.33, blue: 0.25), Color(red: 0.07, green: 0.10, blue: 0.08)]
                        : [Color(red: 0.85, green: 0.92, blue: 0.87), Color(red: 0.93, green: 0.96, blue: 0.94)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                if style == .auto {
                    Picker("Time", selection: $night.animation(.easeInOut(duration: 0.35))) {
                        Text("Asr").tag(false)
                        Text("Maghrib").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                ForEach(WidgetStyle.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { raw = option.rawValue }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == style {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.sage)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(AppIconChoice.rowInsets)
                }
            } footer: {
                Text("Every Prayers widget on your Home Screen changes right away.")
            }
        }
        .navigationTitle("Prayers widget")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: raw) { _, new in
            picked(new)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WidgetStyle {
    /// The page's words (the same as the widget's own picker).
    var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark"; case .auto: "Sun" }
    }
    var detail: String {
        switch self {
        case .system: "Follows your iPhone's light or dark"
        case .light: "Always light"
        case .dark: "Always dark"
        case .auto: "Light after Fajr, dark at Maghrib"
        }
    }
}

/// One prayer: its name, its symbol (black = on, grey = off), "on" / "off" — a tap flips it.
private struct LiveActivityPrayerCol: View {
    let prayer: String
    var changed: () -> Void = {}
    @AppStorage private var on: Bool

    init(prayer: String, changed: @escaping () -> Void = {}) {
        self.prayer = prayer
        self.changed = changed
        _on = AppStorage(wrappedValue: LiveActivityPrefs.onByDefault.contains(prayer), LiveActivityPrefs.key(prayer), store: UserDefaults(suiteName: SharedStore.appGroup))
    }

    var body: some View {
        Button {
            on.toggle()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in PrayerLiveActivities.plan(reason: "Settings: \(prayer) \(on ? "on" : "off")"); changed() }
        } label: {
            VStack {
                Text(prayer)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
                // The bells' place and size (owner: switching sides should be clean): the Lock Screen card, slashed off;
                // no gap for the dots — "on / off" sits where the bells' dots are (owner).
                // As much black as the filled bells when on (owner: hard to tell on from off): a heavier symbol in the
                // label color; off a light grey slash, as the bells' off.
                Image(systemName: on ? "platter.filled.bottom.iphone" : "iphone.slash")
                    .font(.system(size: 20, weight: on ? .bold : .light))
                    .foregroundStyle(on ? Color.primary : Color.gray.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
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

#if DEBUG
/// The Live Activity card's tuner (owner, 2026-10-11: "give me a tuner to adjust the ui layout, gradient, font size,
/// positions … easily labeled … and not hiding the ui so i can see the changes"). The very card the Lock Screen draws
/// (shared views), pinned at the top; its state picked under it; labelled sliders below. Every change is saved to the
/// app group at once; "Show on Lock Screen" redraws the real card and writes the config into la-test.log; "Copy" copies it.
struct LATunerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var t = LATuning.current
    @State private var kind = UserDefaults.standard.integer(forKey: "laTunerState")   // DEBUG -laTunerState N
    /// The card's look in the preview (the real card takes the app's Light / Dark / Auto). DEBUG `-laLight YES`.
    @State private var previewDark = !UserDefaults.standard.bool(forKey: "laLight")
    @State private var base = Date()
    @State private var note = ""

    private let kinds = ["Running", "Last ½ hr", "Marked", "Ended", "Island", "Last card"]

    var body: some View {
        NavigationStack {
            Group { if UserDefaults.standard.bool(forKey: "laLookPage") { LiveActivityAppearancePage() }   // DEBUG -laLookPage
            else if UserDefaults.standard.bool(forKey: "laSettingsPreview") { Form { LiveActivitySettingsSection() } }   // DEBUG -laSettingsPreview
            else if UserDefaults.standard.bool(forKey: "laIslandGallery") { LAIslandGallery(t: t) } else {
            VStack(spacing: 0) {
                preview
                    .frame(height: kind == 4 ? 330 : kind == 5 ? 240 : 210)
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

    private var sample: PrayerWindowAttributes.ContentState {
        let m: Double = 60
        switch kind {
        case 2: return .init(label: "Asr", start: base.addingTimeInterval(-25 * m), end: base.addingTimeInterval(115 * m), symbol: prayerIcon(for: "Asr"), markedAt: base)
        case 3: return .init(label: "Asr", start: base.addingTimeInterval(-145 * m), end: base.addingTimeInterval(-5 * m), symbol: prayerIcon(for: "Asr"))
        case 1 where UserDefaults.standard.object(forKey: "laPreviewLeft") != nil, 4 where UserDefaults.standard.object(forKey: "laPreviewLeft") != nil:   // DEBUG -laPreviewLeft seconds
            return .init(label: "Asr", start: base.addingTimeInterval(-110 * m), end: base.addingTimeInterval(UserDefaults.standard.double(forKey: "laPreviewLeft")), symbol: prayerIcon(for: "Asr"))
        case 1: return .init(label: "Asr", start: base.addingTimeInterval(-110 * m), end: base.addingTimeInterval(20 * m), symbol: prayerIcon(for: "Asr"))
        case 5: return .init(label: "Asr", start: base.addingTimeInterval(-40 * m), end: base.addingTimeInterval(100 * m), symbol: prayerIcon(for: "Asr"), last: true)
        default: return .init(label: "Asr", start: base.addingTimeInterval(-40 * m), end: base.addingTimeInterval(100 * m), symbol: prayerIcon(for: "Asr"))
        }
    }

    @ViewBuilder private var preview: some View {
        let s = sample
        if kind == 4 {
            // The Dynamic Island opened up, on black.
            // Only roughly the island: iOS places the regions round the camera itself (see board island-rules.md).
            // Opened in both states (owner): more than half an hour left, then the last half hour with "27m".
            let later = PrayerWindowAttributes.ContentState(label: "Asr", start: base.addingTimeInterval(-40 * 60), end: base.addingTimeInterval(100 * 60), symbol: prayerIcon(for: "Asr"))
            let soon = PrayerWindowAttributes.ContentState(label: "Asr", start: base.addingTimeInterval(-113 * 60), end: base.addingTimeInterval(27 * 60), symbol: prayerIcon(for: "Asr"))
            VStack(spacing: 10) {
                LAFoldedIsland(state: soon, stale: false, t: t)
                ForEach([later, soon], id: \.end) { st in
                    HStack(alignment: .center, spacing: 12) {
                        LAIslandRingAndName(state: st, ended: false, t: t)
                        Spacer(minLength: 0)
                        LAIslandTrailing(state: st, n: 0, ended: false, t: t)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 10)
        } else {
            LALockCardBody(state: s, n: 0, ended: kind == 3, t: t)
                .environment(\.colorScheme, previewDark ? .dark : .light)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    // MARK: The controls

    @ViewBuilder private var controls: some View {
        Section("Card") {
            Picker("Timed changes", selection: Binding(get: { LAGate.style },
                                                       set: { UserDefaults(suiteName: SharedStore.appGroup)?.set($0, forKey: LAGate.styleKey); t.lineSpacing += 0 })) {
                Text("1 s wipe").tag(0)
                Text("Instant").tag(1)
                Text("Fade (8 steps)").tag(2)
            }
            Picker("Preview look", selection: $previewDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
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
        Section("Ended ring (pick Ended)") {
            row("Dashes", "how many round the ring", \.endedDashCount, 3...24, 1)
            row("Dash length", "share of each step that's dash", \.endedDashShare, 0.1...0.95, 0.05)
            row("Dash brightness", "1 = full grey", \.endedDashOpacity, 0.1...1, 0.05)
            row("Dash width", "at the 90 pt design size", \.endedDashWidth, 0.5...10, 0.5)
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
            row("Folded time size", "\"24m\" on the folded island, last half hour only", \.islandTimeSize, 12...36, 1)
            Picker("Name weight", selection: Binding(get: { t.islandTitleWeight ?? 2 }, set: { t.islandTitleWeight = $0 })) {
                ForEach(LATuning.weightNames.indices, id: \.self) { Text(LATuning.weightNames[$0]).tag($0) }
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
        for a in Activity<PrayerWindowAttributes>.activities where a.activityState == .active || a.activityState == .stale {
            await a.update(a.content)
            n += 1
        }
        PrayerWindowLog.add("tuning applied to \(n) card(s): " + t.json.replacingOccurrences(of: "\n", with: " "))
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

/// (Every build: the setup's Live Activity page draws it too.) The island folded, drawn roughly as iOS does: a black pill with the camera in its middle, our two sides at its ends.
struct LAFoldedIsland: View {
    let state: PrayerWindowAttributes.ContentState
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

#if DEBUG

/// DEBUG -laIslandGallery: the island folded and opened in each state, for screenshots.
struct LAIslandGallery: View {
    let t: LATuning
    private let now = Date()
    private func state(start: Double, end: Double, marked: Bool = false) -> PrayerWindowAttributes.ContentState {
        .init(label: "Asr", start: now.addingTimeInterval(start * 60), end: now.addingTimeInterval(end * 60), symbol: prayerIcon(for: "Asr"),
              markedAt: marked ? now : nil)
    }
    private var rows: [(String, PrayerWindowAttributes.ContentState, Bool)] {
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


/// A header the list scrolls under: iOS 26's `safeAreaBar` (the scroll edge effect softens what passes beneath), a bar
/// material before.
private struct OverListHeader<Header: View>: ViewModifier {
    @ViewBuilder let header: () -> Header
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top) { header().padding(.bottom, 6) }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                header().padding(.bottom, 6).background(.bar)
            }
        }
    }
}
