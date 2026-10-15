import QuartzCore

/// The pet as a small tree of layers.
///
/// Redrawing the whole cat every frame keeps a CPU core busy for no reason: most of him is the
/// same picture from one frame to the next, only squashed, lifted or tilted. So each part is a
/// bitmap that is redrawn only when it really changes (the face while his eyes move, the tail
/// while it sways), and the compositor does the moving.
final class PetStage {
    /// Add this to a host layer. It is the canvas size times the scale, y up as usual on macOS.
    let layer = CALayer()

    /// Flips to the renderer's y-down space and applies the user's size setting.
    private let rig = CALayer()
    /// Squash, hop and roll, all around the feet.
    private let figure = CALayer()
    private let shadow = Part(PetRenderer.shadowBox)
    private let tail = Part(PetRenderer.tailBox)
    private let earL = Part(PetRenderer.earBox, anchor: PetRenderer.earPivot)
    private let earR = Part(PetRenderer.earBox, anchor: PetRenderer.earPivot)
    private let body = Part(PetRenderer.bodyBox)
    private let stripes = Part(PetRenderer.stripesBox)
    private let face = Part(PetRenderer.faceBox)
    private let particles = Part(PetRenderer.particleBox)
    private var scale: CGFloat = 0
    private var density: CGFloat = 0

    init() {
        layer.anchorPoint = .zero
        layer.addSublayer(rig)
        rig.addSublayer(shadow.layer)
        rig.addSublayer(figure)
        rig.addSublayer(particles.layer)
        for part in [tail, earL, earR, body, stripes, face] {
            figure.addSublayer(part.layer)
        }
        shadow.layer.position = PetRenderer.feet
        figure.position = PetRenderer.feet
        particles.layer.position = PetRenderer.feet
    }

    /// `scale` is the user's size setting, `density` the display's pixels per point.
    func configure(scale: CGFloat, density: CGFloat) {
        guard scale != self.scale || density != self.density else { return }
        self.scale = scale
        self.density = density

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: PetRenderer.canvas.width * scale, height: PetRenderer.canvas.height * scale)
        rig.position = CGPoint(x: 0, y: layer.bounds.height)
        rig.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))

        for part in [shadow, tail, earL, earR, body, stripes, face, particles] {
            part.pixelsPerPoint = scale * density
        }
        shadow.redraw(PetRenderer.drawShadow)
        body.redraw(PetRenderer.drawBody)
        stripes.redraw(PetRenderer.drawStripes)
        earR.redraw(PetRenderer.drawEar)
        earL.layer.contents = earR.layer.contents
        CATransaction.commit()
    }

    func show(_ pose: PetPose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let height = (pose.lift / 60).clamped(0...1)
        shadow.layer.opacity = Float(1 - 0.5 * height)
        shadow.layer.setAffineTransform(CGAffineTransform(scaleX: (1 - 0.35 * height) * pose.squash.squareRoot(), y: 1))

        // Squash first, then lift, then roll: the same order a body would do it in.
        figure.setAffineTransform(
            CGAffineTransform(scaleX: pose.squash.squareRoot(), y: 1 / pose.squash)
                .concatenating(CGAffineTransform(translationX: 0, y: -pose.lift))
                .concatenating(CGAffineTransform(rotationAngle: pose.tilt))
        )

        // Head turn: the face slides one way, the ears a little the other, the stripes in between.
        let turn = pose.face.dx
        let pivot = PetRenderer.earPivot
        earR.layer.position = CGPoint(x: pivot.x - turn * 1.5, y: pivot.y)
        earR.layer.setAffineTransform(CGAffineTransform(rotationAngle: pose.earR))
        earL.layer.position = CGPoint(x: -pivot.x - turn * 1.5, y: pivot.y)
        earL.layer.setAffineTransform(
            CGAffineTransform(rotationAngle: pose.earL).concatenating(CGAffineTransform(scaleX: -1, y: 1))
        )
        stripes.layer.position = CGPoint(x: turn * 3, y: 0)
        face.layer.position = CGPoint(x: turn * 4, y: pose.face.dy * 3)

        // Keys are the pose rounded to steps too small to see, so a still pose costs nothing.
        tail.redraw(ifChanged: [step(pose.tail, 250)]) {
            PetRenderer.drawTail(angle: pose.tail, in: $0)
        }
        face.redraw(ifChanged: [
            step(pose.lookL.dx, 60), step(pose.lookL.dy, 60), step(pose.lookR.dx, 60), step(pose.lookR.dy, 60),
            step(pose.eyeOpen, 100), step(pose.pupil, 60), pose.joy > 0.5 ? 1 : 0, step(pose.mouth, 60),
            step(pose.blush, 25), step(pose.sleep, 40), step(pose.noseBubble, 40),
        ]) {
            PetRenderer.drawFace(pose, in: $0)
        }
        if pose.particles.isEmpty {
            particles.clear()
        } else {
            particles.redraw { PetRenderer.drawParticles(pose.particles, in: $0) }
        }
    }

    private func step(_ value: Double, _ stepsPerUnit: Double) -> Int32 {
        Int32((value * stepsPerUnit).rounded())
    }
}

/// One layer and the bitmap it shows.
private final class Part {
    let layer = CALayer()
    var pixelsPerPoint: CGFloat = 2 {
        didSet {
            guard pixelsPerPoint != oldValue else { return }
            canvas = nil
            key = nil
        }
    }

    private let box: CGRect
    private var canvas: CGContext?
    private var key: [Int32]?

    /// `box` is where the part sits relative to the feet. `anchor`, in the same space, is the
    /// point it rotates around and the point `layer.position` places.
    init(_ box: CGRect, anchor: CGPoint = .zero) {
        self.box = box
        layer.bounds = box
        layer.anchorPoint = CGPoint(x: (anchor.x - box.minX) / box.width, y: (anchor.y - box.minY) / box.height)
        layer.position = anchor
    }

    func redraw(ifChanged newKey: [Int32], _ paint: (CGContext) -> Void) {
        guard newKey != key else { return }
        redraw(paint)
        key = newKey
    }

    func redraw(_ paint: (CGContext) -> Void) {
        let width = Int((box.width * pixelsPerPoint).rounded(.up))
        let height = Int((box.height * pixelsPerPoint).rounded(.up))
        if canvas == nil {
            canvas = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }
        guard let canvas else { return }

        canvas.clear(CGRect(x: 0, y: 0, width: width, height: height))
        canvas.saveGState()
        // The renderer's y-down coordinates go straight into this y-up bitmap, leaving the
        // picture upside down. The rig's flip turns every part the right way up at once.
        canvas.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        canvas.translateBy(x: -box.minX, y: -box.minY)
        canvas.setLineCap(.round)
        canvas.setLineJoin(.round)
        paint(canvas)
        canvas.restoreGState()
        layer.contents = canvas.makeImage()
        key = nil
    }

    func clear() {
        guard layer.contents != nil else { return }
        layer.contents = nil
        key = nil
    }
}
