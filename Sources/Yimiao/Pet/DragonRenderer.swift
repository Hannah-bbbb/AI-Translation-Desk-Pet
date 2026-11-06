import CoreGraphics
import Foundation

/// Draws the dragon, Chinese style and wingless: a long scaly body arching between four short
/// legs with three claws on each paw, a ridge of fins down the back, a tail ending in a flame
/// of a tuft, and a head raised at the front with antlers, a mane, bushy brows, long whiskers
/// and a beard.
///
/// It uses the cat's layers the way the snake does: the body layer holds neck, body and legs,
/// the right-ear layer holds the head so it nods on its neck, the stripes layer holds the
/// whiskers (which sway with the tail), and the tail layer holds the tail.
enum DragonRenderer {
    /// Where the neck meets the head; the head nods around it.
    static let neckTop = CGPoint(x: -48, y: -60)
    private static let c = CGPoint(x: -50, y: -77)

    static let anatomy = PetRenderer.Anatomy(
        shadowBox: CGRect(x: -60, y: -6, width: 140, height: 14),
        tailBox: CGRect(x: 28, y: -110, width: 90, height: 112),
        bodyBox: CGRect(x: -64, y: -78, width: 124, height: 82),
        stripesBox: CGRect(x: -100, y: -92, width: 98, height: 48),
        faceBox: CGRect(x: -78, y: -102, width: 56, height: 52),
        earBox: CGRect(x: -94, y: -128, width: 88, height: 90),
        earPivot: neckTop,
        hatSeat: CGPoint(x: -50, y: -95),
        hatScale: 0.55,
        headTop: 123,
        headX: -50,
        halfWidth: 106,
        eyes: CGPoint(x: -50, y: -83),
        eyeSpread: 10,
        hitAreas: [
            CGRect(x: -80, y: -126, width: 60, height: 76),
            CGRect(x: -58, y: -56, width: 120, height: 60),
            CGRect(x: 44, y: -82, width: 66, height: 64),
        ],
        particleOffset: CGVector(dx: -50, dy: 2),
        // Tall enough to reach the ground, for the clouds he calls up around his feet.
        particleBox: CGRect(x: -90, y: -176, width: 222, height: 190),
        species: .dragon
    )

    private typealias Ink = PetRenderer.Ink
    private static let line: CGFloat = 2.6

    // MARK: - Shapes

    /// Neck, chest, a hump over the back, hips. The tail layer carries on from the hips.
    private static let bodySpine = Spine(
        curves: [
            (CGPoint(x: -48, y: -62), CGPoint(x: -48, y: -46), CGPoint(x: -42, y: -32), CGPoint(x: -28, y: -28)),
            (CGPoint(x: -28, y: -28), CGPoint(x: -18, y: -25), CGPoint(x: -6, y: -38), CGPoint(x: 8, y: -38)),
            (CGPoint(x: 8, y: -38), CGPoint(x: 20, y: -38), CGPoint(x: 30, y: -25), CGPoint(x: 40, y: -24)),
        ],
        widths: [(0, 17), (0.6, 20), (1, 22), (2, 23), (3, 19)]
    )

    private static let headPath: CGPath = {
        let (w, top, bottom) = (24.0, c.y - 20, c.y + 18)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: bottom))
        p.addCurve(to: CGPoint(x: c.x + w, y: c.y + 1), control1: CGPoint(x: c.x + w * 0.7, y: bottom), control2: CGPoint(x: c.x + w, y: bottom - 8))
        p.addCurve(to: CGPoint(x: c.x, y: top), control1: CGPoint(x: c.x + w, y: top + 9), control2: CGPoint(x: c.x + w * 0.62, y: top))
        p.addCurve(to: CGPoint(x: c.x - w, y: c.y + 1), control1: CGPoint(x: c.x - w * 0.62, y: top), control2: CGPoint(x: c.x - w, y: top + 9))
        p.addCurve(to: CGPoint(x: c.x, y: bottom), control1: CGPoint(x: c.x - w, y: bottom - 8), control2: CGPoint(x: c.x - w * 0.7, y: bottom))
        p.closeSubpath()
        return p
    }()

    private static let muzzle = CGRect(x: c.x - 16.5, y: c.y + 2, width: 33, height: 19)

    // MARK: - Still parts

    static func drawShadow(in ctx: CGContext) {
        ctx.setFillColor(PetRenderer.rgb(0x000000, 0.17))
        ctx.fillEllipse(in: CGRect(x: -48, y: -4.5, width: 104, height: 10))
    }

    /// Legs on the far side, back fins, body, collar, then the legs on the near side.
    static func drawBody(_ look: PetLook, in ctx: CGContext) {
        let skin = look.dragonSkin.palette
        drawLeg(top: CGPoint(x: -15, y: -28), foot: CGPoint(x: -16, y: -1), near: false, skin, ctx)
        drawLeg(top: CGPoint(x: 28, y: -28), foot: CGPoint(x: 26, y: -1), near: false, skin, ctx)

        drawFins(bodySpine, from: 0.55, to: 2.95, skin, ctx)
        drawScaly(bodySpine, closedStart: true, closedEnd: false, skin, ctx)

        // Collar on the neck, below the beard.
        let (p, n, half) = bodySpine.frame(at: 0.6)
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
        ctx.translateBy(x: p.x - 2, y: p.y + 1.5)
        ctx.scaleBy(x: 0.62, y: 0.62)
        ctx.translateBy(x: 0, y: 27.5)
        if look.outfit == .newYear { PetRenderer.drawKnot(ctx) } else { PetRenderer.drawBell(outline: skin.outline, ctx) }
        ctx.restoreGState()

        drawLeg(top: CGPoint(x: -27, y: -24), foot: CGPoint(x: -31, y: -1), near: true, skin, ctx)
        drawLeg(top: CGPoint(x: 41, y: -21), foot: CGPoint(x: 39, y: -1), near: true, skin, ctx)
    }

    /// A short, sturdy leg bending forward at the knee, and a paw with three ivory claws.
    private static func drawLeg(top: CGPoint, foot: CGPoint, near: Bool, _ skin: DragonPalette, _ ctx: CGContext) {
        let leg = Spine(curves: [(top, CGPoint(x: top.x - 1, y: top.y + 8), CGPoint(x: foot.x + 3, y: foot.y - 8), foot)],
                        widths: [(0, 12), (1, 9.5)])
        let shape = leg.outline(closedStart: true, closedEnd: false, forFill: true)
        let paw = CGPath(ellipseIn: CGRect(x: foot.x - 8.5, y: foot.y - 6.5, width: 15, height: 7.5), transform: nil)
        for path in [shape, paw] {
            ctx.addPath(path)
            ctx.setFillColor(skin.bottom)
            ctx.fillPath()
            if !near {
                // The far side is in shade.
                ctx.addPath(path)
                ctx.setFillColor(PetRenderer.rgb(0x000000, 0.16))
                ctx.fillPath()
            }
        }
        if near {
            // Same gradient as the body, so the top of the leg melts into it.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.drawLinearGradient(PetRenderer.gradient(skin.top, skin.bottom), start: CGPoint(x: 0, y: -58), end: CGPoint(x: 0, y: 0), options: [])
            ctx.restoreGState()
        }
        // A near leg is drawn over the body: no outline across its top.
        ctx.addPath(leg.outline(closedStart: !near, closedEnd: false, forFill: false))
        ctx.setStrokeColor(skin.outline)
        ctx.setLineWidth(line)
        ctx.strokePath()
        ctx.addPath(paw)
        ctx.setStrokeColor(skin.outline)
        ctx.setLineWidth(2.2)
        ctx.strokePath()

        // Three talons along the front of the paw, hooking down and forward.
        for i in 0..<3 {
            let base = CGPoint(x: foot.x - 6.5 + CGFloat(i) * 4.2, y: foot.y - 1.8 + (i == 0 ? -0.8 : 0))
            let claw = CGMutablePath()
            claw.move(to: CGPoint(x: base.x - 1.8, y: base.y - 1.8))
            claw.addQuadCurve(to: CGPoint(x: base.x - 4.8, y: base.y + 2.6), control: CGPoint(x: base.x - 4.8, y: base.y - 1.2))
            claw.addQuadCurve(to: CGPoint(x: base.x + 1.8, y: base.y + 0.8), control: CGPoint(x: base.x - 1.4, y: base.y + 2.8))
            claw.closeSubpath()
            fill(claw, skin.horn, skin.outline, width: 1.3, ctx)
        }

        guard near else { return }
        // A flame of fur at the back of the leg, the way dragons are drawn.
        let root = CGPoint(x: top.x + 4.5, y: top.y + 9)
        let tuft = CGMutablePath()
        tuft.move(to: CGPoint(x: root.x - 1, y: root.y - 4))
        tuft.addQuadCurve(to: CGPoint(x: root.x + 9, y: root.y + 6), control: CGPoint(x: root.x + 7, y: root.y - 3))
        tuft.addQuadCurve(to: CGPoint(x: root.x - 0.5, y: root.y + 4), control: CGPoint(x: root.x + 3, y: root.y + 2))
        tuft.closeSubpath()
        fill(tuft, skin.mane, skin.outline, width: 1.8, ctx)
    }

    /// His head, in the layer that nods: mane and beard behind, antlers, then head and snout.
    static func drawHead(_ skin: DragonSkin, in ctx: CGContext) {
        let palette = skin.palette

        // Mane: flame-shaped tufts fanning out behind the head, more of them on the neck side.
        for (degrees, length) in [(150.0, 13.0), (178.0, 16.0), (206.0, 15.0), (236.0, 11.0), (-62.0, 11.0), (-30.0, 16.0),
                                  (-2.0, 18.0), (26.0, 17.0), (54.0, 13.0)] {
            let a = degrees * .pi / 180
            let d = CGVector(dx: cos(a), dy: sin(a))
            let perp = CGVector(dx: -d.dy, dy: d.dx)
            let base = CGPoint(x: c.x + d.dx * 21, y: c.y + d.dy * 16)
            let tip = CGPoint(x: base.x + d.dx * length + perp.dx * 3, y: base.y + d.dy * length + perp.dy * 3)
            let tuft = CGMutablePath()
            tuft.move(to: CGPoint(x: base.x + perp.dx * 7, y: base.y + perp.dy * 7))
            tuft.addQuadCurve(to: tip, control: CGPoint(x: base.x + d.dx * length * 0.5 + perp.dx * 7, y: base.y + d.dy * length * 0.5 + perp.dy * 7))
            tuft.addQuadCurve(to: CGPoint(x: base.x - perp.dx * 7, y: base.y - perp.dy * 7),
                              control: CGPoint(x: base.x + d.dx * length * 0.45 - perp.dx * 1.5, y: base.y + d.dy * length * 0.45 - perp.dy * 1.5))
            tuft.closeSubpath()
            fill(tuft, palette.mane, palette.outline, width: 2.2, ctx)
        }

        // Beard under the chin.
        let beard = CGMutablePath()
        beard.move(to: CGPoint(x: c.x - 7, y: c.y + 17))
        beard.addQuadCurve(to: CGPoint(x: c.x + 1, y: c.y + 33), control: CGPoint(x: c.x - 7, y: c.y + 28))
        beard.addQuadCurve(to: CGPoint(x: c.x + 6, y: c.y + 17), control: CGPoint(x: c.x + 5, y: c.y + 25))
        beard.closeSubpath()
        fill(beard, palette.mane, palette.outline, width: 2.2, ctx)

        // Antlers: a curved beam with a tine branching off backwards.
        for side in [-1.0, 1.0] {
            let base = CGPoint(x: c.x + side * 11, y: c.y - 14)
            let beam = CGMutablePath()
            beam.move(to: base)
            beam.addQuadCurve(to: CGPoint(x: c.x + side * 22, y: c.y - 44), control: CGPoint(x: c.x + side * 19, y: c.y - 28))
            let tine = CGMutablePath()
            tine.move(to: CGPoint(x: c.x + side * 17.5, y: c.y - 28.5))
            tine.addQuadCurve(to: CGPoint(x: c.x + side * 30, y: c.y - 34), control: CGPoint(x: c.x + side * 25, y: c.y - 28))
            for (path, width) in [(beam, 5.0), (tine, 3.4)] {
                ctx.addPath(path)
                ctx.setStrokeColor(palette.outline)
                ctx.setLineWidth(width + 3)
                ctx.strokePath()
            }
            for (path, width) in [(beam, 5.0), (tine, 3.4)] {
                ctx.addPath(path)
                ctx.setStrokeColor(palette.horn)
                ctx.setLineWidth(width)
                ctx.strokePath()
            }
        }

        ctx.saveGState()
        ctx.addPath(headPath)
        ctx.clip()
        ctx.drawLinearGradient(PetRenderer.gradient(palette.top, palette.bottom),
                               start: CGPoint(x: 0, y: c.y - 20), end: CGPoint(x: 0, y: c.y + 18), options: [])
        ctx.restoreGState()
        ctx.addPath(headPath)
        ctx.setStrokeColor(palette.outline)
        ctx.setLineWidth(line)
        ctx.strokePath()

        fill(CGPath(ellipseIn: muzzle, transform: nil), palette.belly, palette.outline, width: 2.2, ctx)
    }

    /// Two long whiskers from the snout, swaying a little with the tail.
    static func drawWhiskers(sway: Double, skin: DragonSkin, in ctx: CGContext) {
        let palette = skin.palette
        let s = CGFloat(sway)
        for side in [-1.0, 1.0] {
            let whisker = CGMutablePath()
            let end = CGPoint(x: c.x + side * 40, y: c.y + 17 + s * 9 * side)
            whisker.move(to: CGPoint(x: c.x + side * 15, y: c.y + 9))
            whisker.addCurve(to: end, control1: CGPoint(x: c.x + side * 27, y: c.y + 4),
                             control2: CGPoint(x: c.x + side * 35, y: c.y + 7 + s * 5 * side))
            whisker.addQuadCurve(to: CGPoint(x: end.x - side * 1, y: end.y + 6), control: CGPoint(x: end.x + side * 5, y: end.y + 5))
            ctx.addPath(whisker)
            ctx.setStrokeColor(palette.outline)
            ctx.setLineWidth(3.8)
            ctx.strokePath()
            ctx.addPath(whisker)
            ctx.setStrokeColor(palette.mane)
            ctx.setLineWidth(1.8)
            ctx.strokePath()
        }
    }

    // MARK: - Moving parts

    /// The tail carries on from the hips, sweeps up and ends in a flame of a tuft.
    static func drawTail(angle: Double, skin: DragonSkin, in ctx: CGContext) {
        let palette = skin.palette
        let end = bodySpine.curves[2].3
        let root = CGPoint(x: end.x - 6, y: end.y - 0.6)
        let lead = CGPoint(x: end.x + 12, y: end.y + 1.2)
        let tip = end + CGVector(dx: 46, dy: -38).rotated(by: angle)
        let bend = end + CGVector(dx: 40, dy: -8).rotated(by: angle * 0.5)
        let spine = Spine(
            curves: [(root, mix(root, end, 0.33), mix(root, end, 0.66), end), (end, lead, bend, tip)],
            widths: [(0, 19.2), (1, 19), (1.6, 11), (2, 6)]
        )

        // The tuft, three flames fanning back from the tip.
        let (p, n, _) = spine.frame(at: 2)
        let along = CGVector(dx: n.dy, dy: -n.dx)
        for (turn, length) in [(-0.95, 13.0), (-0.3, 17.0), (0.4, 12.0)] {
            let d = along.rotated(by: turn)
            let perp = CGVector(dx: -d.dy, dy: d.dx)
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: p.x + perp.dx * 4.5 - d.dx * 3, y: p.y + perp.dy * 4.5 - d.dy * 3))
            let tipPoint = CGPoint(x: p.x + d.dx * length, y: p.y + d.dy * length)
            flame.addQuadCurve(to: tipPoint, control: CGPoint(x: p.x + d.dx * length * 0.5 + perp.dx * 6, y: p.y + d.dy * length * 0.5 + perp.dy * 6))
            flame.addQuadCurve(to: CGPoint(x: p.x - perp.dx * 4.5 - d.dx * 3, y: p.y - perp.dy * 4.5 - d.dy * 3),
                               control: CGPoint(x: p.x + d.dx * length * 0.45 - perp.dx * 1, y: p.y + d.dy * length * 0.45 - perp.dy * 1))
            flame.closeSubpath()
            fill(flame, palette.mane, palette.outline, width: 2.2, ctx)
        }

        drawFins(spine, from: 1.05, to: 1.8, palette, ctx)
        drawScaly(spine, closedStart: false, closedEnd: true, palette, ctx)
    }

    /// Eyes and brows, cheeks, nostrils and mouth, facing straight ahead.
    static func drawFace(_ pose: PetPose, skin: DragonSkin, in ctx: CGContext) {
        let palette = skin.palette
        ctx.setFillColor(PetRenderer.rgb(0xFF6F7D, 0.3 + 0.5 * pose.blush.clamped(0...1)))
        for side in [-1.0, 1.0] {
            ctx.fillEllipse(in: CGRect(x: c.x + side * 18.5 - 4, y: c.y - 2, width: 8, height: 5))
        }

        for (side, look) in [(-1.0, pose.lookL), (1.0, pose.lookR)] {
            PetRenderer.drawEye(at: CGPoint(x: c.x + side * 10, y: c.y - 6), look: look, pose, size: 0.56,
                                outline: palette.outline, line: palette.outline, ctx)
        }

        // Bushy brows, which lift when he is excited.
        let lift = CGFloat((pose.pupil - 1).clamped(0...0.6)) * 4
        for side in [-1.0, 1.0] {
            let brow = CGMutablePath()
            brow.move(to: CGPoint(x: c.x + side * 4.5, y: c.y - 14.5 - lift))
            brow.addQuadCurve(to: CGPoint(x: c.x + side * 16, y: c.y - 16 - lift), control: CGPoint(x: c.x + side * 10, y: c.y - 19 - lift))
            ctx.addPath(brow)
            ctx.setStrokeColor(palette.outline)
            ctx.setLineWidth(5.2)
            ctx.strokePath()
            ctx.addPath(brow)
            ctx.setStrokeColor(palette.mane)
            ctx.setLineWidth(2.8)
            ctx.strokePath()
        }

        ctx.setFillColor(palette.outline.copy(alpha: 0.7) ?? palette.outline)
        for side in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.translateBy(x: c.x + side * 5.5, y: c.y + 7.5)
            ctx.rotate(by: side * 0.35)
            ctx.fillEllipse(in: CGRect(x: -1.9, y: -1.3, width: 3.8, height: 2.6))
            ctx.restoreGState()
        }

        let m = CGPoint(x: c.x, y: c.y + 13.5)
        if pose.mouth > 0.06 {
            let open = pose.mouth.clamped(0...1)
            let half = 4.5 + 2.5 * open
            let hole = CGRect(x: m.x - half, y: m.y - 0.8, width: half * 2, height: 2 + 6 * open)
            ctx.saveGState()
            ctx.addEllipse(in: hole)
            ctx.clip()
            ctx.setFillColor(Ink.mouth)
            ctx.fill(hole)
            ctx.setFillColor(Ink.tongue)
            ctx.fillEllipse(in: CGRect(x: m.x - half * 0.7, y: hole.maxY - hole.height * 0.42, width: half * 1.4, height: hole.height * 0.8))
            ctx.setFillColor(PetRenderer.rgb(0xFFFFFF))
            for side in [-1.0, 1.0] {
                let fang = CGMutablePath()
                fang.move(to: CGPoint(x: m.x + side * (half * 0.55 - 1.5), y: hole.minY))
                fang.addLine(to: CGPoint(x: m.x + side * (half * 0.55 + 1.5), y: hole.minY))
                fang.addLine(to: CGPoint(x: m.x + side * half * 0.55, y: hole.minY + 2 + 1.5 * open))
                fang.closeSubpath()
                ctx.addPath(fang)
            }
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setStrokeColor(palette.outline)
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: hole)
        }
        ctx.move(to: CGPoint(x: m.x - 7.5, y: m.y - 0.5))
        ctx.addQuadCurve(to: CGPoint(x: m.x + 7.5, y: m.y - 0.5), control: CGPoint(x: m.x, y: m.y + 3.5))
        ctx.setStrokeColor(palette.outline)
        ctx.setLineWidth(1.8)
        ctx.strokePath()

        PetRenderer.drawNoseBubble(pose.noseBubble * 0.65, from: CGPoint(x: c.x + 5.5, y: c.y + 8), ctx)
    }

    // MARK: - Pieces

    /// Fins along the top of a spine, leaning back towards the tail, drawn before the tube so
    /// their roots tuck under it.
    private static func drawFins(_ spine: Spine, from start: CGFloat, to end: CGFloat, _ skin: DragonPalette, _ ctx: CGContext) {
        for u in stride(from: start, through: end, by: 0.19) {
            let (p, n, half) = spine.frame(at: u)
            let along = CGVector(dx: n.dy, dy: -n.dx)
            let out = CGVector(dx: -n.dx, dy: -n.dy)
            let h = (half * 0.62).clamped(3.5...7.5)
            let edge = CGPoint(x: p.x + out.dx * (half - 1.5), y: p.y + out.dy * (half - 1.5))
            let tip = CGPoint(x: edge.x + out.dx * h + along.dx * h * 0.75, y: edge.y + out.dy * h + along.dy * h * 0.75)
            let fin = CGMutablePath()
            fin.move(to: CGPoint(x: edge.x - along.dx * 4, y: edge.y - along.dy * 4))
            fin.addQuadCurve(to: tip, control: CGPoint(x: edge.x + out.dx * h * 1.05 - along.dx * 1, y: edge.y + out.dy * h * 1.05 - along.dy * 1))
            fin.addQuadCurve(to: CGPoint(x: edge.x + along.dx * 4, y: edge.y + along.dy * 4),
                             control: CGPoint(x: edge.x + out.dx * h * 0.3 + along.dx * 3.5, y: edge.y + out.dy * h * 0.3 + along.dy * 3.5))
            fin.closeSubpath()
            fill(fin, skin.mane, skin.outline, width: 1.9, ctx)
        }
    }

    /// A tube of scales: gradient, a few scale arcs, belly plates along the underside, outline.
    private static func drawScaly(_ spine: Spine, closedStart: Bool, closedEnd: Bool, _ skin: DragonPalette, _ ctx: CGContext) {
        let shape = spine.outline(closedStart: closedStart, closedEnd: closedEnd, forFill: true)
        let samples = spine.samples
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // Absolute coordinates, so the tail's gradient lines up with the body's.
        ctx.drawLinearGradient(PetRenderer.gradient(skin.top, skin.bottom), start: CGPoint(x: 0, y: -58), end: CGPoint(x: 0, y: 0), options: [])

        // Scales: small arcs in two staggered rows.
        ctx.setStrokeColor(skin.outline.copy(alpha: 0.22) ?? skin.outline)
        ctx.setLineWidth(1.2)
        for (index, s) in samples.enumerated() where index % 4 == 2 {
            for (row, across) in [(0, -0.55), (1, -0.05)] where (index / 4 + row) % 2 == 0 {
                let centre = s.edge(across)
                let r = s.half * 0.24
                let along = CGVector(dx: s.normal.dy, dy: -s.normal.dx)
                ctx.move(to: CGPoint(x: centre.x - along.dx * r, y: centre.y - along.dy * r))
                ctx.addQuadCurve(to: CGPoint(x: centre.x + along.dx * r, y: centre.y + along.dy * r),
                                 control: CGPoint(x: centre.x + s.normal.dx * r * 1.6, y: centre.y + s.normal.dy * r * 1.6))
            }
        }
        ctx.strokePath()

        let belly = CGMutablePath()
        belly.move(to: samples[0].edge(1))
        for s in samples.dropFirst() { belly.addLine(to: s.edge(1)) }
        for s in samples.reversed() { belly.addLine(to: s.edge(0.4)) }
        belly.closeSubpath()
        ctx.addPath(belly)
        ctx.setFillColor(skin.belly)
        ctx.fillPath()
        ctx.setStrokeColor(skin.bellyLine)
        ctx.setLineWidth(1.2)
        for (index, s) in samples.enumerated() where index % 3 == 1 {
            ctx.move(to: s.edge(1.2))
            ctx.addLine(to: s.edge(0.4))
        }
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(spine.outline(closedStart: closedStart, closedEnd: closedEnd, forFill: false))
        ctx.setStrokeColor(skin.outline)
        ctx.setLineWidth(line)
        ctx.strokePath()
    }

    private static func fill(_ path: CGPath, _ colour: CGColor, _ outline: CGColor, width: CGFloat, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setFillColor(colour)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(width)
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
