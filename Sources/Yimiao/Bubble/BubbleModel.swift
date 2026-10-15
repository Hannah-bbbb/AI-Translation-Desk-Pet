import AppKit
import Combine

/// What the speech bubble is showing.
@MainActor
final class BubbleModel: ObservableObject {
    enum Phase { case loading, streaming, done, error, notice }

    /// A button under the text.
    struct Choice: Identifiable {
        let id = UUID()
        let title: String
        let action: () -> Void
    }

    /// Something in the bubble that can be clicked.
    enum Target: Hashable {
        case card
        case choice(UUID)
    }

    @Published private(set) var isVisible = false
    @Published private(set) var phase = Phase.notice
    @Published private(set) var text = ""
    /// The small line above the text, e.g. "英语 → 简体中文".
    @Published private(set) var caption = ""
    @Published private(set) var justCopied = false
    @Published private(set) var choices: [Choice] = []
    /// What the pointer is over. Hovering anywhere on the card holds the bubble open.
    @Published var hovered: Target?
    var isHovered: Bool { hovered != nil }
    /// Where the tail points, in the bubble window's coordinates.
    @Published var tailX = BubbleLayout.windowSize.width / 2
    /// True when the bubble hangs below the pet instead of sitting above him.
    @Published var isBelow = false
    /// A smaller scrollable bubble can fit beside a large selection.
    @Published var windowSize = BubbleLayout.windowSize
    /// Where the card and each of its buttons sit inside the window, top-left origin, as the
    /// view last reported them. Clicks and hovering are worked out from these.
    var frames: [Target: CGRect] = [:]
    var cardFrame: CGRect { frames[.card] ?? .zero }

    private var remaining = 0.0
    private var action: (() -> Void)?

    /// Whether a click does something other than copy.
    var hasAction: Bool { action != nil }

    func begin(caption: String) {
        self.caption = caption
        text = ""
        phase = .loading
        justCopied = false
        action = nil
        choices = []
        isVisible = true
    }

    func append(_ piece: String) {
        // Models sometimes open with a blank line.
        text += text.isEmpty ? String(piece.drop(while: \.isWhitespace)) : piece
        if !text.isEmpty { phase = .streaming }
    }

    func finish() {
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .done
        // Long enough to read, and longer for more text.
        remaining = (3.5 + Double(text.count) * 0.08).clamped(4...25)
    }

    func fail(_ message: String, caption: String = "出错了", choices: [Choice] = []) {
        self.caption = caption
        text = message
        phase = .error
        justCopied = false
        action = nil
        self.choices = choices
        // Long enough to reach for a button.
        remaining = choices.isEmpty ? 8 : 14
        isVisible = true
    }

    /// The pet speaking for himself. `action` runs if the bubble is clicked.
    func say(_ message: String, seconds: Double = 6, action: (() -> Void)? = nil) {
        caption = ""
        text = message
        phase = .notice
        justCopied = false
        self.action = action
        choices = []
        remaining = seconds
        isVisible = true
    }

    /// The pet asking something, with buttons to answer.
    func ask(_ message: String, seconds: Double, choices: [Choice]) {
        say(message, seconds: seconds)
        self.choices = choices
    }

    func hide() {
        if isVisible { isVisible = false }
    }

    /// Counts down to auto-dismissal. Hovering holds the bubble open.
    func tick(dt: Double) {
        guard isVisible, !isHovered, phase == .done || phase == .error || phase == .notice else { return }
        remaining -= dt
        if remaining <= 0 { hide() }
    }

    /// The button under a point (window coordinates, top-left origin), else the card, else nothing.
    func target(at point: CGPoint) -> Target? {
        guard isVisible else { return nil }
        if let choice = choices.first(where: { frames[.choice($0.id)]?.contains(point) == true }) {
            return .choice(choice.id)
        }
        return cardFrame.contains(point) ? .card : nil
    }

    func activate(_ target: Target) {
        switch target {
        case .card:
            click()
        case .choice(let id):
            choices.first { $0.id == id }?.action()
        }
    }

    func click() {
        if let action {
            hide()
            action()
            return
        }
        guard phase == .done, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        justCopied = true
        remaining = max(remaining, 2.5)
    }
}
