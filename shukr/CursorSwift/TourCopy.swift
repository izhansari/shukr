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

enum TourCopy {

    // MARK: Used on every chapter

    static let continueButton = "Continue"
    static let getThere = "Get there"        // the first step of Zikr and Settings
    static let tryIt = "Try it"              // the to-dos step's label

    // MARK: The welcome (before chapter 1)

    enum Welcome {
        static let title = "Bismillah"
        static let line = "Let’s take a quick look around."
        static let chapters = [
            "Prayer Circle|the prayer that matters now",
            "Prayer List|your whole day",
            "Zikr|your daily remembrance",
            "Settings|make it yours",
        ]
        static let footnote = "A quick look at each, then you try it. It’s a practice day — nothing here is kept."
        static let button = "Let’s begin"
    }

    // MARK: 1 · Prayer Circle

    enum Circle {
        static let title = "Prayer Circle"

        static let showsStep = "What it shows"
        static let showsLead = "It shows the prayer that matters to you:"
        static let situations = [
            "during a prayer?|the current one",
            "already prayed?|the upcoming one",
            "end of the day?|any you missed",
        ]

        static let coloursStep = "The colours"
        static let coloursLead = "The ring fills with different colours based on how much time passes:"
        static let colours = ["First 30 min", "On time", "Late"]   // green, yellow, red
        static let seeItInAction = "See it in action"
        static let playAgain = "Play again"

        static let todos = [
            "Tap the circle to flip the time text",
            "Turn until the qibla arrow points up",
            "Hold the circle to mark Asr",
        ]
        static let noCompass = "No compass here? Skip it"
        static let marked = "Marked — Asr has moved to your list. Swipe up to see it."
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

        static let todos = [
            "Tap a coming prayer for the time until",
            "Unfold to see all your prayers",
            "Tap a marked prayer for its score",
            "Hold a marked one, change its time, save",
        ]
        static let allDone = "That’s your day — and it only ever says what’s true."

        // The tip inside the time editor (opened by the last to-do).
        static let editorTitle = "When did you really pray?"
        static let editorLine = "Drag the colour bar or turn the wheel, then save. It’s practice — nothing is kept."
        static let editorTodo = "Change the time, then save"
    }

    // MARK: 3 · Zikr

    enum Zikr {
        static let title = "Zikr"

        static let getThereLead = "It’s one page over."
        static let getThereTodo = "Swipe right"

        static let pageStep = "On this page"
        static let pageLead = "The tasks here are examples."
        static let page = [
            "your tasks on the wheel, freestyle first",
            "History top left, Azkar top right",
            "under it: tasks done and time left",
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

        static let getThereLead = "One tap away."
        static let getThereTodo = "Tap Settings"

        static let hereStep = "What you set here"
        static let here = [
            "your location and how prayer times are worked out",
            "a reminder for each prayer",
            "the Fajr alarm",
            "how shukr looks",
        ]

        static let lastStep = "This tour"
        static let last = "It lives here: tap “Show me around again” any time."
        static let doneButton = "Done"
    }

    // MARK: Around the tour

    enum Skip {
        static let button = "Skip tour"
        static let confirm = "Tap again to skip"
        static let skippedTitle = "You skipped the tour"
        static let skippedLine = "It’s in the ☰ menu and in Settings whenever you want it."
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
