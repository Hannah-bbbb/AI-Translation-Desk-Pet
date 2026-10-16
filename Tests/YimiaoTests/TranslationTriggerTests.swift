import XCTest
@testable import Yimiao

/// Telling a deliberate tap of ⌥ from ⌥ used in a shortcut.
final class TranslationTriggerTests: XCTestCase {
    func testQuickLoneOptionTapIsRecognised() {
        var tap = OptionTap()
        XCTAssertFalse(tap.modifiersChanged(onlyOption: true, none: false, at: 1.0))
        XCTAssertTrue(tap.modifiersChanged(onlyOption: false, none: true, at: 1.2))
    }

    func testOptionUsedForSomethingElseIsNotATap() {
        var held = OptionTap()
        _ = held.modifiersChanged(onlyOption: true, none: false, at: 1.0)
        XCTAssertFalse(held.modifiersChanged(onlyOption: false, none: true, at: 2.0), "held too long")

        var shortcut = OptionTap()
        _ = shortcut.modifiersChanged(onlyOption: true, none: false, at: 1.0)
        shortcut.interrupted()
        XCTAssertFalse(shortcut.modifiersChanged(onlyOption: false, none: true, at: 1.2), "⌥ plus a key or a click")

        var chord = OptionTap()
        _ = chord.modifiersChanged(onlyOption: false, none: false, at: 1.0)  // ⌘⌥ together
        _ = chord.modifiersChanged(onlyOption: true, none: false, at: 1.1)   // ⌘ let go first
        XCTAssertFalse(chord.modifiersChanged(onlyOption: false, none: true, at: 1.2))

        var withShift = OptionTap()
        _ = withShift.modifiersChanged(onlyOption: true, none: false, at: 1.0)
        _ = withShift.modifiersChanged(onlyOption: false, none: false, at: 1.05)  // ⌥⇧
        _ = withShift.modifiersChanged(onlyOption: true, none: false, at: 1.1)
        XCTAssertFalse(withShift.modifiersChanged(onlyOption: false, none: true, at: 1.2))
    }
}
