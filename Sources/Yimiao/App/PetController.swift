import AppKit
import ApplicationServices
import Combine

/// Wires everything together: feeds the brain each frame, turns selections into translations,
/// lets him speak up when there is a reason to, and keeps the bubble anchored to him.
@MainActor
final class PetController: NSObject, PetViewDelegate, NSMenuDelegate {
    /// Longer selections are almost certainly not something to read in a bubble.
    private static let maxLength = 3000

    private let settings = Settings.shared
    private let brain = PetBrain()
    private let bubble = BubbleModel()
    private let watcher = SelectionWatcher()
    private let vocabulary = Vocabulary()
    private let settingsWindow = SettingsWindow()
    private let vocabularyWindow = VocabularyWindow()
    private let petView = PetView()
    private let petWindow: OverlayPanel
    private let bubbleWindow = OverlayPanel(size: BubbleLayout.windowSize)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var subscriptions = Set<AnyCancellable>()

    private var translation: Task<Void, Never>?
    private var translationID = 0
    private var lastSource = ""
    /// Service failures in a row. A second one in a row is a pattern, not bad luck.
    private var serviceFailures = 0
    private var companion = Companion(day: PetController.savedDay())
    /// The copy of `companion.day` last written to disk.
    private var storedDay = PetController.savedDay()
    /// A remark he has decided to make and is still wording.
    private var remark: Task<Void, Never>?
    /// True when he nodded off from boredom, in which case activity wakes him again.
    private var sleptOnHisOwn = false
    private var wokeOnThisClick = false
    private var isDragging = false
    private var hasAccessibility = AXIsProcessTrusted()
    private var lastMouse = NSEvent.mouseLocation
    private var lastOrigin = CGPoint.zero
    private var sinceCheck = 0.0
    private var lastReminder = Date.distantPast

    /// The spot he calls home, in screen coordinates of his feet. Dragging him sets it.
    private var spot = CGPoint.zero
    /// True while he is over at a selection rather than where he belongs.
    private var isOut = false
    private var leap: Leap?
    /// Seconds he has had nothing left to do at a selection.
    private var lingering = 0.0
    /// Retained for the whole translation, including streaming and error messages.
    private var protectedSelection: CGRect?
    private var selectionAnchor: CGPoint?
    private var bubbleHasNoSpace = false

    /// Video is on screen somewhere.
    private var isWatching = false
    /// The user called him out during this video, so he stays out until it ends.
    private var declinedHiding = false
    private var playingFor = 0
    private var stoppedFor = 0

    /// One jump across the screen, in screen coordinates of his feet.
    private struct Leap {
        let from: CGPoint
        let to: CGPoint
        let duration: Double
        /// Height of the arc at its peak.
        let rise: CGFloat
        var elapsed = 0.0
    }

    override init() {
        petWindow = OverlayPanel(size: Self.windowSize(scale: Settings.shared.petScale))
        super.init()

        petView.delegate = self
        petView.scale = settings.petScale
        petView.frame = CGRect(origin: .zero, size: petWindow.frame.size)
        petView.autoresizingMask = [.width, .height]
        petWindow.contentView = petView
        bubbleWindow.contentView = BubbleHostingView(rootView: BubbleView(model: bubble))

        menu.delegate = self
        statusItem.menu = menu
        let icon = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "译喵")
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "译喵")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageLeading
    }

    func start() {
        spot = onScreen(savedSpot() ?? defaultSpot())
        petWindow.setFrameOrigin(origin(forFeet: spot, scale: settings.petScale))
        lastOrigin = petWindow.frame.origin
        layoutBubble()
        petWindow.orderFrontRegardless()
        bubbleWindow.orderFrontRegardless()

        watcher.onSelection = { [weak self] in self?.translate($0, near: $1, avoiding: $2) }
        watcher.isEnabled = { [weak self] in self?.brain.isAsleep == false }
        watcher.allowsClipboardFallback = { [weak self] in self?.settings.clipboardFallback ?? false }
        watcher.onBlocked = { [weak self] in self?.remindAboutPermission() }
        watcher.start()
        Log.selection.notice("launched, Accessibility access: \(self.hasAccessibility)")

        settings.$petScale.dropFirst().removeDuplicates()
            .sink { [weak self] in self?.applyScale($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                // `settle` walks him over if his spot had to move.
                self.spot = self.onScreen(self.spot)
                self.layoutBubble()
            }
            .store(in: &subscriptions)

        greet()
    }

    // MARK: - Frame

    func petView(_ view: PetView, poseAfter dt: Double) -> PetPose {
        advanceLeap(dt)
        settle(dt)

        let scale = settings.petScale
        let mouse = NSEvent.mouseLocation
        let feet = feetOnScreen
        // Into the brain's space: relative to the feet, y down, unscaled.
        let local = CGPoint(x: (mouse.x - feet.x) / scale, y: (feet.y - mouse.y) / scale)
        brain.updateMouse(local, travel: hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) / scale, dt: dt)
        lastMouse = mouse

        let origin = petWindow.frame.origin
        if isDragging, dt > 0 {
            let speed = (origin.x - lastOrigin.x) / scale / dt
            brain.carrySpeed += (speed - brain.carrySpeed) * min(1, dt * 12)
        } else {
            brain.carrySpeed = 0
        }
        lastOrigin = origin

        // Only the cat and the bubble card catch clicks. The rest of both windows is empty air.
        setClickThrough(petWindow, !(isDragging || brain.hitTest(local)))
        let bubbleFrame = bubbleWindow.frame
        let hovered = bubble.target(at: CGPoint(x: mouse.x - bubbleFrame.minX, y: bubbleFrame.maxY - mouse.y))
        setClickThrough(bubbleWindow, hovered == nil || bubbleHasNoSpace || bubbleWindow.alphaValue == 0)
        if bubble.hovered != hovered { bubble.hovered = hovered }
        if !bubbleHasNoSpace { bubble.tick(dt: dt) }
        if !bubble.isVisible, protectedSelection != nil {
            clearSelectionPlacement()
            layoutBubble()
        }
        brain.bubbleBelow = bubble.isBelow

        sinceCheck += dt
        if sinceCheck >= 1 {
            sinceCheck = 0
            let anyInput = CGEventType(rawValue: ~0)!
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
            checkPermission()
            checkVideo()
            checkIdle(idle)
            // Watching something is sitting at the screen, not being away from it.
            checkRhythm(isWatching ? 0 : idle)
        }
        let pose = brain.tick(dt: dt)
        view.pace = brain.isLively ? .lively : .resting
        return pose
    }

    private func setClickThrough(_ window: NSWindow, _ ignores: Bool) {
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }

    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        guard trusted != hasAccessibility else { return }
        hasAccessibility = trusted
        Log.selection.notice("Accessibility access is now: \(trusted)")
        if trusted {
            watcher.restart()
            if !brain.isAsleep { bubble.say("权限到手！选中一段文字试试看～") }
        }
    }

    /// He noticed a selection he was not allowed to read. Once a minute is enough nagging.
    private func remindAboutPermission() {
        guard !bubble.isVisible, Date().timeIntervalSince(lastReminder) > 60 else { return }
        lastReminder = Date()
        layoutBubble()
        bubble.say("我看不见你选中的文字：「辅助功能」权限还没生效。\n点这里，然后在列表里打开「译喵」的开关", seconds: 12) {
            Permissions.requestAccessibility()
        }
        brain.confuse()
    }

    private func checkIdle(_ idle: TimeInterval) {
        if brain.isAsleep {
            if sleptOnHisOwn, idle < 2 { setAsleep(false) }
        } else if settings.autoSleepMinutes > 0, idle > Double(settings.autoSleepMinutes) * 60, !bubble.isVisible {
            setAsleep(true, onHisOwn: true)
        }
    }

    // MARK: - Pet interaction

    func petView(_ view: PetView, clicked count: Int) {
        if count == 1 {
            wokeOnThisClick = brain.isAsleep
            if brain.isAsleep {
                setAsleep(false)
            } else {
                bubble.hide()
                brain.poke()
            }
            // Clicking the sliver of him at the edge calls him out for the rest of this video.
            if isHiding { declinedHiding = true }
        } else if count == 2, !wokeOnThisClick {
            // Without the check, double-clicking a sleeping cat would wake him and knock him straight out again.
            setAsleep(true)
        }
    }

    func petViewDragBegan(_ view: PetView) {
        isDragging = true
        brain.isHeld = true
        // Picked up mid-visit, mid-jump or out of hiding: wherever he is put down is home now.
        leap = nil
        isOut = false
        clearSelectionPlacement()
        bubbleWindow.alphaValue = 1
        if isWatching { declinedHiding = true }
    }

    func petViewDragged(_ view: PetView) {
        layoutBubble()
    }

    func petViewDragEnded(_ view: PetView) {
        isDragging = false
        brain.isHeld = false
        brain.drop()
        spot = onScreen(feetOnScreen)
        petWindow.setFrameOrigin(origin(forFeet: spot, scale: settings.petScale))
        layoutBubble()
        UserDefaults.standard.set(NSStringFromPoint(spot), forKey: "petFeet")
    }

    func petViewMenu(_ view: PetView) -> NSMenu { menu }

    private func setAsleep(_ asleep: Bool, onHisOwn: Bool = false) {
        guard asleep != brain.isAsleep else { return }
        sleptOnHisOwn = asleep && onHisOwn
        if asleep {
            cancelTranslation()
            remark?.cancel()
            remark = nil
            bubble.hide()
            clearSelectionPlacement()
            // He sleeps where he belongs, not wherever the last selection happened to be.
            if isOut { startLeap(to: restingPlace, isVisit: false) }
            brain.fallAsleep()
        } else {
            brain.wakeUp()
        }
    }

    // MARK: - Translation

    /// `pointer` is where a mouse selection ended, if that is how the text was chosen.
    private func translate(_ raw: String, near pointer: CGPoint? = nil, avoiding selection: CGRect? = nil) {
        guard !brain.isAsleep else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LanguageRouter.isWorthTranslating(text) else { return }
        // Re-selecting what is already on show should not flicker the bubble or cost a request.
        if text == lastSource, bubble.isVisible, selection == protectedSelection { return }
        guard let route = LanguageRouter.route(
            text,
            primary: settings.primary,
            secondary: settings.secondary,
            translatesPrimary: settings.translatesPrimary
        ) else { return }

        cancelTranslation()
        remark?.cancel()
        remark = nil
        protectedSelection = selection ?? pointer.map {
            CGRect(x: $0.x - 60, y: $0.y - 24, width: 120, height: 48)
        }
        selectionAnchor = pointer ?? selection.map { CGPoint(x: $0.midX, y: $0.midY) }
        layoutBubble()
        guard text.count <= Self.maxLength else {
            bubble.say("这段有 \(text.count) 个字，太长啦，我一次最多看 \(Self.maxLength) 字")
            brain.confuse()
            return
        }
        let config = settings.translatorConfig
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bubble.say("我还没有 API Key 呢，点这里去设置里填上", seconds: 8) { [weak self] in self?.openSettings() }
            brain.confuse()
            return
        }

        lastSource = text
        translationID += 1
        let id = translationID
        Log.translation.notice("start: \(text.count) characters, \(route.caption, privacy: .public)")
        brain.notice()
        if selectionAnchor != nil { visitSelection() }
        bubble.begin(caption: route.caption)
        brain.activity = .thinking

        translation = Task { [weak self] in
            var started = false
            do {
                for try await piece in Translator.stream(text, to: route.target, otherwise: route.alternate, config: config) {
                    // A newer selection may have replaced this one mid-stream.
                    guard let self, self.translationID == id else { return }
                    if !started {
                        started = true
                        self.brain.activity = .speaking
                    }
                    self.bubble.append(piece)
                }
                guard let self, self.translationID == id else { return }
                guard started else { throw TranslatorError.emptyReply }
                Log.translation.notice("done")
                self.serviceFailures = 0
                self.bubble.finish()
                self.brain.celebrate()
                self.companion.translated(now: Date())
                self.saveDay()
                if self.settings.keepsVocabulary, Vocabulary.isWord(text) {
                    self.vocabulary.record(text, meaning: self.bubble.text)
                }
            } catch {
                guard let self, self.translationID == id, !Task.isCancelled else { return }
                Log.translation.error("failed: \(String(describing: error), privacy: .public)")
                self.lastSource = ""
                self.showFailure(error, config: config) { [weak self] in self?.translateOnRequest(text) }
            }
            self?.brain.activity = .idle
            self?.translation = nil
        }
    }

    /// Says what went wrong, whose fault it probably is, and offers the obvious next step.
    private func showFailure(_ error: Error, config: TranslatorConfig, retry: @escaping () -> Void) {
        let provider = config.provider
        let message = Translator.describe(error, provider: provider)
        let retryChoice = BubbleModel.Choice(title: "重试", action: retry)
        switch Translator.trouble(error) {
        case .service:
            serviceFailures += 1
            var choices = [retryChoice]
            var text = message
            if serviceFailures >= 2 {
                text += "\n连续 \(serviceFailures) 次了，多半是 \(provider) 那边出了故障，过会儿再来"
                if let page = config.statusPage {
                    choices.append(.init(title: "看服务状态") { NSWorkspace.shared.open(page) })
                }
            }
            bubble.fail(text, caption: "\(provider) 服务异常", choices: choices)
        case .network:
            bubble.fail(message, caption: "网络问题", choices: [retryChoice])
        case .settings:
            bubble.fail(message, caption: "设置需要检查", choices: [.init(title: "去设置") { [weak self] in
                self?.bubble.hide()
                self?.openSettings()
            }])
        case .other:
            bubble.fail(message)
        }
        brain.confuse()
    }

    private func cancelTranslation() {
        translationID += 1
        translation?.cancel()
        translation = nil
        brain.activity = .idle
    }

    // MARK: - Speaking up

    private func checkRhythm(_ idle: TimeInterval) {
        let now = Date()
        let occasion = companion.tick(
            now: now,
            idle: idle,
            preferences: settings.companionPreferences,
            hasDueWord: vocabulary.nextDue(now: now) != nil,
            canSpeak: { self.canSpeakUp }
        )
        saveDay()
        if let occasion { speakUp(occasion) }
    }

    /// He only volunteers something when he is awake, at home and has the floor.
    private var canSpeakUp: Bool {
        settings.speaksUp && !brain.isAsleep && !bubble.isVisible && translation == nil && remark == nil
            && !isOut && !isHiding && leap == nil && !isDragging && !frontmostAppIsFullScreen()
    }

    private func speakUp(_ occasion: Companion.Occasion) {
        Log.companion.notice("\(String(describing: occasion), privacy: .public)")
        if occasion == .quiz {
            quiz()
            return
        }
        let now = Date()
        let stock = Lines.stock(for: occasion, at: now)
        let config = settings.translatorConfig
        let asksModel = settings.writesOwnLines && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        remark = Task { [weak self] in
            var line = stock
            if asksModel,
               let reply = try? await Translator.reply(system: Lines.persona, user: Lines.brief(for: occasion, at: now), config: config),
               let written = Lines.tidy(reply) {
                line = written
            }
            guard let self, !Task.isCancelled else { return }
            self.remark = nil
            Log.companion.notice("line written by: \(line == stock ? "stock" : "model", privacy: .public)")
            // The moment may have passed while the model was writing.
            guard !self.brain.isAsleep, !self.bubble.isVisible, self.translation == nil else { return }
            self.layoutBubble()
            self.bubble.say(line, seconds: 9)
            self.brain.perform(Self.gesture(for: occasion))
        }
    }

    private static func gesture(for occasion: Companion.Occasion) -> PetBrain.Gesture {
        switch occasion {
        case .hello, .backFromBreak: .hop
        case .welcomeBack: .wiggle
        case .takeBreak: .stretch
        case .bedtime: .yawn
        case .offWork, .busyDay: .cheer
        case .quiz: .tilt
        }
    }

    /// A presentation, a film, a game: not the time for a cat to pipe up.
    private func frontmostAppIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return screens.contains(frame.size)
        }
    }

    private static func savedDay() -> Companion.Day {
        guard let data = UserDefaults.standard.data(forKey: "companionDay"),
              let day = try? JSONDecoder().decode(Companion.Day.self, from: data)
        else { return Companion.Day() }
        return day
    }

    private func saveDay() {
        guard companion.day != storedDay else { return }
        storedDay = companion.day
        UserDefaults.standard.set(try? JSONEncoder().encode(storedDay), forKey: "companionDay")
    }

    // MARK: - Vocabulary quiz

    private func quiz() {
        guard let word = vocabulary.nextDue() else { return }
        layoutBubble()
        brain.perform(.tilt)
        bubble.ask("考考你：还记得「\(word.term)」怎么翻吗？", seconds: 25, choices: [
            .init(title: "看答案") { [weak self] in self?.reveal(word) },
        ])
    }

    private func reveal(_ word: Word) {
        bubble.ask("\(word.term)\n\(word.meaning)", seconds: 30, choices: [
            .init(title: "记得 ✓") { [weak self] in self?.grade(word, remembered: true) },
            .init(title: "忘了") { [weak self] in self?.grade(word, remembered: false) },
        ])
    }

    private func grade(_ word: Word, remembered: Bool) {
        vocabulary.grade(word, remembered: remembered)
        guard remembered else {
            bubble.say("没事，明天我再问你", seconds: 3)
            brain.perform(.wiggle)
            return
        }
        let streak = word.streak + 1
        bubble.say(
            streak < Vocabulary.intervals.count ? "厉害！\(Vocabulary.intervals[streak]) 天后再考你" : "这个词你已经拿下了喵",
            seconds: 3
        )
        brain.perform(.cheer)
    }

    // MARK: - Visiting a selection

    /// Hops next to the text that was just selected, so the translation appears where the
    /// eyes already are instead of over in his corner.
    private func visitSelection() {
        guard settings.visitsSelection, !isDragging else { return }
        guard let placement = selectionPlacement else { return }
        let target = placement.feet
        let feet = feetOnScreen
        // Even a short correction matters when the old spot would cover the selected text.
        guard hypot(target.x - feet.x, target.y - feet.y) > 1 else {
            isOut = true
            layoutBubble()
            return
        }
        // The bubble waits for him to land rather than flying along.
        bubbleWindow.alphaValue = 0
        startLeap(to: target, isVisit: true)
    }

    private func startLeap(to target: CGPoint, isVisit: Bool) {
        // Keep source protection until the message is dismissed, even if video hiding
        // moves the pet home while its translation is still visible.
        let from = feetOnScreen
        let distance = hypot(target.x - from.x, target.y - from.y)
        let duration = (0.28 + distance / 2600).clamped(0.28...0.6)
        leap = Leap(from: from, to: target, duration: duration, rise: min(90, 24 + distance * 0.12))
        isOut = isVisit
        lingering = 0
        brain.leap(for: duration, direction: target.x >= from.x ? 1 : -1)
    }

    private func advanceLeap(_ dt: Double) {
        guard var leap else { return }
        leap.elapsed += dt
        let t = min(leap.elapsed / leap.duration, 1)
        let eased = t * t * (3 - 2 * t)
        let feet = CGPoint(
            x: leap.from.x + (leap.to.x - leap.from.x) * eased,
            y: leap.from.y + (leap.to.y - leap.from.y) * eased + leap.rise * sin(t * .pi)
        )
        petWindow.setFrameOrigin(origin(forFeet: feet, scale: settings.petScale))
        if t < 1 {
            self.leap = leap
        } else {
            self.leap = nil
            bubbleWindow.alphaValue = 1
        }
        layoutBubble()
    }

    /// Wherever he is, he heads back to where he belongs once nothing keeps him.
    private func settle(_ dt: Double) {
        guard leap == nil, !isDragging else {
            lingering = 0
            return
        }
        let place = restingPlace
        let feet = feetOnScreen
        guard hypot(place.x - feet.x, place.y - feet.y) > 1 else {
            isOut = false
            lingering = 0
            return
        }
        if isOut {
            // At a selection he stays until he has said his piece, and a moment longer.
            guard !bubble.isVisible, translation == nil else {
                lingering = 0
                return
            }
            lingering += dt
            guard lingering > 1 else { return }
        }
        startLeap(to: place, isVisit: false)
    }

    // MARK: - Hiding from video

    private var isHiding: Bool { isWatching && !declinedHiding }

    /// Where he sits when he has nothing to do: his spot, or the screen edge during a video.
    private var restingPlace: CGPoint { isHiding ? hideout : spot }

    private func checkVideo() {
        if settings.hidesForVideo, Playback.isVideoPlaying() {
            playingFor += 1
            stoppedFor = 0
        } else {
            stoppedFor += 1
            playingFor = 0
        }
        // A couple of seconds each way: a clip that autoplays for a moment is not worth
        // moving for, and a pause to rewind is not the end of the film.
        if !isWatching, playingFor >= 2 {
            isWatching = true
            Log.companion.notice("video started, hiding at the edge")
        } else if isWatching, stoppedFor >= 5 {
            isWatching = false
            declinedHiding = false
            Log.companion.notice("video stopped, coming back")
        }
    }

    /// Level with his spot at the nearest side of the screen, with just one eye and an ear
    /// left showing.
    private var hideout: CGPoint {
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(spot) }
            ?? petWindow.screen ?? NSScreen.screens[0]
        let frame = screen.frame
        // A side shared with another display is no hiding place: he would just poke out over there.
        let others = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        let isBeside: (CGRect) -> Bool = { $0.maxY > frame.minY && $0.minY < frame.maxY }
        let leftIsFree = !others.contains { abs($0.maxX - frame.minX) < 2 && isBeside($0) }
        let rightIsFree = !others.contains { abs($0.minX - frame.maxX) < 2 && isBeside($0) }
        let nearerRight = spot.x > frame.midX
        let goesRight = nearerRight ? (rightIsFree || !leftIsFree) : !(leftIsFree || !rightIsFree)
        let peek = 16 * settings.petScale
        return CGPoint(x: goesRight ? frame.maxX + peek : frame.minX - peek, y: spot.y)
    }

    // MARK: - Placement

    private static func windowSize(scale: Double) -> CGSize {
        CGSize(width: PetRenderer.canvas.width * scale, height: PetRenderer.canvas.height * scale)
    }

    /// Where his feet touch down, in screen coordinates (y up).
    private var feetOnScreen: CGPoint {
        let frame = petWindow.frame
        let scale = settings.petScale
        return CGPoint(x: frame.minX + PetRenderer.feet.x * scale, y: frame.maxY - PetRenderer.feet.y * scale)
    }

    private func origin(forFeet feet: CGPoint, scale: Double) -> CGPoint {
        let size = Self.windowSize(scale: scale)
        return CGPoint(x: feet.x - PetRenderer.feet.x * scale, y: feet.y + PetRenderer.feet.y * scale - size.height)
    }

    private func savedSpot() -> CGPoint? {
        UserDefaults.standard.string(forKey: "petFeet").map(NSPointFromString)
    }

    /// Bottom-right corner of the main screen, standing just above the Dock.
    private func defaultSpot() -> CGPoint {
        let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: area.maxX - 150, y: area.minY + 14)
    }

    /// The nearest place to `feet` where all of him can be seen and reached, for when a drag
    /// or a display change would leave him stranded.
    private func onScreen(_ feet: CGPoint) -> CGPoint {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else { return feet }
        let reach = 50 * settings.petScale
        let nearest = screens.first { $0.insetBy(dx: -reach, dy: -reach).contains(feet) }
            ?? screens.min { distance(from: feet, to: $0) < distance(from: feet, to: $1) }!
        return CGPoint(
            x: feet.x.clamped(nearest.minX + reach...max(nearest.minX + reach, nearest.maxX - reach)),
            y: feet.y.clamped(nearest.minY...max(nearest.minY, nearest.maxY - reach * 2))
        )
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(point.x - point.x.clamped(rect.minX...rect.maxX), point.y - point.y.clamped(rect.minY...rect.maxY))
    }

    private func applyScale(_ scale: Double) {
        // Resize around the feet so he grows in place instead of sliding.
        let feet = feetOnScreen
        petView.scale = scale
        petWindow.setFrame(CGRect(origin: origin(forFeet: feet, scale: scale), size: Self.windowSize(scale: scale)), display: true)
        layoutBubble()
    }

    private var selectionPlacement: SelectionPlacement.Result? {
        guard let selection = protectedSelection, let anchor = selectionAnchor else { return nil }
        let allScreens = NSScreen.screens
        let sourceScreen = allScreens.first { $0.frame.contains(anchor) }
            ?? allScreens.first { $0.frame.intersects(selection) }
        let screens = ([sourceScreen].compactMap { $0 } + allScreens.filter { $0 != sourceScreen }).map(\.visibleFrame)
        return SelectionPlacement.place(avoiding: selection, near: anchor, screens: screens,
                                        preferredSize: BubbleLayout.windowSize,
                                        petHead: settings.visitsSelection ? PetRenderer.headTop * settings.petScale : 0,
                                        petHalfWidth: settings.visitsSelection ? 64 * settings.petScale : 0)
    }

    private func clearSelectionPlacement() {
        protectedSelection = nil
        selectionAnchor = nil
        bubbleHasNoSpace = false
        statusItem.button?.title = ""
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.toolTip = "译喵"
    }

    /// Parks the bubble window over his head or under his feet, whichever suits.
    private func layoutBubble() {
        if protectedSelection != nil {
            guard let placement = selectionPlacement else {
                bubbleHasNoSpace = true
                bubbleWindow.alphaValue = 0
                statusItem.button?.title = "译文"
                statusItem.length = NSStatusItem.variableLength
                statusItem.button?.toolTip = "选区周围没有空位，点菜单查看译文"
                return
            }
            bubbleHasNoSpace = false
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.toolTip = "译喵"
            if bubble.windowSize != placement.bubbleFrame.size { bubble.windowSize = placement.bubbleFrame.size }
            bubbleWindow.setFrame(placement.bubbleFrame, display: true)
            if bubble.isBelow != placement.isBelow { bubble.isBelow = placement.isBelow }
            let tailX = placement.feet.x - placement.bubbleFrame.minX
            if bubble.tailX != tailX { bubble.tailX = tailX }
            bubbleWindow.alphaValue = leap == nil ? 1 : 0
            return
        }
        if bubble.windowSize != BubbleLayout.windowSize { bubble.windowSize = BubbleLayout.windowSize }
        bubbleWindow.setContentSize(BubbleLayout.windowSize)
        bubbleWindow.alphaValue = leap == nil ? 1 : 0
        let feet = feetOnScreen
        let scale = settings.petScale
        let size = BubbleLayout.windowSize
        let margin = BubbleLayout.margin
        let area = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let headTop = feet.y + PetRenderer.headTop * scale
        let roomAbove = headTop + size.height - margin <= area.maxY
        let roomBelow = feet.y - 8 + margin - size.height >= area.minY - margin
        // At home the bubble sits on his head. Out visiting it hangs below him, clear of the
        // text he came over to translate.
        let below = isOut ? (roomBelow || !roomAbove) : !roomAbove
        let x = (feet.x - size.width / 2).clamped(area.minX...max(area.minX, area.maxX - size.width))
        // The window's transparent margin overlaps the pet, so the tail ends right at his ears or paws.
        let y = below ? feet.y - 8 + margin - size.height : headTop + 2 - margin
        bubbleWindow.setFrameOrigin(CGPoint(x: x, y: y))
        if bubble.isBelow != below { bubble.isBelow = below }
        let tailX = feet.x - x
        if bubble.tailX != tailX { bubble.tailX = tailX }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if bubbleHasNoSpace, bubble.isVisible {
            add(translation == nil ? "查看译文（选区周围无空位）…" : "查看正在生成的译文…", #selector(showUnobstructedTranslation))
            menu.addItem(.separator())
        }
        add(brain.isAsleep ? "叫醒他" : "哄他睡觉", #selector(toggleSleep))
        add("翻译剪贴板里的文字", #selector(translateClipboard))
        let due = vocabulary.words.filter { !$0.isLearned && $0.due <= Date() }.count
        add(due > 0 ? "生词本（\(due) 个待复习）…" : "生词本…", #selector(openVocabulary))
        menu.addItem(.separator())
        add("设置…", #selector(openSettings), key: ",")
        if !hasAccessibility {
            add("授权辅助功能…", #selector(requestAccessibility))
        }
        add("回到屏幕右下角", #selector(resetPosition))
        menu.addItem(.separator())
        add("退出译喵", #selector(quit), key: "q")
    }

    private func add(_ title: String, _ action: Selector, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    @objc private func toggleSleep() {
        setAsleep(!brain.isAsleep)
    }

    @objc private func translateClipboard() {
        translateOnRequest(NSPasteboard.general.string(forType: .string) ?? "")
    }

    /// Only opens on an explicit click when no overlay can fit without obscuring the source.
    @objc private func showUnobstructedTranslation() {
        let wasTranslating = translation != nil
        let displayedID = translationID
        let alert = NSAlert()
        alert.messageText = "译喵 · \(bubble.caption)"
        alert.informativeText = translation == nil ? "选区周围没有空位，译文在这里查看。" : "翻译仍在生成，可稍后再次查看完整译文。"
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 420, height: 260))
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.font = .systemFont(ofSize: 14)
        text.string = bubble.text.isEmpty ? "正在等待 AI 回应…" : bubble.text
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "复制")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text.string, forType: .string)
        }
        if !wasTranslating, translationID == displayedID {
            bubble.hide()
            clearSelectionPlacement()
            layoutBubble()
        }
    }

    /// Handles `yimiao://translate?text=…`, so other tools can hand him text. Optional `x` and
    /// `y` say where on screen the text is (points from the bottom-left), and he goes there.
    func open(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in items.first { $0.name == name }?.value }
        guard url.scheme == "yimiao", url.host == "translate", let text = value("text") else { return }
        var place: CGPoint?
        if let x = value("x").flatMap(Double.init), let y = value("y").flatMap(Double.init) {
            place = CGPoint(x: x, y: y)
        }
        translateOnRequest(text, near: place)
    }

    /// An explicit ask, unlike a selection: it wakes him and always gets a fresh answer.
    private func translateOnRequest(_ text: String, near place: CGPoint? = nil) {
        setAsleep(false)
        lastSource = ""
        translate(text, near: place)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openVocabulary() {
        vocabularyWindow.show(vocabulary)
    }

    @objc private func requestAccessibility() {
        Permissions.requestAccessibility()
    }

    @objc private func resetPosition() {
        leap = nil
        isOut = false
        clearSelectionPlacement()
        bubbleWindow.alphaValue = 1
        spot = defaultSpot()
        petWindow.setFrameOrigin(origin(forFeet: restingPlace, scale: settings.petScale))
        layoutBubble()
        UserDefaults.standard.removeObject(forKey: "petFeet")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - First words

    private func greet() {
        let defaults = UserDefaults.standard
        if settings.apiKey.isEmpty {
            bubble.say("喵～我是翻译官译喵！\n点这里打开设置，选择 AI 服务并填上 API Key 我就能开工啦", seconds: 15) { [weak self] in
                self?.openSettings()
            }
        } else if !hasAccessibility {
            bubble.say("还差一步：点这里，然后在列表里打开「译喵」的开关，我才看得见你选中的文字", seconds: 15) {
                Permissions.requestAccessibility()
            }
        } else if !defaults.bool(forKey: "hasGreeted") {
            bubble.say("选中任意文字，我就帮你翻译～\n双击我可以哄我睡觉", seconds: 9)
            defaults.set(true, forKey: "hasGreeted")
        }
    }
}
