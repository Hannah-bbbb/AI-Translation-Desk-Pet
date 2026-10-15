import AppKit
import ApplicationServices

/// Notices when the user selects text in any app and reports what they selected.
///
/// The selection is read through the Accessibility API. Apps that do not expose it that way
/// (Chromium browsers, Electron apps) are handled by briefly pressing ⌘C and putting the
/// clipboard back afterwards.
@MainActor
final class SelectionWatcher {
    /// The selected text, and where the pointer let go of it. A selection made from the
    /// keyboard has no such place.
    var onSelection: ((String, CGPoint?) -> Void)?
    /// Called when the user selected something but Accessibility access is missing.
    var onBlocked: (() -> Void)?
    /// Asked before every read, so a sleeping pet costs nothing.
    var isEnabled: () -> Bool = { true }
    var allowsClipboardFallback: () -> Bool = { true }

    private var monitors: [Any] = []
    private var pressPoint = CGPoint.zero
    private var pending: Task<Void, Never>?

    func start() {
        guard monitors.isEmpty else { return }
        listen(.leftMouseDown) { [weak self] _ in
            self?.pressPoint = NSEvent.mouseLocation
        }
        listen(.leftMouseUp) { [weak self] event in
            self?.mouseReleased(event)
        }
        listen(.keyUp) { [weak self] event in
            self?.keyReleased(event)
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
        // After a double-click, wait out a possible third click before reading.
        check(after: multiClick ? 0.3 : 0.1, fromMouse: true)
    }

    private func keyReleased(_ event: NSEvent) {
        let flags = event.modifierFlags
        let navigation: Set<UInt16> = [123, 124, 125, 126, 115, 116, 119, 121]  // arrows, home, end, page up/down
        let extendsSelection = flags.contains(.shift) && navigation.contains(event.keyCode)
        let selectsAll = flags.contains(.command) && event.keyCode == 0  // ⌘A
        guard extendsSelection || selectsAll else { return }
        // Long enough that holding ⇧→ across a sentence reads once, at the end.
        check(after: 0.5, fromMouse: false)
    }

    private func check(after delay: Double, fromMouse: Bool) {
        let pointer = fromMouse ? NSEvent.mouseLocation : nil
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

            // Accessibility calls block on the other app, so they stay off the main thread.
            let answer = await Task.detached(priority: .userInitiated) {
                Self.accessibilitySelection(pid: pid, bundleID: bundleID)
            }.value
            guard !Task.isCancelled else { return }

            var text: String?
            var route = "accessibility"
            switch answer {
            case .text(let selected):
                text = selected
            case .nothing:
                break
            case .unknown:
                // Keyboard triggers never fall back: a stray ⌘C mid-typing is not worth the risk.
                if fromMouse, self.allowsClipboardFallback(), !Self.neverCopyFrom.contains(bundleID) {
                    route = "clipboard"
                    text = await self.copySelection()
                } else {
                    route = "none"
                }
            }
            Log.selection.notice("\(bundleID, privacy: .public) via \(route, privacy: .public): \(text?.count ?? 0) characters")
            guard !Task.isCancelled, let text, !text.isEmpty else { return }
            self.onSelection?(text, pointer)
        }
    }

    // MARK: - Accessibility

    private enum Answer: Sendable {
        case text(String)
        /// The app answered and nothing is selected.
        case nothing
        /// The app could not say either way.
        case unknown
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
        else { return .unknown }
        let focused = unsafeDowncast(focusedRef, to: AXUIElement.self)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value)
        if status == .success, let selected = value as? String, !selected.isEmpty {
            return .text(selected)
        }

        // WebKit (Safari, Mail, …) describes a selection in page content as a pair of text
        // markers, and only hands over the string when asked for that range.
        var markers: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXSelectedTextMarkerRange" as CFString, &markers) == .success,
           let markers {
            var string: CFTypeRef?
            let read = AXUIElementCopyParameterizedAttributeValue(
                focused, "AXStringForTextMarkerRange" as CFString, markers, &string
            )
            if read == .success, let selected = string as? String {
                return selected.isEmpty ? .nothing : .text(selected)
            }
        }
        guard status == .success else { return .unknown }

        // "Success, empty" is only trustworthy from real text controls and Apple's own web views.
        // Elsewhere it often just means the app does not report selections here.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if textRoles.contains(role) || (role == "AXWebArea" && bundleID.hasPrefix("com.apple.")) {
            return .nothing
        }
        return .unknown
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
