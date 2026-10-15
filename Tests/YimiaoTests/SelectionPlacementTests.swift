import XCTest
@testable import Yimiao

final class SelectionPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
    private let preferred = CGSize(width: 380, height: 340)

    func testSelectionNearBottomUsesBubbleAbovePet() throws {
        let selection = CGRect(x: 500, y: 65, width: 300, height: 80)
        let result = try XCTUnwrap(place(selection))
        XCTAssertFalse(result.isBelow)
        XCTAssertGreaterThan(result.bubbleFrame.minY, selection.maxY)
        assertSafe(result, selection: selection, screen: screen, scale: 1)
    }

    func testSelectionNearTopUsesBubbleBelowPet() throws {
        let selection = CGRect(x: 500, y: 780, width: 300, height: 80)
        let result = try XCTUnwrap(place(selection))
        XCTAssertTrue(result.isBelow)
        XCTAssertLessThan(result.bubbleFrame.maxY, selection.minY)
        assertSafe(result, selection: selection, screen: screen, scale: 1)
    }

    func testTallSelectionUsesSideAndReservesFullStreamingSize() throws {
        let selection = CGRect(x: 500, y: 80, width: 300, height: 760)
        let result = try XCTUnwrap(place(selection))
        XCTAssertTrue(result.bubbleFrame.minX > selection.maxX || result.bubbleFrame.maxX < selection.minX)
        XCTAssertEqual(result.bubbleFrame.size, preferred)
        assertSafe(result, selection: selection, screen: screen, scale: 1)
    }

    func testWideSelectionGetsCompactScrollableBubble() throws {
        let selection = CGRect(x: 0, y: 425, width: 1440, height: 70)
        let result = try XCTUnwrap(place(selection))
        XCTAssertLessThan(result.bubbleFrame.height, preferred.height)
        XCTAssertGreaterThanOrEqual(result.bubbleFrame.height, SelectionPlacement.minimumBubble.height)
        assertSafe(result, selection: selection, screen: screen, scale: 1)
    }

    func testFullScreenSelectionUsesOtherDisplayOrReturnsNoSpace() throws {
        XCTAssertNil(place(screen))
        let secondary = CGRect(x: -1280, y: -200, width: 1280, height: 900)
        let result = try XCTUnwrap(SelectionPlacement.place(avoiding: screen, near: CGPoint(x: 720, y: 450),
            screens: [screen, secondary], preferredSize: preferred, petHead: 118, petHalfWidth: 64))
        assertSafe(result, selection: screen, screen: secondary, scale: 1)
    }

    func testScreenEdgesReverseDirectionsAndPetScalesNeverOverlap() {
        for display in [screen, CGRect(x: -1440, y: -800, width: 1440, height: 876)] {
            for scale in [0.6, 1.0, 1.8] {
                for x in stride(from: display.minX, through: display.maxX - 100, by: 160) {
                    for y in stride(from: display.minY, through: display.maxY - 40, by: 100) {
                        let selection = CGRect(x: x, y: y, width: 100, height: 40)
                        for anchor in [selection.origin, CGPoint(x: selection.maxX, y: selection.maxY)] {
                            let result = SelectionPlacement.place(avoiding: selection, near: anchor, screens: [display],
                                preferredSize: preferred, petHead: 118 * scale, petHalfWidth: 64 * scale)
                            guard let result else { XCTFail("Small selections should have room"); continue }
                            assertSafe(result, selection: selection, screen: display, scale: scale)
                        }
                    }
                }
            }
        }
    }

    func testFallbackProtectsWholeLineBandForForwardAndReverseDrags() {
        let a = CGPoint(x: 100, y: 600)
        let b = CGPoint(x: 700, y: 300)
        let forward = SelectionPlacement.fallback(start: a, end: b, screen: screen)
        XCTAssertEqual(forward, SelectionPlacement.fallback(start: b, end: a, screen: screen))
        XCTAssertEqual(forward.minX, screen.minX)
        XCTAssertEqual(forward.maxX, screen.maxX)
        XCTAssertTrue(forward.contains(a))
        XCTAssertTrue(forward.contains(b))
        XCTAssertEqual(forward.height, 348)
    }

    func testAXCoordinateConversionUsesPrimaryDisplayIncludingNegativeCoordinates() {
        XCTAssertEqual(SelectionPlacement.appKitRect(CGRect(x: 100, y: 200, width: 300, height: 40), primaryTop: 900),
                       CGRect(x: 100, y: 660, width: 300, height: 40))
        XCTAssertEqual(SelectionPlacement.appKitRect(CGRect(x: -900, y: -300, width: 300, height: 40), primaryTop: 900),
                       CGRect(x: -900, y: 1160, width: 300, height: 40))
        XCTAssertNil(SelectionPlacement.appKitRect(.zero, primaryTop: 900))
        XCTAssertNil(SelectionPlacement.appKitRect(CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1), primaryTop: 900))
    }

    func testAvoidanceAlsoWorksWhenPetDoesNotVisitSelection() throws {
        let selection = CGRect(x: 0, y: 425, width: 1440, height: 70)
        let result = try XCTUnwrap(SelectionPlacement.place(avoiding: selection, near: CGPoint(x: 720, y: 450),
            screens: [screen], preferredSize: preferred, petHead: 0, petHalfWidth: 0))
        XCTAssertFalse(result.bubbleFrame.intersects(selection.insetBy(dx: -12, dy: -12)))
        XCTAssertTrue(screen.contains(result.bubbleFrame))
    }

    private func place(_ selection: CGRect) -> SelectionPlacement.Result? {
        SelectionPlacement.place(avoiding: selection, near: CGPoint(x: selection.midX, y: selection.midY),
                                 screens: [screen], preferredSize: preferred, petHead: 118, petHalfWidth: 64)
    }

    private func assertSafe(_ result: SelectionPlacement.Result, selection: CGRect, screen: CGRect,
                            scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let exclusion = selection.insetBy(dx: -SelectionPlacement.clearance, dy: -SelectionPlacement.clearance)
        XCTAssertFalse(result.bubbleFrame.intersects(exclusion), file: file, line: line)
        XCTAssertTrue(screen.contains(result.bubbleFrame), file: file, line: line)
        let pet = CGRect(x: result.feet.x - 64 * scale, y: result.feet.y, width: 128 * scale, height: 118 * scale)
        XCTAssertFalse(pet.intersects(exclusion), "pet=\(pet), exclusion=\(exclusion)", file: file, line: line)
        XCTAssertTrue(screen.contains(pet), file: file, line: line)
    }
}
