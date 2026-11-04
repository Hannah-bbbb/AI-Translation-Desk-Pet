import AppKit
import XCTest
@testable import Yimiao

final class PetGeometryTests: XCTestCase {
    func testSmallPetLandingUsedToRestartTheSameJumpForever() {
        let scale = 0.6
        let target = CGPoint(x: 1362, y: 78)
        // Actual frame reproduced on the attached Retina + non-Retina display arrangement.
        let frame = CGRect(x: 1300, y: 64, width: 132, height: 120)
        let feet = PetGeometry.feet(in: frame, scale: scale)
        XCTAssertGreaterThan(hypot(target.x - feet.x, target.y - feet.y), 1,
                             "The old settle condition would start another jump at every landing")
        XCTAssertTrue(PetGeometry.hasArrived(frame: frame, at: target, scale: scale))
        XCTAssertFalse(PetGeometry.hasArrived(frame: frame, at: CGPoint(x: target.x + 10, y: target.y), scale: scale),
                       "A genuine move must still trigger a jump")
    }

    func testCoordinateRoundTripDoesNotDriftAtAnySupportedScale() {
        let points = [CGPoint(x: 1362, y: 78), CGPoint(x: 3282, y: -29), CGPoint(x: -1920.1, y: 1000.7),
                      CGPoint(x: 50.3, y: -1080.3)]
        for step in 60...180 {
            let scale = CGFloat(step) / 100
            for point in points {
                let initial = CGRect(origin: PetGeometry.origin(forFeet: point, scale: scale), size: PetGeometry.windowSize(scale: scale))
                var frame = initial
                for _ in 0..<10 {
                    let feet = PetGeometry.feet(in: frame, scale: scale)
                    frame.origin = PetGeometry.origin(forFeet: feet, scale: scale)
                    XCTAssertEqual(frame, initial, "Coordinate conversions must not walk the pet across the screen")
                    XCTAssertTrue(PetGeometry.hasArrived(frame: frame, at: point, scale: scale))
                }
            }
        }
    }

    @MainActor
    func testNativePanelsSettleAfterOneMoveOnEveryConnectedScreen() {
        _ = NSApplication.shared
        for screen in NSScreen.screens {
            for scale: CGFloat in [0.6, 0.65, 1, 1.33, 1.8] {
                let panel = OverlayPanel(size: PetGeometry.windowSize(scale: scale))
                defer { panel.close() }
                let home = CGPoint(x: screen.visibleFrame.maxX - 150, y: screen.visibleFrame.minY + 14)
                for target in [home, CGPoint(x: screen.frame.maxX + 16 * scale, y: home.y)] {
                    panel.setFrameOrigin(CGPoint(x: screen.frame.midX, y: screen.frame.midY))
                    var jumps = 0
                    // Equivalent to repeated settle/landing cycles; no visible windows or real requests.
                    for _ in 0..<120 {
                        if !PetGeometry.hasArrived(frame: panel.frame, at: target, scale: scale) {
                            jumps += 1
                            panel.setFrameOrigin(PetGeometry.origin(forFeet: target, scale: scale))
                        }
                    }
                    XCTAssertEqual(jumps, 1, "Must land once, including offscreen video hideouts")
                }
            }
        }
    }

    func testSharedScreenEdgeBelongsToTheScreenContainingTheFeet() {
        let main = CGRect(x: 0, y: 64, width: 1512, height: 885)
        let secondary = CGRect(x: 1512, y: -43, width: 1920, height: 1050)
        let start = CGPoint(x: 1520, y: 200)
        let home = PetGeometry.onScreen(start, screens: [main, secondary], halfWidth: 38.4, height: 70.8)
        XCTAssertTrue(secondary.contains(home))
        XCTAssertEqual(home.x, secondary.minX + 38.4, accuracy: 0.001)
        XCTAssertEqual(home, PetGeometry.onScreen(start, screens: [secondary, main], halfWidth: 38.4, height: 70.8))
        XCTAssertEqual(home, PetGeometry.onScreen(home, screens: [main, secondary], halfWidth: 38.4, height: 70.8))
    }

    func testUnpluggedOrVerticallyArrangedDisplayReturnsAVisibleHome() {
        let main = CGRect(x: 0, y: 64, width: 1512, height: 885)
        let points = [CGPoint(x: 3282, y: -29), CGPoint(x: -1700, y: -800), CGPoint(x: 600, y: 1900)]
        for point in points {
            let home = PetGeometry.onScreen(point, screens: [main], halfWidth: 64, height: 154)
            XCTAssertTrue(main.contains(home))
            XCTAssertLessThanOrEqual(home.y + 154, main.maxY, "Reserve actual ears and hat height")
        }
        let above = CGRect(x: -300, y: 982, width: 1920, height: 1050)
        let home = PetGeometry.onScreen(CGPoint(x: -100, y: 1950), screens: [main, above], halfWidth: 64, height: 154)
        XCTAssertTrue(above.contains(home))
    }

    @MainActor
    func testResizingUsesThePreviouslyRenderedScaleForTheFootAnchor() {
        _ = NSApplication.shared
        let home = CGPoint(x: 700, y: 400)
        let panel = OverlayPanel(size: PetGeometry.windowSize(scale: 0.6))
        defer { panel.close() }
        panel.setFrameOrigin(PetGeometry.origin(forFeet: home, scale: 0.6))
        let oldFeet = PetGeometry.feet(in: panel.frame, scale: 0.6)
        for scale: CGFloat in [1.8, 0.65, 1, 0.6] {
            panel.setFrame(CGRect(origin: PetGeometry.origin(forFeet: oldFeet, scale: scale),
                                 size: PetGeometry.windowSize(scale: scale)), display: false)
            let newFeet = PetGeometry.feet(in: panel.frame, scale: scale)
            XCTAssertLessThan(abs(newFeet.x - oldFeet.x), 1.01)
            XCTAssertLessThan(abs(newFeet.y - oldFeet.y), 1.01)
            XCTAssertTrue(PetGeometry.hasArrived(frame: panel.frame, at: oldFeet, scale: scale))
        }
    }
}
