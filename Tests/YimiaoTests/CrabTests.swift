import XCTest
@testable import Yimiao

/// The pixel crab: drawn in pixel steps from the shared brain, with idle moves of his own.
final class CrabTests: XCTestCase {
    private let frame = 1.0 / 60

    private func crabBrain() -> PetBrain {
        let brain = PetBrain()
        brain.anatomy = PetRenderer.anatomy(.crab)
        return brain
    }

    func testCrabFitsInsideTheWindow() {
        let canvas = CGRect(x: -PetRenderer.feet.x, y: -PetRenderer.feet.y,
                            width: PetRenderer.canvas.width, height: PetRenderer.canvas.height)
        let crab = PetRenderer.anatomy(.crab)
        XCTAssertTrue(canvas.contains(crab.faceBox), "his one layer, scuttle room included, must fit the window")
        XCTAssertTrue(canvas.contains(crab.shadowBox))
        // Twelve pixels wide with his arms, eight tall with his legs.
        XCTAssertEqual(crab.headTop, 8 * CrabRenderer.unit)
        XCTAssertGreaterThanOrEqual(crab.halfWidth, 6 * CrabRenderer.unit)
    }

    func testCrabCanBeTouchedOnHisBodyArmsAndLegs() {
        let brain = crabBrain()
        let u = CrabRenderer.unit
        XCTAssertTrue(brain.hitTest(CGPoint(x: -4 * u + 1, y: -8 * u + 1)), "top-left corner of his body")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 6 * u - 1, y: -5 * u)), "tip of his right arm")
        XCTAssertTrue(brain.hitTest(CGPoint(x: -3.5 * u, y: -1)), "a front leg")
        XCTAssertFalse(brain.hitTest(CGPoint(x: 0, y: -12 * u)), "the air above him")
    }

    func testEyesNeverReachTheEdgeOfHisBody() {
        var pose = PetPose()
        for dx in [-1.0, 1.0] {
            for dy in [-1.0, 1.0] {
                pose.lookL = CGVector(dx: dx, dy: dy)
                pose.lookR = CGVector(dx: dx, dy: dy)
                pose.face = CGVector(dx: dx, dy: dy)
                let f = CrabRenderer.frame(for: pose, outfit: .none)
                XCTAssertTrue((-1...1).contains(f.lookX) && (-1...1).contains(f.lookY), "\(f.lookX), \(f.lookY)")
            }
        }
    }

    func testRestingPoseCostsNoRedraws() {
        let brain = crabBrain()
        for _ in 0..<60 { _ = brain.tick(dt: frame) }
        // Breathing and the lazy tail sway are far below a pixel, so the frame holds still.
        var keys = Set<[Int32]>()
        for _ in 0..<60 {
            let pose = brain.tick(dt: frame)
            guard pose.eyeOpen > 0.9 else { continue }
            keys.insert(CrabRenderer.frame(for: pose, outfit: .none).key)
        }
        XCTAssertLessThanOrEqual(keys.count, 2, "a still crab must not redraw every frame")
    }

    func testCrabFindsThingsToDoWhenIdleAndTheCatDoesNot() {
        func moves(_ brain: PetBrain) -> (scuttled: Bool, snapped: Bool, bubbles: Bool) {
            var result = (scuttled: false, snapped: false, bubbles: false)
            for _ in 0..<Int(240 / frame) {
                let pose = brain.tick(dt: frame)
                if abs(pose.scuttle) > CrabRenderer.unit { result.scuttled = true }
                if pose.claw > 0.5 { result.snapped = true }
                if pose.particles.contains(where: { $0.kind == .bubble }) { result.bubbles = true }
            }
            return result
        }
        // Idle moves are picked at random; one of these three comes up about one time in five,
        // so four minutes without any of them would be a broken schedule, not bad luck.
        let crab = moves(crabBrain())
        XCTAssertTrue(crab.scuttled || crab.snapped || crab.bubbles, "four idle minutes and nothing a crab would do")
        let cat = moves(PetBrain())
        XCTAssertFalse(cat.scuttled || cat.snapped || cat.bubbles, "the cat keeps his own habits")
    }

    func testScuttlingStepsHisLegs() {
        let brain = crabBrain()
        brain.perform(.scuttle)
        var steps = Set<Int>()
        for _ in 0..<Int(2.6 / frame) {
            steps.insert(CrabRenderer.frame(for: brain.tick(dt: frame), outfit: .none).scuttle)
        }
        XCTAssertTrue(steps.contains(where: { $0 % 2 != 0 }), "mid-step frames lift every other leg")
        XCTAssertTrue(steps.contains(where: { $0 >= 3 }), "he gets a couple of pixels away")
        XCTAssertEqual(CrabRenderer.frame(for: brain.tick(dt: frame), outfit: .none).scuttle, 0, "and comes back")
    }

    func testAsleepHeSitsWithArmsDownAndANightcap() {
        let brain = crabBrain()
        brain.fallAsleep()
        var pose = PetPose()
        for _ in 0..<Int(7 / frame) { pose = brain.tick(dt: frame) }
        let f = CrabRenderer.frame(for: pose, outfit: .none)
        XCTAssertEqual(f.eyes, .sleeping)
        XCTAssertEqual(f.hat, .nightcap)
        XCTAssertLessThan(f.legs, 4, "sitting down")
        XCTAssertGreaterThan(f.armL, 0)
        XCTAssertGreaterThan(f.armR, 0)
    }

    func testSwitchingFromTheCrabBackToTheCatRestoresHim() {
        let pose = PetBrain().tick(dt: frame)
        func render(_ stage: PetStage) -> Data? {
            stage.show(pose)
            let size = PetRenderer.canvas
            guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            stage.layer.render(in: ctx)
            return ctx.makeImage()?.dataProvider?.data as Data?
        }
        let fresh = PetStage()
        fresh.configure(scale: 1, density: 1)
        let switched = PetStage()
        switched.configure(scale: 1, density: 1, look: PetLook(species: .crab))
        _ = render(switched)
        switched.configure(scale: 1, density: 1, look: PetLook(species: .snake))
        _ = render(switched)
        switched.configure(scale: 1, density: 1)
        XCTAssertEqual(render(fresh), render(switched))
    }
}
