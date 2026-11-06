import XCTest
@testable import Yimiao

/// The snake shares the cat's window, brain and layers; these check that his shape fits that
/// window and that the cat did not change along the way.
final class SnakeTests: XCTestCase {
    private let frame = 1.0 / 60

    /// Every part of the snake must lie inside the window, or it would be cut off on screen.
    func testSnakePartsFitInsideTheWindow() {
        let canvas = CGRect(x: -PetRenderer.feet.x, y: -PetRenderer.feet.y,
                            width: PetRenderer.canvas.width, height: PetRenderer.canvas.height)
        let snake = PetRenderer.anatomy(.snake)
        for (name, box) in [("shadow", snake.shadowBox), ("tail", snake.tailBox), ("body", snake.bodyBox),
                            ("pattern", snake.stripesBox), ("face", snake.faceBox), ("head", snake.earBox)] {
            XCTAssertTrue(canvas.contains(box), "\(name) \(box) leaves the window \(canvas)")
        }
        for area in snake.hitAreas {
            XCTAssertLessThanOrEqual(max(-area.minX, area.maxX), snake.halfWidth + 6,
                                     "his half width must cover all of him that can be touched")
        }
    }

    func testCatShapeIsUnchanged() {
        let cat = PetRenderer.anatomy(.cat)
        // Heights the bubble and window seats used before the snake existed.
        XCTAssertEqual(cat.height(wearing: .none), 118)
        XCTAssertEqual(cat.height(wearing: .newYear), 118)
        XCTAssertEqual(cat.height(wearing: .santa), 118 + 26)
        XCTAssertEqual(cat.height(wearing: .witch), 118 + 36)
        XCTAssertEqual(cat.headX, 0)

        // The old hit test: an ellipse 64 wide and 68 tall either side of a point 54 above the feet.
        let brain = PetBrain()
        XCTAssertTrue(brain.hitTest(CGPoint(x: 0, y: -54)))
        XCTAssertTrue(brain.hitTest(CGPoint(x: 63, y: -54)))
        XCTAssertFalse(brain.hitTest(CGPoint(x: 65, y: -54)))
        XCTAssertTrue(brain.hitTest(CGPoint(x: 0, y: -121)))
        XCTAssertFalse(brain.hitTest(CGPoint(x: 0, y: -123)))
    }

    func testSnakeCanBeTouchedFromHeadToTail() {
        let brain = PetBrain()
        brain.anatomy = PetRenderer.anatomy(.snake)
        XCTAssertTrue(brain.hitTest(CGPoint(x: -46, y: -54)), "head")
        XCTAssertTrue(brain.hitTest(CGPoint(x: -44, y: -32)), "neck")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 10, y: -12)), "middle of the body")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 88, y: -16)), "end of the body")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 94, y: -36)), "tail tip")
        XCTAssertFalse(brain.hitTest(CGPoint(x: 20, y: -70)), "the empty air above his back")
        XCTAssertFalse(brain.hitTest(CGPoint(x: 0, y: -118)), "where the cat's ears would be")
    }

    /// Hats get smaller on his small head and the bubble must clear the top of them.
    func testSnakeHeightAllowsForHats() {
        let snake = PetRenderer.anatomy(.snake)
        XCTAssertEqual(snake.height(wearing: .none), snake.headTop)
        XCTAssertGreaterThan(snake.height(wearing: .santa), snake.headTop)
        XCTAssertGreaterThan(snake.height(wearing: .witch), snake.height(wearing: .santa))
        XCTAssertLessThan(snake.height(wearing: .witch), PetRenderer.anatomy(.cat).height(wearing: .witch))
    }

    func testTongueFlicksWhileAwakeButNotAsleep() {
        let brain = PetBrain()
        var flicked = false
        for _ in 0..<Int(10 / frame) where brain.tick(dt: frame).tongue > 0.5 {
            flicked = true
        }
        XCTAssertTrue(flicked, "an idle snake tastes the air every few seconds")

        brain.fallAsleep()
        for _ in 0..<Int(3 / frame) { _ = brain.tick(dt: frame) }
        for _ in 0..<Int(10 / frame) {
            XCTAssertEqual(brain.tick(dt: frame).tongue, 0, "no tongue in his sleep")
        }
    }

    func testSpottingASelectionFlicksTheTongueAtOnce() {
        let brain = PetBrain()
        _ = brain.tick(dt: frame)
        brain.notice()
        let peak = (0..<20).map { _ in brain.tick(dt: frame).tongue }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.5)
    }

    /// Switching animals back and forth must leave the cat drawn exactly as before.
    func testSwitchingBackToTheCatRestoresHim() {
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
        switched.configure(scale: 1, density: 1, look: PetLook(species: .snake))
        _ = render(switched)
        switched.configure(scale: 1, density: 1)
        XCTAssertEqual(render(fresh), render(switched))
    }
}
