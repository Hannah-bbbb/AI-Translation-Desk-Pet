import XCTest
@testable import Yimiao

/// The dragon: a Chinese, wingless dragon on four clawed legs, nodding his head like the snake,
/// with idle moves of his own.
final class DragonTests: XCTestCase {
    private let frame = 1.0 / 60

    private func dragonBrain() -> PetBrain {
        let brain = PetBrain()
        brain.anatomy = PetRenderer.anatomy(.dragon)
        return brain
    }

    func testDragonPartsFitInsideTheWindow() {
        let canvas = CGRect(x: -PetRenderer.feet.x, y: -PetRenderer.feet.y,
                            width: PetRenderer.canvas.width, height: PetRenderer.canvas.height)
        let dragon = PetRenderer.anatomy(.dragon)
        for (name, box) in [("shadow", dragon.shadowBox), ("tail", dragon.tailBox), ("body", dragon.bodyBox),
                            ("whiskers", dragon.stripesBox), ("face", dragon.faceBox), ("head", dragon.earBox)] {
            XCTAssertTrue(canvas.contains(box), "\(name) \(box) leaves the window \(canvas)")
        }
        for area in dragon.hitAreas {
            XCTAssertLessThanOrEqual(max(-area.minX, area.maxX), dragon.halfWidth + 6)
        }
    }

    /// The tail box must hold the tail however far it swings: asleep, carried, mid-wag.
    func testTailStaysInItsBoxAtEveryAngle() {
        let box = PetRenderer.anatomy(.dragon).tailBox
        for angle in stride(from: -0.5, through: 0.5, by: 0.05) {
            // Draw into a canvas twice as big, the real box in its middle, and look for ink outside it.
            let big = CGContext(data: nil, width: Int(box.width * 2), height: Int(box.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            big.translateBy(x: -box.minX + box.width / 2, y: -box.minY + box.height / 2)
            DragonRenderer.drawTail(angle: angle, skin: .red, in: big)
            let image = big.makeImage()!
            let data = CFDataGetBytePtr(image.dataProvider!.data!)!
            let width = image.width, height = image.height, row = image.bytesPerRow
            var ink = 0
            for y in 0..<height {
                for x in 0..<width where data[y * row + x * 4 + 3] > 0 {
                    ink += 1
                    let inside = x >= Int(box.width / 2) - 1 && x <= Int(box.width * 1.5) + 1
                        && y >= Int(box.height / 2) - 1 && y <= Int(box.height * 1.5) + 1
                    XCTAssertTrue(inside, "tail at angle \(angle) spills out of its box at (\(x), \(y))")
                    if !inside { return }
                }
            }
            XCTAssertGreaterThan(ink, 500, "the tail should have been drawn at angle \(angle)")
        }
    }

    func testDragonCanBeTouchedFromAntlersToTail() {
        let brain = dragonBrain()
        XCTAssertTrue(brain.hitTest(CGPoint(x: -50, y: -78)), "face")
        XCTAssertTrue(brain.hitTest(CGPoint(x: -66, y: -112)), "antler")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 8, y: -40)), "back")
        XCTAssertTrue(brain.hitTest(CGPoint(x: -30, y: -4)), "front paw")
        XCTAssertTrue(brain.hitTest(CGPoint(x: 84, y: -56)), "tail")
        XCTAssertFalse(brain.hitTest(CGPoint(x: 10, y: -100)), "the air over his back")
    }

    func testDragonFindsThingsToDoWhenIdleAndTheCatDoesNot() {
        let dragonish: Set<Particle.Kind> = [.smoke, .flame, .pearl, .cloud]
        func seen(_ brain: PetBrain) -> Set<Particle.Kind> {
            var kinds = Set<Particle.Kind>()
            for _ in 0..<Int(240 / frame) {
                kinds.formUnion(brain.tick(dt: frame).particles.map(\.kind))
            }
            return kinds.intersection(dragonish)
        }
        // One of his moves comes up about one time in three, so four quiet minutes without any is a bug.
        XCTAssertFalse(seen(dragonBrain()).isEmpty, "four idle minutes and no smoke, fire, pearl or clouds")
        XCTAssertTrue(seen(PetBrain()).isEmpty, "the cat keeps his own habits")
    }

    func testEachDragonMoveShowsItsEffect() {
        for (gesture, kind) in [(PetBrain.Gesture.puff, Particle.Kind.smoke), (.sneeze, .flame), (.pearl, .pearl), (.clouds, .cloud)] {
            let brain = dragonBrain()
            brain.perform(gesture)
            var found = false
            for _ in 0..<Int(1.5 / frame) where brain.tick(dt: frame).particles.contains(where: { $0.kind == kind }) {
                found = true
            }
            XCTAssertTrue(found, "\(gesture) should make \(kind)")
        }
    }

    func testSwitchingFromTheDragonBackToTheCatRestoresHim() {
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
        switched.configure(scale: 1, density: 1, look: PetLook(species: .dragon))
        _ = render(switched)
        switched.configure(scale: 1, density: 1)
        XCTAssertEqual(render(fresh), render(switched))
    }
}
