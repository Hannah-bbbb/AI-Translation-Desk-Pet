import Foundation

/// Decides when the pet has a real reason to speak up on his own: you just arrived, you have
/// been at it too long, it is time to stop.
///
/// It looks only at the clock and at how long the keyboard and mouse have been idle, so tests
/// can run a whole day through it in a moment. Calling `tick` once a second is plenty.
struct Companion {
    enum Occasion: Equatable {
        /// The first meeting of the day.
        case hello
        case welcomeBack(minutesAway: Int)
        case takeBreak(minutesWorked: Int)
        /// Back from the break he suggested.
        case backFromBreak
        case offWork
        case bedtime
        case busyDay(translations: Int)
        /// A word from the vocabulary list is due for review.
        case quiz
    }

    struct Preferences {
        var greets = true
        /// Minutes of unbroken work before he suggests a break; 0 turns it off.
        var breakMinutes = 50
        /// Minutes after midnight, or nil when off.
        var offWorkMinute: Int? = 18 * 60 + 30
        var bedtimeMinute: Int? = 23 * 60 + 30
        var quizzes = true
    }

    /// What has already happened today. Saved between launches so a relaunch does not earn a
    /// second good morning.
    struct Day: Codable, Equatable {
        var date = ""
        var greeted = false
        var saidOffWork = false
        var translations = 0
    }

    // Seconds, unless named otherwise.
    /// Input within this long means someone is at the Mac.
    static let presence = 60.0
    /// An absence this long counts as a break and starts a new stretch of work.
    static let breakGap = 5 * 60.0
    static let longAbsenceMinutes = 30
    /// He never speaks up twice within this long.
    static let quiet = 10 * 60.0
    /// A greeting that could not be delivered on arrival is still worth saying this much later.
    static let arrivalGrace = 2 * 60.0
    /// If a break suggestion is ignored he tries again this much later, then twice as long
    /// after that, and so on up to `breakRepeatLimit`. Persistent, not a nag.
    static let breakRepeat = 30 * 60.0
    static let breakRepeatLimit = 2 * 60 * 60.0
    static let bedtimeRepeat = 45 * 60.0
    static let quizRepeat = 90 * 60.0
    /// No quiz until a stretch of work has settled in.
    static let quizWarmUp = 15 * 60.0
    /// How long after the set time "time to stop" is still news, in minutes.
    static let offWorkWindow = 120
    /// The day turns over at five, so working past midnight is still "tonight".
    static let dayStartMinute = 5 * 60
    static let milestones: Set<Int> = [20, 50, 100]

    private(set) var day: Day

    private struct Arrival {
        var at: Date
        /// Nil right after launch, when he has no idea how long you were gone.
        var minutesAway: Int?
        var afterNudge: Bool
    }

    private var lastSeen: Date?
    private var stretchStart: Date?
    private var arrival: Arrival?
    /// Break suggestions made during the current stretch of work.
    private var nudges = 0
    private var nextBreakNudge: Date?
    private var lastBedtimeNudge: Date?
    private var lastQuiz: Date?
    private var lastSpoke: Date?
    private var milestone: Int?

    init(day: Day = Day()) {
        self.day = day
    }

    /// - Parameters:
    ///   - idle: Seconds since the last keyboard or mouse input.
    ///   - hasDueWord: Whether the vocabulary list has something to ask about.
    ///   - canSpeak: Asked only when he has something to say; false keeps it for later.
    mutating func tick(
        now: Date,
        idle: TimeInterval,
        preferences: Preferences,
        hasDueWord: Bool = false,
        calendar: Calendar = .current,
        canSpeak: () -> Bool
    ) -> Occasion? {
        rollOver(now, calendar)
        // Nobody to talk to. Also what makes an absence show up as a gap in `lastSeen`.
        guard idle < Self.presence else { return nil }

        let absence = lastSeen.map { now.timeIntervalSince($0) }
        lastSeen = now
        if absence ?? .infinity >= Self.breakGap {
            arrival = Arrival(at: now, minutesAway: absence.map { Int($0 / 60) }, afterNudge: nudges > 0)
            stretchStart = now
            nudges = 0
            nextBreakNudge = nil
        }
        if let arrival, now.timeIntervalSince(arrival.at) > Self.arrivalGrace {
            self.arrival = nil
        }

        guard let occasion = due(now, preferences, hasDueWord, calendar) else { return nil }
        if let lastSpoke, now.timeIntervalSince(lastSpoke) < Self.quiet { return nil }
        guard canSpeak() else { return nil }

        switch occasion {
        case .hello:
            day.greeted = true
            arrival = nil
        case .welcomeBack, .backFromBreak:
            arrival = nil
        case .takeBreak:
            nudges += 1
            let wait = Self.breakRepeat * pow(2, Double(nudges - 1))
            nextBreakNudge = now.addingTimeInterval(min(wait, Self.breakRepeatLimit))
        case .offWork:
            day.saidOffWork = true
        case .bedtime:
            lastBedtimeNudge = now
        case .busyDay:
            milestone = nil
        case .quiz:
            lastQuiz = now
        }
        lastSpoke = now
        return occasion
    }

    /// Counts a finished translation. Round numbers earn a remark at the next quiet moment.
    mutating func translated(now: Date, calendar: Calendar = .current) {
        rollOver(now, calendar)
        day.translations += 1
        if Self.milestones.contains(day.translations) { milestone = day.translations }
    }

    /// The most pressing thing he could say right now, if anything.
    private func due(_ now: Date, _ preferences: Preferences, _ hasDueWord: Bool, _ calendar: Calendar) -> Occasion? {
        let minute = Self.minuteOfDay(now, calendar)
        let lateNight = preferences.bedtimeMinute.map { Self.isPastBedtime(minute, bedtime: $0) } ?? false

        if let arrival {
            if preferences.greets, !day.greeted { return .hello }
            if preferences.greets, let away = arrival.minutesAway, away >= Self.longAbsenceMinutes {
                return .welcomeBack(minutesAway: away)
            }
            if arrival.afterNudge { return .backFromBreak }
        }
        if lateNight, lastBedtimeNudge.map({ now.timeIntervalSince($0) >= Self.bedtimeRepeat }) ?? true {
            return .bedtime
        }
        if let offWork = preferences.offWorkMinute, !day.saidOffWork,
           (minute - offWork + 1440) % 1440 < Self.offWorkWindow {
            return .offWork
        }
        // Past bedtime "go to sleep" already covers "take a break".
        let worked = stretchStart.map { now.timeIntervalSince($0) } ?? 0
        if preferences.breakMinutes > 0, !lateNight, worked >= Double(preferences.breakMinutes) * 60,
           now >= nextBreakNudge ?? .distantPast {
            return .takeBreak(minutesWorked: Int(worked / 60))
        }
        if let milestone { return .busyDay(translations: milestone) }
        if preferences.quizzes, hasDueWord, !lateNight, worked >= Self.quizWarmUp,
           lastQuiz.map({ now.timeIntervalSince($0) >= Self.quizRepeat }) ?? true {
            return .quiz
        }
        return nil
    }

    private mutating func rollOver(_ now: Date, _ calendar: Calendar) {
        let shifted = now.addingTimeInterval(-Double(Self.dayStartMinute) * 60)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if date != day.date { day = Day(date: date) }
    }

    static func minuteOfDay(_ date: Date, _ calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The night runs from bedtime until the day starts over.
    static func isPastBedtime(_ minute: Int, bedtime: Int) -> Bool {
        let length = (dayStartMinute - bedtime + 1440) % 1440
        let since = (minute - bedtime + 1440) % 1440
        return since < (length == 0 ? 180 : min(length, 480))
    }
}
