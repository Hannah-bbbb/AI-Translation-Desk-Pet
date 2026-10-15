import SwiftUI

enum BubbleLayout {
    /// The bubble lives in a fixed transparent window and grows inside it, which animates far
    /// more smoothly than resizing a window on every streamed token.
    static let windowSize = CGSize(width: 380, height: 340)
    /// Transparent border around the card, leaving room for its shadow.
    static let margin: CGFloat = 20
    static let tail = CGSize(width: 18, height: 10)
    static let maxTextSize = CGSize(width: 300, height: 230)

    /// Left edge of a card of the given width: centred on the tail, but kept inside the window.
    static func cardX(width: CGFloat, tailX: CGFloat) -> CGFloat {
        (tailX - width / 2).clamped(margin...max(margin, windowSize.width - margin - width))
    }
}

struct BubbleView: View {
    @ObservedObject var model: BubbleModel
    @Environment(\.colorScheme) private var scheme

    private var palette: Palette { scheme == .dark ? .dark : .light }
    private var shape: BubbleShape { BubbleShape(tailX: model.tailX, isBelow: model.isBelow) }

    var body: some View {
        let tailX = model.tailX
        ZStack(alignment: model.isBelow ? .topLeading : .bottomLeading) {
            Color.clear
            if model.isVisible {
                card
                    .alignmentGuide(.leading) { -BubbleLayout.cardX(width: $0.width, tailX: tailX) }
                    .transition(.scale(scale: 0.5, anchor: model.isBelow ? .top : .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, BubbleLayout.margin)
        .frame(width: BubbleLayout.windowSize.width, height: BubbleLayout.windowSize.height)
        .coordinateSpace(name: "window")
        .onPreferenceChange(TargetFramesKey.self) { model.frames = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: model.isVisible)
        .animation(.easeOut(duration: 0.14), value: model.text)
        .animation(.easeOut(duration: 0.14), value: model.phase)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !model.caption.isEmpty { header }
            if model.phase == .loading {
                TypingDots(color: palette.caption)
            } else {
                message
            }
            if !model.choices.isEmpty { choices }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10 + (model.isBelow ? BubbleLayout.tail.height : 0))
        .padding(.bottom, 11 + (model.isBelow ? 0 : BubbleLayout.tail.height))
        .background {
            shape.fill(palette.fill).shadow(color: .black.opacity(0.25), radius: 9, y: 3)
            shape.stroke(palette.border, lineWidth: 1.5)
        }
        .reportFrame(as: .card)
    }

    private var header: some View {
        let offersCopy = model.isHovered && model.phase == .done && !model.justCopied
        // The hints take the caption's place rather than sitting beside it. All three are always
        // laid out, so the card keeps its width as they swap.
        return ZStack(alignment: .leading) {
            Text(model.caption).opacity(model.justCopied || offersCopy ? 0 : 1)
            Text("点击复制").opacity(offersCopy ? 1 : 0)
            Text("已复制 ✓").opacity(model.justCopied ? 1 : 0)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.caption)
        .lineLimit(1)
        .animation(.easeOut(duration: 0.12), value: offersCopy)
        .animation(.easeOut(duration: 0.12), value: model.justCopied)
    }

    /// Answer buttons. They only look like buttons: clicks are dispatched by `BubbleHostingView`.
    private var choices: some View {
        HStack(spacing: 8) {
            ForEach(model.choices) { choice in
                let hovered = model.hovered == .choice(choice.id)
                Text(choice.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(hovered ? palette.fill : palette.text)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(hovered ? palette.border : palette.border.opacity(0.12)))
                    .overlay(Capsule().stroke(palette.border, lineWidth: 1.2))
                    .reportFrame(as: .choice(choice.id))
                    .animation(.easeOut(duration: 0.1), value: hovered)
            }
        }
        .padding(.top, 4)
    }

    private var message: some View {
        let text = Text(model.text)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(model.phase == .error ? palette.error : palette.text)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        // Short text hugs its content; anything taller than the limit scrolls.
        return Hug(maxSize: BubbleLayout.maxTextSize) {
            ViewThatFits(in: .vertical) {
                text
                ScrollView {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The view hosting the bubble, and the one place clicks on it are handled.
///
/// The panel never becomes key and the app is never active, which is exactly where SwiftUI's
/// own tap gestures cannot be relied on. So clicks stop here and are matched against the frames
/// the view reports. Everything else, such as scrolling a long translation, still goes to SwiftUI.
final class BubbleHostingView: NSHostingView<BubbleView> {
    private var pressed: BubbleModel.Target?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return frame.contains(point) ? self : nil
        default:
            return super.hitTest(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = rootView.model.target(at: point(of: event))
    }

    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        // Only a press and release on the same thing counts, as with any button.
        guard let pressed, rootView.model.target(at: point(of: event)) == pressed else { return }
        rootView.model.activate(pressed)
    }

    /// In the bubble's own coordinates: top-left origin, matching the reported frames.
    private func point(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}

/// The frames of the card and its buttons, merged from wherever in the tree they are reported.
/// Merging matters: views that report nothing still take part with an empty value, and a
/// plain "last one wins" would let them wipe out the real frames.
private struct TargetFramesKey: PreferenceKey {
    static let defaultValue: [BubbleModel.Target: CGRect] = [:]
    static func reduce(value: inout [BubbleModel.Target: CGRect], nextValue: () -> [BubbleModel.Target: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func reportFrame(as target: BubbleModel.Target) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TargetFramesKey.self, value: [target: geometry.frame(in: .named("window"))])
        })
    }
}

/// Offers its child at most `maxSize` and takes whatever size the child settles on.
/// `frame(maxWidth:)` would instead stretch the child out to the maximum.
private struct Hug: Layout {
    var maxSize: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: min(proposal.width ?? maxSize.width, maxSize.width),
            height: min(proposal.height ?? maxSize.height, maxSize.height)
        )
    }
}

/// A rounded card with a pointer aimed at the pet.
private struct BubbleShape: Shape {
    var tailX: CGFloat
    var isBelow: Bool

    func path(in rect: CGRect) -> Path {
        let tail = BubbleLayout.tail
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + (isBelow ? tail.height : 0),
            width: rect.width,
            height: max(0, rect.height - tail.height)
        )
        let radius = min(15, body.height / 2)
        // The pointer stays clear of the rounded corners even when the card is pushed off-centre.
        let inset = radius + tail.width / 2 + 2
        let x = rect.minX + (tailX - BubbleLayout.cardX(width: rect.width, tailX: tailX))
            .clamped(inset...max(inset, rect.width - inset))
        let base = isBelow ? body.minY + 1 : body.maxY - 1
        let tip = isBelow ? rect.minY : rect.maxY

        var pointer = Path()
        pointer.move(to: CGPoint(x: x - tail.width / 2, y: base))
        pointer.addLine(to: CGPoint(x: x, y: tip))
        pointer.addLine(to: CGPoint(x: x + tail.width / 2, y: base))
        pointer.closeSubpath()
        return Path(roundedRect: body, cornerRadius: radius, style: .continuous).union(pointer)
    }
}

private struct TypingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .offset(y: -4 * max(0, sin(time * 7 - Double(index) * 0.9)))
                }
            }
            .frame(height: 18)
        }
    }
}

/// Cream paper with a brown rim, matching the cat's outline; inverted after dark.
private struct Palette {
    let fill: Color
    let border: Color
    let text: Color
    let caption: Color
    let error: Color

    static let light = Palette(
        fill: Color(hex: 0xFFF9EE),
        border: Color(hex: 0x4B2E1E),
        text: Color(hex: 0x3A2418),
        caption: Color(hex: 0xA57F5E),
        error: Color(hex: 0xC2412D)
    )
    static let dark = Palette(
        fill: Color(hex: 0x2B231E),
        border: Color(hex: 0xE8C9A0),
        text: Color(hex: 0xF7EBDB),
        caption: Color(hex: 0xB89C80),
        error: Color(hex: 0xFF9580)
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
