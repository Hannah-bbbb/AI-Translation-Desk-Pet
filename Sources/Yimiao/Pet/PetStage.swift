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
    private let hat = Part(PetRenderer.hatBox, anchor: PetRenderer.crown)
    private let particles = Part(PetRenderer.particleBox)
    private var scale: CGFloat = 0
    private var density: CGFloat = 0
    private var look = PetLook()
    private var anatomy = PetRenderer.anatomy(.cat)
    /// The hat currently drawn into `hat`, if any.
    private var shownHat: Outfit.Hat?

    init() {
        layer.anchorPoint = .zero
        layer.addSublayer(rig)
        rig.addSublayer(shadow.layer)
        rig.addSublayer(figure)
        rig.addSublayer(particles.layer)
        for part in [tail, earL, earR, body, stripes, face, hat] {
            figure.addSublayer(part.layer)
        }
        shadow.layer.position = PetRenderer.feet
        figure.position = PetRenderer.feet
        particles.layer.position = PetRenderer.feet
    }

    /// `scale` is the user's size setting, `density` the display's pixels per point.
    func configure(scale: CGFloat, density: CGFloat, look: PetLook = PetLook()) {
        guard scale != self.scale || density != self.density || look != self.look else { return }
        self.scale = scale
        self.density = density
        self.look = look

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: PetRenderer.canvas.width * scale, height: PetRenderer.canvas.height * scale)
        rig.position = CGPoint(x: 0, y: layer.bounds.height)
        rig.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))

        anatomy = PetRenderer.anatomy(look.species)
        shadow.reshape(anatomy.shadowBox)
        tail.reshape(anatomy.tailBox)
        body.reshape(anatomy.bodyBox)
        stripes.reshape(anatomy.stripesBox)
        face.reshape(anatomy.faceBox)
        earR.reshape(anatomy.earBox, anchor: anatomy.earPivot)
        // Only the snake nods his markings and face along with his head.
        stripes.layer.setAffineTransform(.identity)
        face.layer.setAffineTransform(.identity)
        // The cat's ears sit behind his body; the snake's head sits in front of his neck.
        figure.insertSublayer(earR.layer, above: look.species == .snake ? body.layer : earL.layer)
        particles.layer.position = CGPoint(x: PetRenderer.feet.x + anatomy.particleOffset.dx,
                                           y: PetRenderer.feet.y + anatomy.particleOffset.dy)
        for part in [shadow, tail, earL, earR, body, stripes, face, hat, particles] {
            part.pixelsPerPoint = scale * density
            // Anything keyed on the pose has to be redrawn in the new colours too.
            part.forget()
        }
        switch look.species {
        case .cat:
            shadow.redraw(PetRenderer.drawShadow)
            body.redraw { PetRenderer.drawBody(look, in: $0) }
            stripes.redraw { PetRenderer.drawStripes(look.coat, in: $0) }
            earR.redraw { PetRenderer.drawEar(look.coat, left: false, in: $0) }
            earL.redraw { PetRenderer.drawEar(look.coat, left: true, in: $0) }
        case .snake:
            shadow.redraw(SnakeRenderer.drawShadow)
            body.redraw { SnakeRenderer.drawBody(look, in: $0) }
            stripes.redraw { SnakeRenderer.drawPattern(look.skin, in: $0) }
            earR.redraw { SnakeRenderer.drawHead(look.skin, in: $0) }
            earL.clear()
        case .crab:
            // All of him is in the face layer; see `showCrab`.
            shadow.redraw(CrabRenderer.drawShadow)
            for part in [tail, earL, earR, body, stripes] { part.clear() }
        }
        shownHat = nil
        hat.clear()
        CATransaction.commit()
    }

    func show(_ pose: PetPose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if look.species == .crab {
            showCrab(pose)
            return
        }

        let height = (pose.lift / 60).clamped(0...1)
        shadow.layer.opacity = Float(1 - 0.5 * height)
        shadow.layer.setAffineTransform(CGAffineTransform(scaleX: (1 - 0.35 * height) * pose.squash.squareRoot(), y: 1))

        // Squash first, then lift, then roll: the same order a body would do it in.
        figure.setAffineTransform(
            CGAffineTransform(scaleX: pose.squash.squareRoot(), y: 1 / pose.squash)
                .concatenating(CGAffineTransform(translationX: 0, y: -pose.lift))
                .concatenating(CGAffineTransform(rotationAngle: pose.tilt))
        )

        switch look.species {
        case .cat: showCatHead(pose)
        case .snake: showSnakeHead(pose)
        case .crab: break
        }

        // Keys are the pose rounded to steps too small to see, so a still pose costs nothing.
        tail.redraw(ifChanged: [step(pose.tail, 250)]) { [look] in
            switch look.species {
            case .cat: PetRenderer.drawTail(angle: pose.tail, coat: look.coat, in: $0)
            case .snake: SnakeRenderer.drawTail(angle: pose.tail, skin: look.skin, in: $0)
            case .crab: break
            }
        }
        var faceKey = [
            step(pose.lookL.dx, 60), step(pose.lookL.dy, 60), step(pose.lookR.dx, 60), step(pose.lookR.dy, 60),
            step(pose.eyeOpen, 100), step(pose.pupil, 60), pose.joy > 0.5 ? 1 : 0, step(pose.mouth, 60),
            step(pose.blush, 25), step(pose.sleep, 40), step(pose.noseBubble, 40),
        ]
        // The cat has no tongue to show, so its flicks must not cost him redraws.
        if look.species == .snake { faceKey.append(step(pose.tongue, 40)) }
        face.redraw(ifChanged: faceKey) { [look] in
            switch look.species {
            case .cat: PetRenderer.drawFace(pose, coat: look.coat, in: $0)
            case .snake: SnakeRenderer.drawFace(pose, skin: look.skin, in: $0)
            case .crab: break
            }
        }
        if pose.particles.isEmpty {
            particles.clear()
        } else {
            particles.redraw { PetRenderer.drawParticles(pose.particles, in: $0) }
        }
    }

    /// The pixel crab moves in pixel steps: no squash or roll, a hop that climbs a half pixel at
    /// a time, and the rest redrawn only when a pixel changes.
    private func showCrab(_ pose: PetPose) {
        let lift = CrabRenderer.lift(pose.lift)
        shadow.layer.opacity = Float(1 - 0.5 * (lift / 60).clamped(0...1))
        shadow.layer.setAffineTransform(.identity)
        figure.setAffineTransform(CGAffineTransform(translationX: 0, y: -lift))
        let frame = CrabRenderer.frame(for: pose, outfit: look.outfit)
        face.layer.position = .zero
        face.redraw(ifChanged: frame.key) { CrabRenderer.draw(frame, in: $0) }
        hat.clear()
        shownHat = nil
        if pose.particles.isEmpty {
            particles.clear()
        } else {
            particles.redraw { PetRenderer.drawParticles(pose.particles, in: $0) }
        }
    }

    /// Head turn: the face slides one way, the ears a little the other, the stripes in between.
    private func showCatHead(_ pose: PetPose) {
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
        // The hat slides with the turn and lifts a little when the ears perk up.
        let perk = -(pose.earL + pose.earR) / 2
        let seat = anatomy.hatSeat
        showHat(pose, at: CGPoint(x: seat.x + turn * 3, y: seat.y - perk * 6), angle: (pose.earR - pose.earL) * 0.25)
    }

    /// The snake's head nods on his neck. Ears that would droop lower it (sleepy, tired, being
    /// carried) and ears that would perk up raise it (spotting something); one ear back tips it.
    private func showSnakeHead(_ pose: PetPose) {
        let turn = pose.face.dx
        let droop = (pose.earL + pose.earR) / 2
        let angle = (-0.8 * droop + 0.3 * (pose.earR - pose.earL)).clamped(-0.32...0.32)
        let drop = (droop * 22).clamped(-4...8)
        let pivot = anatomy.earPivot
        let nod = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y + drop))
        earR.layer.position = CGPoint(x: pivot.x + turn, y: pivot.y + drop)
        earR.layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        stripes.layer.position = CGPoint(x: turn * 2, y: 0)
        stripes.layer.setAffineTransform(nod)
        face.layer.position = CGPoint(x: turn * 3, y: pose.face.dy * 2)
        face.layer.setAffineTransform(nod)
        let seat = anatomy.hatSeat.applying(nod)
        showHat(pose, at: CGPoint(x: seat.x + turn * 2, y: seat.y), angle: angle)
    }

    /// His outfit's hat if it has one. Otherwise a nightcap that fades in as he drifts off.
    private func showHat(_ pose: PetPose, at place: CGPoint, angle: Double) {
        let wanted: Outfit.Hat? = look.outfit.hat ?? (pose.sleep > 0.3 ? .nightcap : nil)
        if wanted != shownHat {
            shownHat = wanted
            if let wanted { hat.redraw { PetRenderer.drawHat(wanted, in: $0) } } else { hat.clear() }
        }
        guard shownHat != nil else { return }
        hat.layer.opacity = look.outfit.hat == nil ? Float(ramp(pose.sleep, 0.3, 0.85)) : 1
        hat.layer.position = place
        hat.layer.setAffineTransform(CGAffineTransform(scaleX: anatomy.hatScale, y: anatomy.hatScale).rotated(by: angle))
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

    private var box: CGRect
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

    /// Moves the part to a different box, for a different animal.
    func reshape(_ newBox: CGRect, anchor: CGPoint = .zero) {
        let anchorPoint = CGPoint(x: (anchor.x - newBox.minX) / newBox.width, y: (anchor.y - newBox.minY) / newBox.height)
        guard newBox != box || anchorPoint != layer.anchorPoint else { return }
        box = newBox
        layer.bounds = newBox
        // The anchor point keeps its place on the layer; whoever owns the part positions it.
        layer.anchorPoint = anchorPoint
        layer.setAffineTransform(.identity)
        canvas = nil
        key = nil
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

    /// Drops the remembered pose, so the next keyed redraw happens whatever the key.
    func forget() {
        key = nil
    }
}
