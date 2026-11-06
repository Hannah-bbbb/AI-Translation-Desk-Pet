import CoreGraphics
import Foundation

/// Draws the snake: a slim body lying along the ground in a lazy wave, a short neck rising at
/// the left with a small round head turned to the viewer, and the tail tip curling up at the
/// right. It uses the cat's space and layers (see `PetRenderer`): the body layer holds neck and
/// body, the right-ear layer holds the head so it can nod on its neck, and the tail layer holds
/// the tail tip. He has no ears; the ear springs nod his head instead, and his forked tongue
/// flicks out now and then.
enum SnakeRenderer {
    /// Where the neck meets the head; the head nods around it.
    static let neckTop = CGPoint(x: -44, y: -42)
    private static let headCentre = CGPoint(x: -46, y: -54)

    static let anatomy = PetRenderer.Anatomy(
        shadowBox: CGRect(x: -58, y: -6, width: 160, height: 14),
        tailBox: CGRect(x: 40, y: -70, width: 74, height: 80),
        bodyBox: CGRect(x: -62, y: -62, width: 126, height: 68),
        stripesBox: CGRect(x: -62, y: -74, width: 32, height: 16),
        faceBox: CGRect(x: -70, y: -74, width: 52, height: 48),
        earBox: CGRect(x: -70, y: -74, width: 48, height: 42),
        earPivot: neckTop,
        hatSeat: CGPoint(x: -46, y: -67),
        hatScale: 0.5,
        headTop: 72,
        headX: -46,
        halfWidth: 98,
        eyes: CGPoint(x: -46, y: -56),
        eyeSpread: 8,
        hitAreas: [
            CGRect(x: -70, y: -76, width: 48, height: 44),
            CGRect(x: -58, y: -52, width: 28, height: 40),
            CGRect(x: -56, y: -28, width: 156, height: 32),
            CGRect(x: 72, y: -52, width: 32, height: 42),
        ],
        particleOffset: CGVector(dx: -44, dy: 48),
        species: .snake
    )

    private typealias Ink = PetRenderer.Ink
    private static let tongueRed = PetRenderer.rgb(0xF2506E)
    private static let line: CGFloat = 2.6

    // MARK: - Shapes

    /// Neck, then the body on the ground with a lazy hump in the middle, as if mid-slither. The
    /// body ends where the tail layer takes over.
    private static let bodySpine = Spine(
        curves: [
            (CGPoint(x: -44, y: -50), CGPoint(x: -45, y: -30), CGPoint(x: -42, y: -12), CGPoint(x: -26, y: -11.6)),
            (CGPoint(x: -26, y: -11.6), CGPoint(x: -15, y: -11.6), CGPoint(x: -6, y: -19.5), CGPoint(x: 6, y: -19.5)),
            (CGPoint(x: 6, y: -19.5), CGPoint(x: 18, y: -19.5), CGPoint(x: 25, y: -11), CGPoint(x: 36, y: -11)),
            (CGPoint(x: 36, y: -11), CGPoint(x: 44, y: -11), CGPoint(x: 50, y: -9.4), CGPoint(x: 58, y: -8.6)),
        ],
        widths: [(0, 18), (0.7, 21), (1, 23), (2, 22.5), (3, 20.5), (4, 16.8)]
    )

    /// A soft head, a little wider than tall, flatter underneath.
    private static let headPath: CGPath = {
        let c = headCentre
        let (w, top, bottom) = (19.0, c.y - 15.5, c.y + 15)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: bottom))
        p.addCurve(to: CGPoint(x: c.x + w, y: c.y + 1), control1: CGPoint(x: c.x + w * 0.66, y: bottom), control2: CGPoint(x: c.x + w, y: bottom - 7))
        p.addCurve(to: CGPoint(x: c.x, y: top), control1: CGPoint(x: c.x + w, y: top + 8), control2: CGPoint(x: c.x + w * 0.6, y: top))
        p.addCurve(to: CGPoint(x: c.x - w, y: c.y + 1), control1: CGPoint(x: c.x - w * 0.6, y: top), control2: CGPoint(x: c.x - w, y: top + 8))
        p.addCurve(to: CGPoint(x: c.x, y: bottom), control1: CGPoint(x: c.x - w, y: bottom - 7), control2: CGPoint(x: c.x - w * 0.66, y: bottom))
        p.closeSubpath()
        return p
    }()

    // MARK: - Still parts

    static func drawShadow(in ctx: CGContext) {
        ctx.setFillColor(PetRenderer.rgb(0x000000, 0.17))
        ctx.fillEllipse(in: CGRect(x: -54, y: -4.5, width: 146, height: 10))
    }

    /// Neck and body, with a collar and bell (or a knot at New Year) on the neck.
    static func drawBody(_ look: PetLook, in ctx: CGContext) {
        let skin = look.skin.palette
        drawTube(bodySpine, closedStart: true, closedEnd: false, spots: [0.6, 1.3, 2.05, 2.75, 3.45], skin, ctx)

        // Collar just under his chin.
        let (p, n, half) = bodySpine.frame(at: 0.3)
        let collar = CGMutablePath()
        collar.move(to: CGPoint(x: p.x + n.dx * (half + 0.5), y: p.y + n.dy * (half + 0.5)))
        collar.addLine(to: CGPoint(x: p.x - n.dx * (half + 0.5), y: p.y - n.dy * (half + 0.5)))
        ctx.addPath(collar)
        ctx.setStrokeColor(skin.outline)
        ctx.setLineWidth(7.5)
        ctx.strokePath()
        ctx.addPath(collar)
        ctx.setStrokeColor(look.outfit == .newYear ? Ink.festiveCollar : Ink.collar)
        ctx.setLineWidth(3.6)
        ctx.strokePath()

        ctx.saveGState()
        // The cat's bell and knot hang from the top of his collar, 27.5 points above his feet;
        // on the snake they hang at the front of the collar, a little smaller.
        ctx.translateBy(x: p.x, y: p.y + 1.5)
        ctx.scaleBy(x: 0.62, y: 0.62)
        ctx.translateBy(x: 0, y: 27.5)
        if look.outfit == .newYear { PetRenderer.drawKnot(ctx) } else { PetRenderer.drawBell(outline: skin.outline, ctx) }
        ctx.restoreGState()
    }

    /// His head, in the layer that nods.
    static func drawHead(_ skin: SnakeSkin, in ctx: CGContext) {
        let palette = skin.palette
        ctx.saveGState()
        ctx.addPath(headPath)
        ctx.clip()
        ctx.drawLinearGradient(PetRenderer.gradient(palette.top, palette.bottom),
                               start: CGPoint(x: 0, y: headCentre.y - 16), end: CGPoint(x: 0, y: headCentre.y + 15), options: [])
        // A pale chin, where the mouth sits.
        ctx.setFillColor(palette.belly)
        ctx.fillEllipse(in: CGRect(x: headCentre.x - 13, y: headCentre.y + 4, width: 26, height: 16))
        ctx.restoreGState()
        ctx.addPath(headPath)
        ctx.setStrokeColor(palette.outline)
        ctx.setLineWidth(line)
        ctx.strokePath()
    }

    /// Spots on top of his head. Like the cat's stripes they slide a little as the head turns.
    static func drawPattern(_ skin: SnakeSkin, in ctx: CGContext) {
        let palette = skin.palette
        ctx.saveGState()
        ctx.addPath(headPath)
        ctx.clip()
        ctx.setFillColor(palette.spot)
        let c = headCentre
        for (dx, dy, w, h) in [(0.0, -12.5, 8.0, 5.0), (-9.0, -10.0, 5.0, 4.0), (9.0, -10.0, 5.0, 4.0)] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: c.x + dx - w / 2, y: c.y + dy - h / 2, width: w, height: h),
                               cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        }
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setBlendMode(.clear)
        ctx.addPath(headPath)
        ctx.setLineWidth(line)
        ctx.strokePath()
        ctx.setBlendMode(.normal)
    }

    // MARK: - Moving parts

    /// The tail, carrying on from the end of the body and curling up. Its root stays put under
    /// the body; the tip swings furthest, so it bends like the cat's.
    static func drawTail(angle: Double, skin: SnakeSkin, in ctx: CGContext) {
        let end = bodySpine.curves[3].3
        let root = CGPoint(x: end.x - 6, y: end.y - 0.6)
        let lead = CGPoint(x: end.x + 12, y: end.y + 1.2)
        let tip = end + CGVector(dx: 38, dy: -30).rotated(by: angle)
        let bend = end + CGVector(dx: 34, dy: -2).rotated(by: angle * 0.5)
        let spine = Spine(
            curves: [(root, mix(root, end, 0.33), mix(root, end, 0.66), end), (end, lead, bend, tip)],
            widths: [(0, 17), (1, 16.8), (1.55, 9), (2, 3)]
        )
        drawTube(spine, closedStart: false, closedEnd: true, spots: [1.3, 1.65], skin.palette, ctx)
    }

    /// Eyes, cheeks, nostrils, mouth and tongue, facing straight ahead.
    static func drawFace(_ pose: PetPose, skin: SnakeSkin, in ctx: CGContext) {
        let palette = skin.palette
        let c = headCentre
        ctx.setFillColor(PetRenderer.rgb(0xFF6F7D, 0.3 + 0.5 * pose.blush.clamped(0...1)))
        for side in [-1.0, 1.0] {
            ctx.fillEllipse(in: CGRect(x: c.x + side * 12.5 - 4.5, y: c.y + 5, width: 9, height: 5.5))
        }

        for (side, look) in [(-1.0, pose.lookL), (1.0, pose.lookR)] {
            PetRenderer.drawEye(at: CGPoint(x: c.x + side * 8, y: c.y - 2), look: look, pose, size: 0.5,
                                outline: palette.outline, line: palette.outline, ctx)
        }

        ctx.setFillColor(palette.outline.copy(alpha: 0.5) ?? palette.outline)
        for side in [-1.0, 1.0] {
            ctx.fillEllipse(in: CGRect(x: c.x + side * 2.3 - 0.8, y: c.y + 5.2, width: 1.6, height: 1.2))
        }

        let m = CGPoint(x: c.x, y: c.y + 9)
        if pose.mouth > 0.06 {
            let open = pose.mouth.clamped(0...1)
            let half = 3 + 1.8 * open
            let hole = CGRect(x: m.x - half, y: m.y - 0.6, width: half * 2, height: 1.6 + 5 * open)
            ctx.saveGState()
            ctx.addEllipse(in: hole)
            ctx.clip()
            ctx.setFillColor(Ink.mouth)
            ctx.fill(hole)
            ctx.setFillColor(Ink.tongue)
            ctx.fillEllipse(in: CGRect(x: m.x - half * 0.7, y: hole.maxY - hole.height * 0.42, width: half * 1.4, height: hole.height * 0.8))
            ctx.restoreGState()
            ctx.setStrokeColor(palette.outline)
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: hole)
        } else if pose.tongue > 0.04 {
            drawTongue(pose.tongue, from: CGPoint(x: m.x, y: m.y + 1), palette.outline, ctx)
        }

        // A small, content smile.
        ctx.move(to: CGPoint(x: m.x - 5, y: m.y - 0.8))
        ctx.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 0.8), control: CGPoint(x: m.x, y: m.y + 2.6))
        ctx.setStrokeColor(palette.outline)
        ctx.setLineWidth(1.7)
        ctx.strokePath()

        PetRenderer.drawNoseBubble(pose.noseBubble * 0.6, from: CGPoint(x: c.x + 2.3, y: c.y + 5.8), ctx)
    }

    /// The forked tongue, `amount` of the way out.
    private static func drawTongue(_ amount: Double, from root: CGPoint, _ outline: CGColor, _ ctx: CGContext) {
        let length = 1.5 + 6 * amount.clamped(0...1)
        let tip = CGPoint(x: root.x, y: root.y + length)
        let fork = 1.5 + 2 * amount
        let tongue = CGMutablePath()
        tongue.move(to: root)
        tongue.addLine(to: tip)
        tongue.move(to: tip)
        tongue.addLine(to: CGPoint(x: tip.x - fork * 0.8, y: tip.y + fork))
        tongue.move(to: tip)
        tongue.addLine(to: CGPoint(x: tip.x + fork * 0.8, y: tip.y + fork))
        ctx.addPath(tongue)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(3.8)
        ctx.strokePath()
        ctx.addPath(tongue)
        ctx.setStrokeColor(tongueRed)
        ctx.setLineWidth(1.8)
        ctx.strokePath()
    }

    // MARK: - Tubes

    /// Fills a spine with the skin: gradient, spots along the back at the given spine positions,
    /// a pale belly along the underside with scale lines, and an outline. An open end is left
    /// unoutlined so the next piece (the tail under the body) carries on without a seam.
    private static func drawTube(_ spine: Spine, closedStart: Bool, closedEnd: Bool, spots: [CGFloat],
                                 _ skin: SkinPalette, _ ctx: CGContext) {
        let shape = spine.outline(closedStart: closedStart, closedEnd: closedEnd, forFill: true)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // Absolute coordinates, so the tail's gradient lines up with the body's.
        ctx.drawLinearGradient(PetRenderer.gradient(skin.top, skin.bottom),
                               start: CGPoint(x: 0, y: -46), end: CGPoint(x: 0, y: 0), options: [])

        ctx.setFillColor(skin.spot)
        for u in spots {
            let (p, n, half) = spine.frame(at: u)
            let centre = CGPoint(x: p.x - n.dx * half * 0.32, y: p.y - n.dy * half * 0.32)
            ctx.saveGState()
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.rotate(by: atan2(-n.dx, n.dy))
            let w = half * 0.78, h = half * 0.5
            ctx.addPath(CGPath(roundedRect: CGRect(x: -w, y: -h, width: w * 2, height: h * 2), cornerWidth: h, cornerHeight: h, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // The belly: the underside third of the tube.
        let samples = spine.samples
        let belly = CGMutablePath()
        belly.move(to: samples[0].edge(1))
        for s in samples.dropFirst() { belly.addLine(to: s.edge(1)) }
        for s in samples.reversed() { belly.addLine(to: s.edge(0.36)) }
        belly.closeSubpath()
        ctx.addPath(belly)
        ctx.setFillColor(skin.belly)
        ctx.fillPath()
        ctx.setStrokeColor(skin.bellyLine)
        ctx.setLineWidth(1.1)
        for (index, s) in samples.enumerated() where index % 3 == 1 {
            ctx.move(to: s.edge(1.2))
            ctx.addLine(to: s.edge(0.36))
        }
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(spine.outline(closedStart: closedStart, closedEnd: closedEnd, forFill: false))
        ctx.setStrokeColor(skin.outline)
        ctx.setLineWidth(line)
        ctx.strokePath()
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

private extension CGVector {
    func rotated(by angle: Double) -> CGVector {
        CGVector(dx: dx * cos(angle) - dy * sin(angle), dy: dx * sin(angle) + dy * cos(angle))
    }
}

private func + (p: CGPoint, v: CGVector) -> CGPoint {
    CGPoint(x: p.x + v.dx, y: p.y + v.dy)
}
