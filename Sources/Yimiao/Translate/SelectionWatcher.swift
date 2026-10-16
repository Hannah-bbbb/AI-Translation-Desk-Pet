import AppKit
import ApplicationServices

/// Notices when the user selects text in any app and reports what they selected.
///
/// The selection is read through the Accessibility API. Apps that do not expose it that way
/// (Chromium browsers, Electron apps) are handled by briefly pressing ⌘C and putting the
/// clipboard back afterwards.
@MainActor
final class SelectionWatcher {
    /// Text, mouse release point (if any), and a protected rectangle in AppKit screen coordinates.
    var onSelection: ((String, CGPoint?, CGRect?) -> Void)?
    /// Called when the user selected something but Accessibility access is missing.
    var onBlocked: (() -> Void)?
    /// Asked before every read, so a sleeping pet costs nothing.
    var isEnabled: () -> Bool = { true }
    var allowsClipboardFallback: () -> Bool = { true }
    /// When true, only selections made while holding ⌥ count, or ones followed by a tap of ⌥.
    var requiresOption: () -> Bool = { false }

    private var monitors: [Any] = []
    private var pressPoint = CGPoint.zero
    private var pending: Task<Void, Never>?
    private var optionTap = OptionTap()
    /// The last selection made without ⌥, in case a tap of ⌥ follows to ask for it.
    private var unclaimed: Gesture?

    /// How a selection was made: where the pointer let go, if it was the mouse.
    private struct Gesture {
        var at = Date()
        var pointer: CGPoint?
        var dragStart: CGPoint
        var extendsPrevious = false
    }

    func start() {
        guard monitors.isEmpty else { return }
        listen(.leftMouseDown) { [weak self] _ in
            self?.pressPoint = NSEvent.mouseLocation
            self?.optionTap.interrupted()
        }
        listen(.leftMouseUp) { [weak self] event in
            self?.mouseReleased(event)
        }
        listen(.keyUp) { [weak self] event in
            self?.keyReleased(event)
        }
        listen(.keyDown) { [weak self] _ in
            self?.optionTap.interrupted()
        }
        listen(.flagsChanged) { [weak self] event in
            self?.modifiersChanged(event)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pending?.cancel()
    }

    /// Key events only start arriving once Accessibility access is granted, and only to
    /// monitors installed afterwards.
    func restart() {
        stop()
        start()
    }

    private func listen(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    // MARK: - Triggers

    private func mouseReleased(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dragged = hypot(point.x - pressPoint.x, point.y - pressPoint.y) > 6
        let multiClick = event.clickCount >= 2
        // A plain click only moves the caret; these three are the ways a mouse selects text.
        guard dragged || multiClick || event.modifierFlags.contains(.shift) else { return }
        let gesture = Gesture(pointer: point, dragStart: pressPoint, extendsPrevious: event.modifierFlags.contains(.shift))
        if requiresOption(), !event.modifierFlags.contains(.option) {
            unclaimed = gesture
            return
        }
        // After a double-click, wait out a possible third click before reading.
        check(after: multiClick ? 0.3 : 0.1, gesture)
    }

    private func keyReleased(_ event: NSEvent) {
        let flags = event.modifierFlags
        let navigation: Set<UInt16> = [123, 124, 125, 126, 115, 116, 119, 121]  // arrows, home, end, page up/down
        let extendsSelection = flags.contains(.shift) && navigation.contains(event.keyCode)
        let selectsAll = flags.contains(.command) && event.keyCode == 0  // ⌘A
        guard extendsSelection || selectsAll else { return }
        let gesture = Gesture(dragStart: pressPoint)
        if requiresOption(), !flags.contains(.option) {
            unclaimed = gesture
            return
        }
        // Long enough that holding ⇧→ across a sentence reads once, at the end.
        check(after: 0.5, gesture)
    }

    /// In ⌥ mode, a quick tap of ⌥ on its own asks for the selection just made, or failing
    /// that, whatever is selected right now.
    private func modifiersChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard optionTap.modifiersChanged(onlyOption: flags == .option, none: flags.isEmpty, at: event.timestamp),
              requiresOption()
        else { return }
        let recent = unclaimed.flatMap { Date().timeIntervalSince($0.at) < 30 ? $0 : nil }
        unclaimed = nil
        check(after: 0.05, recent ?? Gesture(dragStart: pressPoint))
    }

    private func check(after delay: Double, _ gesture: Gesture) {
        let pointer = gesture.pointer
        let fromMouse = pointer != nil
        let dragStart = gesture.dragStart
        let extendsPrevious = gesture.extendsPrevious
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.isEnabled() else { return }
            // Without the grant every read below fails quietly, which looks exactly like
            // "nothing selected". Say so instead.
            guard AXIsProcessTrusted() else {
                Log.selection.notice("blocked: no Accessibility access")
                self.onBlocked?()
                return
            }
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier ?? ""
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0

            // Accessibility calls block on the other app, so they stay off the main thread.
            let answer = await Task.detached(priority: .userInitiated) {
                Self.accessibilitySelection(pid: pid, bundleID: bundleID)
            }.value
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }

            var text: String?
            var bounds: CGRect?
            var focusedBounds: CGRect?
            var route = "accessibility"
            switch answer {
            case .text(let selected, let rect, let focused):
                text = selected
                bounds = rect.flatMap { SelectionPlacement.appKitRect($0, primaryTop: primaryTop) }
                focusedBounds = focused.flatMap { SelectionPlacement.appKitRect($0, primaryTop: primaryTop) }
            case .nothing:
                break
            case .unknown(let rect, let focused):
                bounds = rect.flatMap { SelectionPlacement.appKitRect($0, primaryTop: primaryTop) }
                focusedBounds = focused.flatMap { SelectionPlacement.appKitRect($0, primaryTop: primaryTop) }
                // Keyboard triggers never fall back: a stray ⌘C mid-typing is not worth the risk.
                if fromMouse, self.allowsClipboardFallback(), !Self.neverCopyFrom.contains(bundleID) {
                    route = "clipboard"
                    text = await self.copySelection()
                } else {
                    route = "none"
                }
            }
            Log.selection.notice("\(bundleID, privacy: .public) via \(route, privacy: .public): \(text?.count ?? 0) characters")
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let text, !text.isEmpty else { return }
            if bounds == nil {
                if let pointer, !extendsPrevious,
                   let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
                    bounds = SelectionPlacement.fallback(start: dragStart, end: pointer, screen: screen.frame)
                } else {
                    // A keyboard/shift extension can start anywhere in the focused text control.
                    bounds = focusedBounds ?? NSScreen.main?.frame
                }
            }
            self.onSelection?(text, pointer, bounds)
        }
    }

    // MARK: - Accessibility

    private enum Answer: Sendable {
        case text(String, CGRect?, CGRect?)
        /// The app answered and nothing is selected.
        case nothing
        /// The app could not say either way.
        case unknown(CGRect?, CGRect?)
    }

    /// Apps where a synthetic ⌘C would copy files or do nothing useful.
    private static let neverCopyFrom: Set<String> = ["com.apple.finder", "com.apple.dock"]

    /// Controls whose empty answer can be believed.
    nonisolated private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXStaticText"]

    nonisolated private static func accessibilitySelection(pid: pid_t, bundleID: String) -> Answer {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return .unknown(nil, nil) }
        let focused = unsafeDowncast(focusedRef, to: AXUIElement.self)
        let focusedBounds = elementBounds(focused)
        var range: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &range)
        var bounds: CGRect?
        if let range, CFGetTypeID(range) == AXValueGetTypeID() {
            let value = unsafeDowncast(range, to: AXValue.self)
            var characters = CFRange()
            if AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &characters), characters.length > 0 {
                bounds = rangeBounds(focused, parameter: range, attribute: kAXBoundsForRangeParameterizedAttribute as CFString)
            }
        }

        var markers: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXSelectedTextMarkerRange" as CFString, &markers)
        if bounds == nil, let markers {
            bounds = rangeBounds(focused, parameter: markers, attribute: "AXBoundsForTextMarkerRange" as CFString)
        }

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value)
        if status == .success, let selected = value as? String, !selected.isEmpty {
            return .text(selected, bounds, focusedBounds)
        }

        // WebKit (Safari, Mail, …) describes a selection in page content as a pair of text
        // markers, and only hands over the string when asked for that range.
        if let markers {
            var string: CFTypeRef?
            let read = AXUIElementCopyParameterizedAttributeValue(
                focused, "AXStringForTextMarkerRange" as CFString, markers, &string
            )
            if read == .success, let selected = string as? String {
                return selected.isEmpty ? .nothing : .text(selected, bounds, focusedBounds)
            }
        }
        guard status == .success else { return .unknown(bounds, focusedBounds) }

        // "Success, empty" is only trustworthy from real text controls and Apple's own web views.
        // Elsewhere it often just means the app does not report selections here.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if textRoles.contains(role) || (role == "AXWebArea" && bundleID.hasPrefix("com.apple.")) {
            return .nothing
        }
        return .unknown(bounds, focusedBounds)
    }

    nonisolated private static func rangeBounds(_ element: AXUIElement, parameter: CFTypeRef, attribute: CFString) -> CGRect? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(result, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    nonisolated private static func elementBounds(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        let positionValue = unsafeDowncast(positionRef, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeRef, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Clipboard fallback

    /// Presses ⌘C in the frontmost app, reads what landed on the clipboard, then restores
    /// whatever was there before.
    private func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let before = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: keyDown)
            // Exactly ⌘, whatever else the user is still holding.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        var copied = false
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 15_000_000)
            if pasteboard.changeCount != before {
                copied = true
                break
            }
        }
        guard copied else { return nil }

        // Let the app finish writing every flavour before reading.
        try? await Task.sleep(nanoseconds: 20_000_000)
        // Files copy as their names; that is not a text selection.
        let text = pasteboard.availableType(from: [.fileURL]) == nil ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return text
    }
}

/// Recognises ⌥ pressed and released on its own, quickly, with no other key or click between.
struct OptionTap {
    static let longest = 0.45

    private var downAt: Double?
    private var spoiled = false
    private var wasNone = true

    /// Feed every modifier change. Returns true on the release that completes a tap.
    mutating func modifiersChanged(onlyOption: Bool, none: Bool, at time: Double) -> Bool {
        defer { wasNone = none }
        if onlyOption {
            // Only a press from nothing counts; ⌘⌥ let go of ⌘-first is not a tap.
            if downAt == nil, wasNone {
                downAt = time
                spoiled = false
            }
            return false
        }
        guard let start = downAt else { return false }
        guard none else {
            spoiled = true
            return false
        }
        downAt = nil
        return !spoiled && time - start <= Self.longest
    }

    /// Another key or a click while ⌥ was down: that was a shortcut, not a tap.
    mutating func interrupted() {
        if downAt != nil { spoiled = true }
    }
}
