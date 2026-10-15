import CoreGraphics
import Foundation

/// Draws the cat, one part at a time. Everything is in points relative to his feet with y
/// pointing down. `PetStage` turns each part into a layer and moves the layers around.
enum PetRenderer {
    /// Size of the whole scene at scale 1, and where the feet stand inside it.
    static let canvas = CGSize(width: 220, height: 200)
    static let feet = CGPoint(x: 102, y: 178)
    /// Height of the ear tips above the feet. The speech bubble's tail points here.
    static let headTop: CGFloat = 118

    // Each part's bounding box, roomy enough for every pose it can take.
    static let shadowBox = CGRect(x: -52, y: -6, width: 104, height: 14)
    static let tailBox = CGRect(x: 24, y: -84, width: 92, height: 92)
    static let earBox = CGRect(x: 10, y: -122, width: 48, height: 66)
    static let bodyBox = CGRect(x: -64, y: -100, width: 128, height: 106)
    static let stripesBox = CGRect(x: -22, y: -100, width: 44, height: 26)
    static let faceBox = CGRect(x: -76, y: -82, width: 152, height: 60)
    static let particleBox = CGRect(x: -100, y: -176, width: 216, height: 124)
    /// The ears swivel around the middle of their base.
    static let earPivot = CGPoint(x: 34, y: -76)

    // MARK: - Palette

    private enum Ink {
        static let outline = rgb(0x4B2E1E)
        static let furTop = rgb(0xFFC56B)
        static let furBottom = rgb(0xFFA443)
        static let stripe = rgb(0xEE8526)
        static let cream = rgb(0xFFF4DF)
        static let earInner = rgb(0xFF9FA6)
        static let nose = rgb(0xE8656F)
        static let mouth = rgb(0x6A2424)
        static let tongue = rgb(0xFF8E96)
        static let pupil = rgb(0x2A1810)
        static let collar = rgb(0x2EC4B6)
        static let bell = rgb(0xFFD447)
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static let furGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [Ink.furTop, Ink.furBottom] as CFArray,
        locations: [0, 1]
    )!

    // MARK: - Still parts

    /// A gumdrop: flat underneath, domed on top, 116 wide and 96 tall.
    private static let bodyPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -38, y: 0))
        p.addCurve(to: CGPoint(x: -58, y: -40), control1: CGPoint(x: -56, y: 0), control2: CGPoint(x: -61, y: -20))
        p.addCurve(to: CGPoint(x: 0, y: -96), control1: CGPoint(x: -55, y: -76), control2: CGPoint(x: -32, y: -96))
        p.addCurve(to: CGPoint(x: 58, y: -40), control1: CGPoint(x: 32, y: -96), control2: CGPoint(x: 55, y: -76))
        p.addCurve(to: CGPoint(x: 38, y: 0), control1: CGPoint(x: 61, y: -20), control2: CGPoint(x: 56, y: 0))
        p.closeSubpath()
        return p
    }()

    static func drawShadow(in ctx: CGContext) {
        ctx.setFillColor(rgb(0x000000, 0.17))
        ctx.fillEllipse(in: CGRect(x: -50, y: -5, width: 100, height: 12))
    }

    /// Fur, belly, collar and bell, outline, paws.
    static func drawBody(in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.drawLinearGradient(furGradient, start: CGPoint(x: 0, y: -96), end: .zero, options: [])

        ctx.setFillColor(Ink.cream)
        ctx.fillEllipse(in: CGRect(x: -31, y: -25, width: 62, height: 46))

        let collar = CGMutablePath()
        collar.move(to: CGPoint(x: -64, y: -31))
        collar.addQuadCurve(to: CGPoint(x: 64, y: -31), control: CGPoint(x: 0, y: -13))
        ctx.addPath(collar)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(10.5)
        ctx.strokePath()
        ctx.addPath(collar)
        ctx.setStrokeColor(Ink.collar)
        ctx.setLineWidth(5.5)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(bodyPath)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(3)
        ctx.strokePath()

        let bell = CGRect(x: -6.2, y: -27.5, width: 12.4, height: 12.4)
        ctx.setFillColor(Ink.bell)
        ctx.fillEllipse(in: bell)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(2.2)
        ctx.strokeEllipse(in: bell)
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: 0, y: bell.midY + 1))
        ctx.addLine(to: CGPoint(x: 0, y: bell.maxY - 2))
        ctx.strokePath()

        for side in [-1.0, 1.0] {
            let paw = CGRect(x: side * 17 - 11, y: -12, width: 22, height: 15)
            ctx.setFillColor(Ink.cream)
            ctx.fillEllipse(in: paw)
            ctx.setStrokeColor(Ink.outline)
            ctx.setLineWidth(2.6)
            ctx.strokeEllipse(in: paw)
        }
    }

    /// Tabby stripes on the forehead. They sit in their own layer above the body so they can
    /// slide sideways as the head turns.
    static func drawStripes(in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.setStrokeColor(Ink.stripe)
        ctx.setLineWidth(5.5)
        for (x, length) in [(-12.0, 13.0), (0.0, 18.0), (12.0, 13.0)] {
            ctx.move(to: CGPoint(x: x * 1.15, y: -102))
            ctx.addLine(to: CGPoint(x: x, y: -97 + length))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Shave off what would cover the body's outline underneath.
        ctx.setBlendMode(.clear)
        ctx.addPath(bodyPath)
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.setBlendMode(.normal)
    }

    /// The right ear, upright. The left one is the same picture mirrored.
    static func drawEar(in ctx: CGContext) {
        let outer = CGPoint(x: 50, y: -62)
        let inner = CGPoint(x: 18, y: -90)
        let tip = CGPoint(x: 46, y: -117)

        let ear = CGMutablePath()
        ear.move(to: outer)
        ear.addArc(tangent1End: tip, tangent2End: inner, radius: 7)
        ear.addLine(to: inner)
        ear.closeSubpath()
        ctx.addPath(ear)
        ctx.setFillColor(Ink.furTop)
        ctx.fillPath()
        ctx.addPath(ear)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(3)
        ctx.strokePath()

        let centre = CGPoint(x: (outer.x + inner.x + tip.x) / 3, y: (outer.y + inner.y + tip.y) / 3 + 3)
        let shrink: (CGPoint) -> CGPoint = { mix(centre, $0, 0.5) }
        let lining = CGMutablePath()
        lining.move(to: shrink(outer))
        lining.addArc(tangent1End: shrink(tip), tangent2End: shrink(inner), radius: 3.5)
        lining.addLine(to: shrink(inner))
        lining.closeSubpath()
        ctx.addPath(lining)
        ctx.setFillColor(Ink.earInner)
        ctx.fillPath()
    }

    // MARK: - Moving parts

    static func drawTail(angle: Double, in ctx: CGContext) {
        // The tip swings further than the middle, so the tail bends instead of pivoting like a stick.
        let base = CGPoint(x: 40, y: -12)
        let c1 = base + CGVector(dx: 34, dy: 6)
        let c2 = base + CGVector(dx: 50, dy: -22).rotated(by: angle * 0.5)
        let end = base + CGVector(dx: 32, dy: -46).rotated(by: angle)

        let tail = CGMutablePath()
        tail.move(to: base)
        tail.addCurve(to: end, control1: c1, control2: c2)
        ctx.addPath(tail)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(17)
        ctx.strokePath()
        ctx.addPath(tail)
        ctx.setStrokeColor(Ink.furBottom)
        ctx.setLineWidth(11)
        ctx.strokePath()

        // Cream tip: the last quarter of the same curve, cut out with de Casteljau.
        let t: CGFloat = 0.74
        let a = mix(base, c1, t), b = mix(c1, c2, t), c = mix(c2, end, t)
        let d = mix(a, b, t), e = mix(b, c, t)
        let tipPath = CGMutablePath()
        tipPath.move(to: mix(d, e, t))
        tipPath.addCurve(to: end, control1: e, control2: c)
        ctx.addPath(tipPath)
        ctx.setStrokeColor(Ink.cream)
        ctx.setLineWidth(11)
        ctx.strokePath()
    }

    /// Eyes, cheeks, whiskers, nose and mouth, facing straight ahead. Turning the head is done
    /// by sliding the whole layer.
    static func drawFace(_ pose: PetPose, in ctx: CGContext) {
        ctx.setFillColor(rgb(0xFF6F7D, 0.28 + 0.5 * pose.blush.clamped(0...1)))
        for side in [-1.0, 1.0] {
            ctx.fillEllipse(in: CGRect(x: side * 37 - 8.5, y: -50, width: 17, height: 10))
        }

        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(1.8)
        for side in [-1.0, 1.0] {
            ctx.move(to: CGPoint(x: side * 50, y: -52))
            ctx.addLine(to: CGPoint(x: side * 71, y: -56))
            ctx.move(to: CGPoint(x: side * 50, y: -46))
            ctx.addLine(to: CGPoint(x: side * 71, y: -45))
        }
        ctx.strokePath()

        drawEye(at: CGPoint(x: -21, y: -62), look: pose.lookL, pose, ctx)
        drawEye(at: CGPoint(x: 21, y: -62), look: pose.lookR, pose, ctx)

        let m = CGPoint(x: 0, y: -44)
        if pose.mouth > 0.06 {
            let open = pose.mouth.clamped(0...1)
            let half = 5 + 2.5 * open
            let hole = CGRect(x: m.x - half, y: m.y + 0.5, width: half * 2, height: 2.5 + 9.5 * open)
            ctx.saveGState()
            ctx.addEllipse(in: hole)
            ctx.clip()
            ctx.setFillColor(Ink.mouth)
            ctx.fill(hole)
            ctx.setFillColor(Ink.tongue)
            ctx.fillEllipse(in: CGRect(x: m.x - half * 0.75, y: hole.maxY - hole.height * 0.45, width: half * 1.5, height: hole.height * 0.8))
            ctx.restoreGState()
            ctx.setStrokeColor(Ink.outline)
            ctx.setLineWidth(2.2)
            ctx.strokeEllipse(in: hole)
        }

        ctx.move(to: CGPoint(x: m.x - 7.5, y: m.y + 0.5))
        ctx.addQuadCurve(to: CGPoint(x: m.x, y: m.y - 0.5), control: CGPoint(x: m.x - 4, y: m.y + 5.5))
        ctx.addQuadCurve(to: CGPoint(x: m.x + 7.5, y: m.y + 0.5), control: CGPoint(x: m.x + 4, y: m.y + 5.5))
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(2.4)
        ctx.strokePath()

        ctx.setFillColor(Ink.nose)
        ctx.fillEllipse(in: CGRect(x: m.x - 3.4, y: m.y - 6.4, width: 6.8, height: 4.8))

        if pose.noseBubble > 0.02 {
            let r = 2 + 8.5 * pose.noseBubble
            let centre = CGPoint(x: m.x + 4 + r * 0.75, y: m.y - 4 + r * 0.3)
            let bubble = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(rgb(0xBFE9FF, 0.55))
            ctx.fillEllipse(in: bubble)
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.9))
            ctx.setLineWidth(1.3)
            ctx.strokeEllipse(in: bubble)
            ctx.setFillColor(rgb(0xFFFFFF, 0.9))
            ctx.fillEllipse(in: CGRect(x: centre.x - r * 0.55, y: centre.y - r * 0.6, width: r * 0.4, height: r * 0.4))
        }
    }

    private static func drawEye(at c: CGPoint, look: CGVector, _ pose: PetPose, _ ctx: CGContext) {
        let open = pose.eyeOpen.clamped(0...1) * (1 - pose.sleep.clamped(0...1))
        let happy = pose.joy > 0.5

        if happy || open < 0.14 {
            // Shut. Happy eyes arch upward, sleeping eyes sag, a blink is almost flat.
            let bend: CGFloat = happy ? -11 : 3 + 7 * pose.sleep
            let y = c.y + (happy ? 4 : 1)
            ctx.move(to: CGPoint(x: c.x - 10, y: y))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 10, y: y), control: CGPoint(x: c.x, y: y + bend))
            ctx.setStrokeColor(Ink.outline)
            ctx.setLineWidth(3.2)
            ctx.strokePath()
            return
        }

        let rx: CGFloat = 12.5
        let ry = 14 * open
        let white = CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
        ctx.saveGState()
        ctx.addEllipse(in: white)
        ctx.clip()
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(white)
        let r = 7.4 * pose.pupil
        let p = CGPoint(x: c.x + look.dx * 5.2, y: c.y + look.dy * 6.2)
        ctx.setFillColor(Ink.pupil)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.66, width: r * 0.62, height: r * 0.62))
        ctx.fillEllipse(in: CGRect(x: p.x + r * 0.2, y: p.y + r * 0.22, width: r * 0.3, height: r * 0.3))
        ctx.restoreGState()
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(2.6)
        ctx.strokeEllipse(in: white)
    }

    // MARK: - Particles

    static func drawParticles(_ particles: [Particle], in ctx: CGContext) {
        for particle in particles {
            draw(particle, ctx)
        }
    }

    private static func draw(_ p: Particle, _ ctx: CGContext) {
        let t = p.progress
        // Pop in fast, linger, fade out.
        let alpha = min(1, t / 0.12) * (1 - ramp(t, 0.6, 1))
        guard alpha > 0.01 else { return }
        let pop = 0.55 + 0.45 * min(1, t / 0.14)

        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.translateBy(x: p.x, y: p.y)

        switch p.kind {
        case .zzz:
            let s = p.size * (0.7 + 0.7 * t)
            ctx.rotate(by: -0.18)
            let z = CGMutablePath()
            z.move(to: CGPoint(x: -s, y: -s))
            z.addLine(to: CGPoint(x: s, y: -s))
            z.addLine(to: CGPoint(x: -s, y: s))
            z.addLine(to: CGPoint(x: s, y: s))
            stroke(z, width: s * 0.5, fill: Ink.cream, ctx)

        case .heart:
            let s = p.size * pop
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: 0, y: s))
            heart.addCurve(to: CGPoint(x: -s, y: -0.2 * s), control1: CGPoint(x: -0.35 * s, y: 0.65 * s), control2: CGPoint(x: -s, y: 0.35 * s))
            heart.addCurve(to: CGPoint(x: 0, y: -0.45 * s), control1: CGPoint(x: -s, y: -0.85 * s), control2: CGPoint(x: -0.25 * s, y: -0.95 * s))
            heart.addCurve(to: CGPoint(x: s, y: -0.2 * s), control1: CGPoint(x: 0.25 * s, y: -0.95 * s), control2: CGPoint(x: s, y: -0.85 * s))
            heart.addCurve(to: CGPoint(x: 0, y: s), control1: CGPoint(x: s, y: 0.35 * s), control2: CGPoint(x: 0.35 * s, y: 0.65 * s))
            fill(heart, rgb(0xFF6B8B), ctx)

        case .spark:
            let s = p.size * pop
            ctx.rotate(by: t * 1.5)
            let star = CGMutablePath()
            for i in 0..<8 {
                let radius = i.isMultiple(of: 2) ? s : s * 0.36
                let angle = Double(i) * .pi / 4
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            fill(star, Ink.bell, ctx)

        case .alert:
            let s = p.size * pop
            let mark = CGMutablePath()
            mark.move(to: CGPoint(x: 0, y: -s))
            mark.addLine(to: CGPoint(x: 0, y: 0.2 * s))
            mark.move(to: CGPoint(x: 0, y: s))
            mark.addLine(to: CGPoint(x: 0, y: s))
            stroke(mark, width: s * 0.55, fill: Ink.bell, ctx)

        case .question:
            let s = p.size * pop
            let mark = CGMutablePath()
            mark.move(to: CGPoint(x: -0.55 * s, y: -0.55 * s))
            mark.addCurve(to: CGPoint(x: 0.55 * s, y: -0.55 * s), control1: CGPoint(x: -0.55 * s, y: -1.25 * s), control2: CGPoint(x: 0.55 * s, y: -1.25 * s))
            mark.addCurve(to: CGPoint(x: 0, y: 0.3 * s), control1: CGPoint(x: 0.55 * s, y: -0.05 * s), control2: CGPoint(x: 0, y: -0.15 * s))
            mark.move(to: CGPoint(x: 0, y: s))
            mark.addLine(to: CGPoint(x: 0, y: s))
            stroke(mark, width: s * 0.5, fill: Ink.cream, ctx)
        }
        ctx.restoreGState()
    }

    /// A stroked glyph with a dark rim, so it stays readable on any wallpaper.
    private static func stroke(_ path: CGPath, width: CGFloat, fill: CGColor, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(width + 3.2)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(fill)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    private static func fill(_ path: CGPath, _ color: CGColor, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(Ink.outline)
        ctx.setLineWidth(1.6)
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
