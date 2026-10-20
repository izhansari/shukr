//
//  TourCopy.swift
//  shukr
//
//  Every word the app tour says, in one place, in the order it's seen (owner, 2026-10-06: "where can I go in the
//  code to change the copy?"). Edit the text between the quotes and build — nothing else needs touching.
//
//  · Lists are one line per item.
//  · A "|" splits a line in two: the welcome's chapters (title | the words under it) and the circle's
//    situations (the question | what the circle shows).
//  · Quotes and apostrophes: use the curly ones (’ “ ”) so they match the rest of the app.
//  · Keep each list's length: the to-dos are counted by position (the first one, the second…), so changing how many
//    there are needs a change in Tour.swift too. Rewording them never does.
//

import Foundation

/// Which tour runs: the new one (show, name, pay off — no intro cards, the map step, the list unfolded first; owner
/// 2026-10-13). The Settings switch to the classic one is gone (owner, 2026-10-14), so it's always the new one; the classic
/// paths are unreached.
enum TourFlow {
    static var v2: Bool { true }
}

enum TourCopy {

    // MARK: Used on every chapter

    static let continueButton = "Continue"
    static let getThere = "Get there"        // the first step of Zikr and Settings
    static let tryIt = "Try it"              // the to-dos step's label
    static func doneCount(_ n: Int) -> String { "\(n) done" }
    /// A chapter's end, in the top panel ("Prayer Circle done").
    static func chapterDone(_ chapter: String) -> String { "\(chapter) done" }
    /// A step's explanation, read once before its strip (TourStrip.swift).
    static let gotIt = "Got it"   // finished steps folded into one line

    // MARK: The welcome (before chapter 1)

    enum Welcome {
        static let title = "Bismillah"
        static var line: String { TourFlow.v2 ? "Your prayer times, your qibla and your record, all on one screen. Let’s take two minutes to look around." : "Let’s take a quick look around." }
        static var chapters: [String] { TourFlow.v2 ? [
            "Prayer Circle|what’s on now, and which way to face",
            "Prayer List|your whole day",
            "Settings|make it yours",
        ] : [
            "Prayer Circle|the prayer that matters now",
            "Prayer List|your whole day",
            "Settings|make it yours",
        ] }
        static var footnote: String { TourFlow.v2 ? "It’s a practice day — nothing here is kept." : "A quick look at each, then you try it. It’s a practice day — nothing here is kept." }
        static let button = "Let’s begin"
        /// The panel's line over the welcome.
        static let panelLabel = "App tour"
    }

    // MARK: 1 · Prayer Circle

    enum Circle {
        static let title = "Prayer Circle"

        static let showsStep = "What it shows"
        static let showsLead = "This is the heart of shukr. It always shows the prayer that matters right now:"
        static let situations = [
            "during a prayer?|the current one",
            "already prayed?|the upcoming one",
            "end of the day?|any you missed",
        ]

        static let coloursStep = "The colors"
        static let coloursLead = "The ring fills as the prayer’s time passes, and its color is the score you’d get if you prayed now:"
        static let colours = [PrayerScoring.Grade.perfect, .onTime, .late].map(\.rawValue)   // green, yellow, red (VoiceOver only now)
        static let playAgain = "Play again"

        static var todos: [String] { TourFlow.v2 ? [
            "Tap the circle to see how long is left",
            "Turn until the arrow points straight up",
            "Turn until the ring around you turns green",   // on the map (→ on the qibla's line opens it)
            "Hold the circle to mark Asr",
        ] : [
            "Tap the circle to flip the time text",
            "Turn until the qibla arrow points up",
            "Hold the circle to mark Asr",
        ] }
        static let noCompass = "No compass here? Skip it"
        /// The qibla's held line when it was skipped (it can't say "you're facing it"); → still opens the map.
        static let qiblaSkippedAfter = "Compasses can be off, so let’s find the qibla on a map."
        /// A line over each to-do in the panel: what it is (owner: "text above it that helps educate them").
        /// The line teaches what the thing is; the to-do under it says what to do — never the same words (owner).
        static var todoLeads: [String] { TourFlow.v2 ? [
            "This circle shows the current prayer: Asr.",
            "The small arrow on the ring points to the Kaaba.",
            "The green line is the true way to the Kaaba, worked out from where you are.",
            "Prayed? Mark it right here.",
        ] : [
            "The ring fills as the prayer's time runs out.",
            "The small arrow on the ring points to the Kaaba.",
            "A marked prayer is scored by how early you prayed.",
        ] }
        /// Once each is done, the panel holds and teaches a little more, then → (owner).
        static var todoAfters: [String] { TourFlow.v2 ? [
            "Tap again to see when it ends. In its last hour it shows the time left by itself.",
            "You’re facing the qibla. Compasses can be off, so let’s check it on a map.",
            "That’s the qibla, whatever your compass says. Your prayers are pinned on this map too, and it finds mosques near you.",
            "Perfect, prayed in the first 30 minutes. See how it moved on to Maghrib? Once you’ve prayed, it moves on to the next one.",
        ] : [
            "Tap it any time. In a prayer's last hour it shows the time left on its own.",
            "Straight up means you're facing the qibla. How strict that is lives in Settings.",
            "First 30 minutes is Perfect, 100. After that the score eases down until the time ends.",
        ] }
        /// The button beside the chapter's name on "What it shows": on to trying it (owner: not "Continue").
        static let tryButton = "Try it"
        static var marked: String { TourFlow.v2 ? "Asr went into your list for today. Swipe up to see it." : "Asr has moved to your prayer list. Let’s look at that next. Swipe up to reveal it." }
    }

    // MARK: 2 · Prayer List

    enum List {
        static let title = "Prayer List"

        static let showsStep = "What it shows"
        static let shows = [
            "your day’s prayers and their times",
            "coming ones greyed, with time until",
            "marked ones show your time and score",
            "marked ones tuck below, one tap away",
        ]

        static let canStep = "What you can do"
        static let can = [
            "complete a prayer, or undo it",
            "edit when and where you prayed",
            "see how well you’re praying today",
        ]

        /// The chapter's one bubble before its to-dos (owner: the two steps' tooltips covered too much of the page).
        static let canLead = "From here you can:"
        static let canNow = [
            "see the full day’s prayer times",
            "mark and edit your prayers",
            "see your performance at a glance",
        ]

        /// A line over each to-do in the panel: what it is.
        static var todoLeads: [String] { TourFlow.v2 ? [
            "Prayers you’ve marked fold away to keep the list short.",
            "Upcoming prayers show when they start.",
            "Every marked prayer keeps its score.",
            "Prayed Fajr earlier than you marked it? Fix it.",
        ] : [
            "Your whole day is here, in order.",
            "Prayers you've marked tuck away to keep it tidy.",
            "Every prayer you mark is scored out of 100.",
            "Marked one at the wrong time? Its time can be fixed.",
        ] }
        static var todoAfters: [String] { TourFlow.v2 ? [
            "Your full day: what you’ve prayed, and what you haven’t yet.",
            "That’s a countdown to when it starts. Tap again for the time.",
            "“Qaza · 40” means it was prayed after its time. Its dot’s color shows it too.",
            "Saved. Fajr counts as Middle now, and your day’s score is updated.",   // Save's own moment; → ends the chapter
        ] : [
            "The times follow your location and calculation method, both in Settings.",
            "Tap “done” again to tuck them back away.",
            "Perfect is 100, Middle 80 or more, Closing 60 or more, Qaza 40.",
            "",   // the chapter's own end follows
        ] }
        static var todos: [String] { TourFlow.v2 ? [
            "Tap “3 done”",
            "Tap Maghrib’s time",
            "Tap Fajr’s time",
            "Hold Fajr",
        ] : [
            "Tap a coming prayer for the time until",
            "Unfold to see all your prayers",
            "Tap a marked prayer for its score",
            "Hold Fajr, move it into the yellow, save",      // only Fajr opens, and saves only in the yellow, until this is done
        ] }
        static let allDone = "That’s your day — all in one list and easy to track."

        // The tip inside the time editor (opened by the last to-do).
        static let editorTitle = "When did you really pray?"
        static var editorLine: String { TourFlow.v2 ? "Drag the color bar or turn the wheel. It’s practice — nothing is kept."
            : "Say you prayed Fajr earlier than you marked it: drag the color bar or turn the wheel into the yellow, then save. It’s practice — nothing is kept." }
        static let editorTodo = "Move it into the yellow, then save"
        /// The editor's to-dos in the top panel (owner: the first ticks as soon as it's in the yellow).
        static let editorTodos = ["Move it into the yellow", "Let go to save"]   // no Save since the bento: a release saves
        /// Held under the first once it's in the yellow (owner: "its own moment"): the score the draft would keep.
        static func editorInYellow(_ score: Int) -> String { "\(PrayerScoring.Grade.onTime.rawValue) · \(score) — that’s the score it’ll keep." }
    }

    // MARK: 3 · Zikr

    enum Zikr {
        static let title = "Zikr"

        static let getThereLead = "Your zikr lives one page over."
        static let getThereTodo = "Swipe right"

        static let pageStep = "On this page"
        static let pageLead = "These three are examples, so the wheel isn’t empty."
        static let page = [
            "your tasks on the wheel, freestyle first",
            "History top left",
            "under it: tasks done and time left — a tap opens Your azkar",
        ]

        static let todos = [
            "Scroll the wheel",
            "Hold a task, then pick an option",
        ]
        static let allDone = "On your own tasks, that’s how you edit or delete them."

        static let exampleTag = "example"   // on each example task's circle
    }

    // MARK: 4 · Settings

    enum Settings {
        static let title = "Settings"

        static let getThereLead = "Settings is one page over."
        static let getThereTodo = "Swipe left"

        static var hereStep: String { TourFlow.v2 ? "Reminders" : "What you set here" }
        /// The new flow's opening line (owner: the Reminders section had no intro).
        static let remindersIntro = "Reminders come three ways. Here’s how to change them."
        static var here: [String] { TourFlow.v2 ? [
            "your location, prayer times and qibla, your reminders, and how shukr looks",
        ] : [
            "your location, prayer times and qibla",
            "notifications, Live Activities and the Fajr alarm",
            "how shukr looks, and its widgets",
            "Explore shukr: widgets, Siri and more",
        ] }

        static let lastStep = "This tour"
        /// Its try-its (owner: harmless moves — Explore stays something to discover).
        /// The new flow starts on a prayer's bell (put back once it's let go — TourRuntime.restoreBell).
        static var todos: [String] { (TourFlow.v2 ? ["Tap a prayer’s bell"] : []) + [
            "Switch Reminders to Live Activities",
            "Now switch to Fajr Alarm",
            "Tap ⓘ by Reminders",
        ] }
        /// A line over each to-do in the panel: what the thing it names is.
        static var todoLeads: [String] { (TourFlow.v2 ? ["Notifications first: each prayer’s bell says what it sends."] : []) + [
            "Live Activities put a prayer's countdown on your lock screen.",
            "The Fajr alarm is a real alarm that moves with Fajr.",
            "Every ⓘ explains its section in plain words.",
        ] }
        static var todoAfters: [String] { (TourFlow.v2 ? ["Each tap moves it on: off, start, then nudge, which adds a reminder halfway and one near the end. We’ll put yours back."] : []) + [
            "Each prayer gets its card when it starts, and you can mark it right from there.",
            "Set it once and it rings before Fajr every day, moving with Fajr through the year.",
            "Look for ⓘ by any section whenever you want to know more.",
        ] }
        /// The last chapter's moment swipes to this, the tour's end.
        static let finale = "Tour complete"
        static let last = "That’s shukr. May it make your prayers easier. If you ever want this walk again, it lives here."
        static let doneButton = "Done"
    }

    // MARK: The Zikr Tour (chapter 3's "Show me", the first Zikr visit, ☰ → Zikr Tour)

    enum ZikrTour {
        static let title = "Zikr"
        static let menuRow = "Zikr Tour"            // in the ☰ menu until it's finished
        static let offer = "Want to learn Zikr properly? About 2 minutes."
        static let showMe = "Show me"
        static let skipToSettings = "Skip to Settings"   // in the app tour
        static let notNow = "Not now"                    // on its own

        // The first step carries on from the lock's narration ("take the first step" — decision zikr-lock-bridge A); the
        // freestyle / task difference is learned on the page later, not explained up front.
        static let kindsStep = "Your first step"
        static let kindsLead = "Your first step: one zikr, every day."
        static let kindsTodo = "Tap New task"
        static let reuseLead = "Your first step is already here."
        static let reuseDoneLead = "You already have an Astaghfirullah task, and today’s is done."

        static let taskStep = "Your first task"
        static let pickLead = "Every task is one zikr."
        static let pickTodo = "Pick Astaghfirullah"
        static let goalLead = "A goal can be a count or minutes."
        static let goalTodo = "Make it 33, then Continue"
        static let placeLead = "Put it where you like on your list, or leave it at the end."
        static let placeTodo = "Continue"
        static let reviewLead = "Name: optional, like “After Fajr”. Reminder: optional — a daily nudge at a time or around a prayer."
        static let reviewTodo = "Tap Add to my day"

        static let countStep = "Count it"
        // The counter's welcome, before the first lesson — its own moment, no bubble (owner: "a nice welcome and just
        // explains we gonna show them the different ways to count and we'll do it together").
        static let welcomeKicker = "Your counter"
        static let welcomeTitle = "Welcome"
        static let welcomeBody = "There are three ways to count. Try each one here first — we’ll do it together."
        /// The practice boxes (owner: "three different boxed areas in an hstack that has each ghost finger graphic").
        static let practiceTap = "Tap"
        static let practiceDrag = "Drag down, then lift"
        static let practiceStroke = "Keep pressed, drag up and down"
        static let welcomeButton = "Let’s begin"
        static let startLead = "Your task is on the wheel."
        static let startTodo = "Tap your zikr to carry on"
        static let tapLead = "The whole screen counts."
        static let tapTodo = "Tap anywhere, 3 times"
        static let dragLead = "Drag down anywhere, then lift."
        static let dragTodo = "3 separate drags"
        static let strokeLead = "You can keep your finger pressed and drag up and down."
        static let strokeTodo = "3 drags without lifting"
        static func goLead(_ goal: Int) -> String { "Keep going — it ends by itself at \(goal)." }
        static func goTodo(_ goal: Int) -> String { "Reach \(goal)" }

        static let streakStep = "Your streak and pace"
        /// The results' line, as it went (owner: "user can finish early so write that streak phrase dynamically"; then
        /// "they don't gotta do the 100. they can end it and it'll show how we save tasks with progress in their tab").
        static func streakLead(counted: Int, goal: Int, streak: Int, met: Bool, task: String) -> String {
            if met {
                return streak <= 1 ? "Goal met — that’s day 1 of your streak. Every day you meet it, your streak grows."
                                   : "Goal met — that’s day \(streak) of your streak. Every day you meet it, it grows."
            }
            return "\(counted) done — \(task) is waiting on your wheel to finish today."
        }
        static func paceLine(_ seconds: Double) -> String {
            "Your pace: \(String(format: "%.1f", seconds))s a count — shukr learns it as you go."
        }
        static let streakTodo = "Tap Done"

        static let timeStep = "How long it takes"
        static let timeLead = "With your pace, the line under the wheel knows how long your tasks will take."
        static let timeTodo = "Tap it"
        static let tasksLead = "All your tasks. Hold and drag to change their order."

        static let whereStep = "Where things live"
        static let historyLead = "Every session you finish lives in History."
        static let historyTodo = "Open History, top left"
        static let historyPageLead = "Today’s session is at the top."
        static let azkarLead = "Your zikr live in Azkar."
        static let azkarTodo = "Open Azkar, top right"
        static let azkarPageLead = "The built-in ones, and your own — ＋ adds one."

        static func doneLine(met: Bool, counted: Int, goal: Int) -> String {
            met ? "That’s your first day of remembrance. Your zikr will be waiting for you tomorrow."
                : "Your \(counted) are saved — its ring shows \(counted) of \(goal). Finish it here anytime today."
        }
        static let doneButton = "Done"
    }

    // MARK: The first counting session's tips (a freestyle session, after the tour)

    enum Session {
        static let skip = "Skip tips"
        static let skipConfirm = "Tap again to skip"

        // 1 · Counting
        static let countingTitle = "Counting"
        static let tapStep = "Tap"
        static let tapLead = "The whole screen is your counter."
        static let tapTodo = "Tap anywhere, 3 times"
        static let dragStep = "Drag"
        static let dragLead = "Drag down anywhere, then lift your finger."
        static let dragTodo = "3 separate drags"
        static let strokeStep = "Without lifting"
        static let strokeLead = "Keep your finger down and move it down and up."
        static let strokeTodo = "3 drags without lifting"

        // 2 · Pausing
        static let pausingTitle = "Pausing"
        static let pauseStep = "Pause"
        static let pauseLead = "The pause button is at the top left."
        static let pauseTodo = "Tap pause"
        static let pausedStep = "The pause screen"
        static let pausedLead = "Your session’s stats, notes for the zikr, and a few more things at the bottom — explore them any time. For now, let’s finish."
        static let pausedTodo = "Tap Finish, then again"

        // 3 · After
        static let afterTitle = "After"
        static let resultsStep = "Saved"
        static let resultsLead = "Every session you finish goes into your history."
        static let resultsTodo = "Tap Done"
        static let historyStep = "Your history"
        static let historyLead = "It’s top left on the Zikr page."
        static let historyTodo = "Open History"
        static let deleteStep = "Tidy up"
        static let deleteLead = "That was practice — delete it."
        static let deleteTodo = "Swipe “Practice” left, then Delete"
        static let keptStep = "That one counts"
        static let keptLead = "You counted for real, so it’s kept."
        static let endLine = "Now the real one: tap the circle when you’re ready."
        static let endButton = "Done"
        static let practiceTitle = "Practice"   // the practice session's name in History
        // Settings, under "Show me around again"
        static let againRow = "Show me the counting tips again"
        static let againArmed = "Ready — start a freestyle session"
    }

    // MARK: Around the tour

    enum Skip {
        static let button = "Skip tour"
        static let confirm = "Tap again to skip"
        static let skippedTitle = "You skipped the tour"
        static let skippedLine = "It’s in the ☰ menu and in Settings whenever you want it."
        /// The ✕ in the tour's top panel asks first, with iOS's own alert (owner).
        static let alertTitle = "Skip the tour?"
        static let alertLine = "It’s in the ☰ menu whenever you want it."
        static let alertSkip = "Skip tour"
        static let alertKeep = "Keep going"
    }

    /// The invitation after the first-run setup.
    enum Invite {
        static let title = "Want a quick look around?"
        static let line = "Two minutes, on a practice prayer — nothing you do here is saved. You can run it again any time from Settings."
        static let later = "Later"
        static let showMe = "Show me"
    }

    static let menuRow = "App Tour"                  // in the ☰ menu until the tour is finished
    static let backToTour = "Back to the tour"       // when something takes them off the chapter's page

    // MARK: After the tour (the first real mark)

    enum AfterTour {
        static let celebrateTitle = "Your first prayer, marked."
        static let celebrateLine = "May there be many more."

        static let pillTitle = "Tasbih Fatimah, after every prayer."
        static let pillLine = "Each time you mark a prayer, this comes up for a little while — 33 · 33 · 34, if you’d like to say it. Tap it now."   // no-break spaces keep 33 · 33 · 34 on one line
        static let pillTodo = "Tap “Post-salah tasbih”"
        static let pillDoneTitle = "It’ll be there after every prayer."
        static let pillDoneLine = "Mark a prayer and it comes up. ✕ when you’d rather not."

        static let mapTitle = "See where you prayed"
        static let mapLine = "Every prayer you mark is on the map, under Explore → Prayers."
        static let mapTodo = "Tap the arrow on the circle"

        static let markTitle = "Tap the dot"
        static let markLine = "to mark it prayed. Hold it to change the time."

        static let gotIt = "Got it"
    }
}
