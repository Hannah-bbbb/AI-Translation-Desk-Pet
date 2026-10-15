import AppKit

@MainActor
protocol PetViewDelegate: AnyObject {
    /// Called once per display refresh with the time since the last one; returns what to draw.
    func petView(_ view: PetView, poseAfter dt: Double) -> PetPose
    func petView(_ view: PetView, clicked count: Int)
    func petViewDragBegan(_ view: PetView)
    func petViewDragged(_ view: PetView)
    func petViewDragEnded(_ view: PetView)
    func petViewMenu(_ view: PetView) -> NSMenu
}

/// Draws the pet in step with the display and turns mouse input into clicks and drags.
final class PetView: NSView {
    enum Pace { case resting, lively }

    weak var delegate: PetViewDelegate?
    var scale: CGFloat = 1 {
        didSet { configureStage() }
    }
    /// How often to redraw. Breathing looks the same at 30 fps; eye tracking and bounces do not.
    var pace = Pace.lively {
        didSet { if pace != oldValue { applyPace() } }
    }

    private let stage = PetStage()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var grab: (mouse: CGPoint, origin: CGPoint)?
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-hosting: the view's layer is ours, and AppKit never draws into it.
        let host = CALayer()
        host.addSublayer(stage.layer)
        layer = host
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PetView is created in code")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        // Common modes keep him animating while a menu is open or he is being dragged.
        link.add(to: .main, forMode: .common)
        self.link = link
        applyPace()
        configureStage()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        configureStage()
    }

    private func configureStage() {
        stage.configure(scale: scale, density: window?.backingScaleFactor ?? 2)
    }

    private func applyPace() {
        link?.preferredFrameRateRange = switch pace {
        case .resting: CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        case .lively: CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 60 : link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        if let delegate {
            stage.show(delegate.petView(self, poseAfter: dt))
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        grab = (NSEvent.mouseLocation, window.frame.origin)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let grab else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - grab.mouse.x
        let dy = mouse.y - grab.mouse.y
        if !isDragging {
            // A few points of slop, so a shaky click is still a click.
            guard hypot(dx, dy) > 3 else { return }
            isDragging = true
            delegate?.petViewDragBegan(self)
        }
        window.setFrameOrigin(CGPoint(x: grab.origin.x + dx, y: grab.origin.y + dy))
        delegate?.petViewDragged(self)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            delegate?.petViewDragEnded(self)
        } else if grab != nil {
            delegate?.petView(self, clicked: event.clickCount)
        }
        grab = nil
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = delegate?.petViewMenu(self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
