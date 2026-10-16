import XCTest
@testable import Yimiao

/// The cat-like behaviours: playing, typing, music, battery, window seats, outfits and the
/// daily tally.
final class CatLifeTests: XCTestCase {
    private let frame = 1.0 / 60

    // MARK: - Teasing and pouncing

    func testWavingBackAndForthCountsAsTeasing() {
        var teasing = Teasing()
        var time = 0.0
        // Four sweeps of 60 points in under two seconds.
        for sweep in 0..<5 {
            for step in 0...10 {
                let x = sweep.isMultiple(of: 2) ? Double(step) * 6 : 60 - Double(step) * 6
                teasing.track(x, at: time)
                time += 0.035
            }
        }
        XCTAssertTrue(teasing.isTeasing(at: time))
    }

    func testJitterAndSlowPassesAreNotTeasing() {
        var jitter = Teasing()
        var time = 0.0
        for step in 0..<120 {
            jitter.track(Double(step % 2) * 5, at: time)
            time += 0.016
        }
        XCTAssertFalse(jitter.isTeasing(at: time), "wobbles shorter than a sweep do not count")

        var slow = Teasing()
        time = 0
        for sweep in 0..<5 {
            for step in 0...10 {
                slow.track(sweep.isMultiple(of: 2) ? Double(step) * 6 : 60 - Double(step) * 6, at: time)
                time += 0.12
            }
        }
        XCTAssertFalse(slow.isTeasing(at: time), "turns spread over many seconds are just moving around")
    }

    func testWavedCursorInFrontEndsInAPounce() {
        let brain = PetBrain()
        brain.mayPlay = true
        let target = wave(brain, y: -60, seconds: 4)
        let pounce = try? XCTUnwrap(target)
        XCTAssertNotNil(pounce)
        XCTAssertLessThan(abs(pounce?.x ?? 999), 300)
    }

    func testNoPounceWhenBusyOnHimOrDragging() {
        let busy = PetBrain()
        busy.mayPlay = false
        XCTAssertNil(wave(busy, y: -60, seconds: 4), "not while he has a job to do")

        let stroked = PetBrain()
        stroked.mayPlay = true
        XCTAssertNil(wave(stroked, y: -50, seconds: 4, around: 0, amplitude: 20), "back and forth on his body is petting")

        let dragging = PetBrain()
        dragging.mayPlay = true
        dragging.mouseButtonDown = true
        XCTAssertNil(wave(dragging, y: -60, seconds: 4), "a held button is a selection or a drag, not a toy")
    }

    // MARK: - Typing, music, battery

    func testSustainedFastTypingImpressesHim() {
        let brain = PetBrain()
        var sparks = false
        for frameIndex in 0..<(60 * 5) {
            // Eight keys a second.
            if frameIndex % 7 == 0 { brain.keyTapped() }
            brain.updateMouse(CGPoint(x: 40, y: -160), travel: 0, dt: frame)
            let pose = brain.tick(dt: frame)
            sparks = sparks || pose.particles.contains { $0.kind == .spark }
        }
        XCTAssertTrue(sparks)
    }

    func testMusicMakesHimNodAndSing() {
        let brain = PetBrain()
        brain.hearsMusic = true
        var faces: [Double] = []
        var notes = false
        for _ in 0..<(60 * 4) {
            brain.updateMouse(CGPoint(x: 40, y: -160), travel: 0, dt: frame)
            let pose = brain.tick(dt: frame)
            faces.append(pose.face.dy)
            notes = notes || pose.particles.contains { $0.kind == .note }
        }
        XCTAssertTrue(notes)
        XCTAssertGreaterThan((faces.max() ?? 0) - (faces.min() ?? 0), 0.15, "his head bobs")
    }

    func testFlatBatteryMakesHimDroopyAndChargingPerksHimUp() {
        let tired = PetBrain()
        tired.energy = .low
        let fresh = PetBrain()
        var tiredEyes = 0.0, freshEyes = 0.0, tiredEars = 0.0
        for _ in 0..<(60 * 3) {
            tired.updateMouse(CGPoint(x: 40, y: -160), travel: 0, dt: frame)
            fresh.updateMouse(CGPoint(x: 40, y: -160), travel: 0, dt: frame)
            let t = tired.tick(dt: frame)
            let f = fresh.tick(dt: frame)
            tiredEyes += t.eyeOpen
            freshEyes += f.eyeOpen
            tiredEars += t.earL
        }
        XCTAssertLessThan(tiredEyes, freshEyes * 0.8)
        XCTAssertGreaterThan(tiredEars, 0)

        tired.energy = .full
        tired.recharged()
        let pose = tired.tick(dt: frame)
        XCTAssertTrue(pose.particles.contains { $0.kind == .bolt })
    }

    func testBatteryReadingIsAPercentageWhenThereIsABattery() {
        // Desktop Macs have none, and that is fine.
        guard let reading = Battery.read() else { return }
        XCTAssertTrue((0...100).contains(reading.percent))
    }

    // MARK: - Outfits

    func testFestivalOutfitsFollowTheCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func on(_ y: Int, _ m: Int, _ d: Int) -> Outfit {
            Outfit.festival(on: calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!, calendar: calendar)
        }
        XCTAssertEqual(on(2026, 10, 16), .none)
        XCTAssertEqual(on(2026, 10, 24), .witch)
        XCTAssertEqual(on(2026, 11, 1), .witch)
        XCTAssertEqual(on(2026, 11, 2), .none)
        XCTAssertEqual(on(2026, 12, 24), .santa)
        XCTAssertEqual(on(2026, 12, 27), .none)
        // Lunar 12/23 to 1/15 in 2027: 30 January to 20 February.
        XCTAssertEqual(on(2027, 1, 29), .none)
        XCTAssertEqual(on(2027, 1, 30), .newYear)
        XCTAssertEqual(on(2027, 2, 6), .newYear)
        XCTAssertEqual(on(2027, 2, 20), .newYear)
        XCTAssertEqual(on(2027, 2, 21), .none)
    }

    // MARK: - Daily tally

    func testDaySavedByAnOlderVersionStillLoads() throws {
        let old = #"{"date":"2026-10-16","greeted":true,"saidOffWork":false,"translations":7}"#
        let day = try JSONDecoder().decode(Companion.Day.self, from: Data(old.utf8))
        XCTAssertTrue(day.greeted, "no second good morning after the upgrade")
        XCTAssertEqual(day.translations, 7)
        XCTAssertEqual(day.newWords, 0)
        XCTAssertEqual(day.breaks, 0)
    }

    func testBreaksAndWordsAreCountedWithinTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!
        var companion = Companion()
        let quiet = Companion.Preferences(greets: false, breakMinutes: 0, offWorkMinute: nil, bedtimeMinute: nil, quizzes: false)

        func present(from start: Date, minutes: Int) {
            for second in stride(from: 0, to: minutes * 60, by: 30) {
                _ = companion.tick(now: start.addingTimeInterval(Double(second)), idle: 1, preferences: quiet, calendar: calendar) { true }
            }
        }
        present(from: morning, minutes: 60)
        present(from: morning.addingTimeInterval(70 * 60), minutes: 30)   // 10 minutes away: a break
        present(from: morning.addingTimeInterval(102 * 60), minutes: 10)  // 2 minutes away: not one
        companion.learnedWord(now: morning.addingTimeInterval(110 * 60), calendar: calendar)
        companion.translated(now: morning.addingTimeInterval(110 * 60), calendar: calendar)
        XCTAssertEqual(companion.day.breaks, 1)
        XCTAssertEqual(companion.day.newWords, 1)
        XCTAssertEqual(Lines.summary(companion.day), "今日小结：翻译 1 段 · 新词 1 个 · 休息 1 次")

        // Overnight is not a break taken today.
        present(from: morning.addingTimeInterval(24 * 3600), minutes: 5)
        XCTAssertEqual(companion.day.breaks, 0)
        XCTAssertNil(Lines.summary(companion.day))
    }

    func testLowBatteryIsMentionedOnceAndForgottenWhenPluggedIn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quiet = Companion.Preferences(greets: false, breakMinutes: 0, offWorkMinute: nil, bedtimeMinute: nil, quizzes: false)
        var companion = Companion()
        _ = companion.tick(now: now, idle: 1, preferences: quiet) { true }
        companion.batteryLow(percent: 9)
        XCTAssertEqual(companion.tick(now: now.addingTimeInterval(1), idle: 1, preferences: quiet) { true }, .lowBattery(percent: 9))
        XCTAssertNil(companion.tick(now: now.addingTimeInterval(2000), idle: 1, preferences: quiet) { true })

        var plugged = Companion()
        _ = plugged.tick(now: now, idle: 1, preferences: quiet) { true }
        plugged.batteryLow(percent: 8)
        plugged.batteryRecovered()
        XCTAssertNil(plugged.tick(now: now.addingTimeInterval(1), idle: 1, preferences: quiet) { true })
    }

    // MARK: - Window seats

    func testSeatSitsOnTheTopEdgeWithinWindowAndScreen() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let window = CGRect(x: 200, y: 100, width: 800, height: 500)
        let feet = try XCTUnwrap(WindowSeat.seat(on: window, fraction: 0.7, halfWidth: 62, height: 118, screens: [screen]))
        XCTAssertEqual(feet.y, window.maxY - 1)
        XCTAssertEqual(feet.x, window.minX + 560, accuracy: 0.5)

        // Far right: kept inside both the window and the screen.
        let edge = CGRect(x: 1000, y: 100, width: 700, height: 500)
        let clamped = try XCTUnwrap(WindowSeat.seat(on: edge, fraction: 0.95, halfWidth: 62, height: 118, screens: [screen]))
        XCTAssertLessThanOrEqual(clamped.x, screen.maxX - 62)
    }

    func testNoSeatWithoutHeadroomOrOnANarrowWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let tall = CGRect(x: 200, y: 100, width: 800, height: 700)
        XCTAssertNil(WindowSeat.seat(on: tall, fraction: 0.7, halfWidth: 62, height: 118, screens: [screen]))
        let narrow = CGRect(x: 200, y: 100, width: 150, height: 300)
        XCTAssertNil(WindowSeat.seat(on: narrow, fraction: 0.5, halfWidth: 62, height: 118, screens: [screen]))
    }

    func testWindowInFrontOfHisSeatCoversHim() {
        let body = WindowSeat.body(at: CGPoint(x: 600, y: 600), halfWidth: 62, height: 118)
        XCTAssertTrue(WindowSeat.isCovered(body, by: [CGRect(x: 500, y: 550, width: 400, height: 400)]))
        XCTAssertFalse(WindowSeat.isCovered(body, by: [CGRect(x: 900, y: 550, width: 400, height: 400)]))
    }

    // MARK: - Helpers

    /// Waves the cursor side to side in front of him and returns where he pounced, if he did.
    private func wave(_ brain: PetBrain, y: Double, seconds: Double, around centre: Double = 140, amplitude: Double = 60) -> CGPoint? {
        var last = CGPoint(x: centre, y: y)
        for frameIndex in 0..<Int(seconds * 60) {
            let time = Double(frameIndex) * frame
            let point = CGPoint(x: centre + sin(time * 2 * .pi * 2.2) * amplitude, y: y)
            brain.updateMouse(point, travel: hypot(point.x - last.x, point.y - last.y), dt: frame)
            last = point
            _ = brain.tick(dt: frame)
            if let target = brain.takePounce() { return target }
        }
        return nil
    }
}
