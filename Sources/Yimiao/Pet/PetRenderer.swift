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
    static let hatBox = CGRect(x: -52, y: -162, width: 104, height: 78)
    /// The top of his head, where a hat sits and turns around.
    static let crown = CGPoint(x: 0, y: -96)
    /// The ears swivel around the middle of their base.
    static let earPivot = CGPoint(x: 34, y: -76)

    /// Where each layer sits for one animal. The canvas and the feet are shared, so the window,
    /// the jumps and the bubble placement do not care which animal he is.
    struct Anatomy {
        var shadowBox: CGRect
        var tailBox: CGRect
        var bodyBox: CGRect
        /// Markings that slide with the head turn: tabby stripes, or the spots on a snake's head.
        var stripesBox: CGRect
        var faceBox: CGRect
        /// The cat's right ear (the left is its mirror image), or the snake's head.
        var earBox: CGRect
        /// What that part swings around.
        var earPivot: CGPoint
        /// Hats are drawn around the cat's crown; this is where that point lands on this animal.
        var hatSeat: CGPoint
        /// Hats are sized for the cat's head; a smaller head wears them smaller.
        var hatScale: CGFloat
        /// Height of the top of the head (ears included) above the feet.
        var headTop: CGFloat
        /// How far the middle of the head is to the side of the feet. The bubble's tail points there.
        var headX: CGFloat
        /// Half his width, for keeping him on screen and finding room for him.
        var halfWidth: CGFloat
        /// The point between his eyes and half the distance between them, which the gaze aims from.
        var eyes: CGPoint
        var eyeSpread: Double
        /// Ellipses, given by their bounding boxes, that count as touching him.
        var hitAreas: [CGRect]
        /// Moves the snores, hearts and sparks so they come off his head.
        var particleOffset: CGVector
        var species = Species.cat
        /// How far his own hats rise above his head, for an animal that does not wear the cat's.
        var hatHeights: [Outfit.Hat: CGFloat] = [:]

        /// From the feet to the top of his head, or of his hat if he wears one.
        func height(wearing outfit: Outfit) -> CGFloat {
            guard let hat = outfit.hat else { return headTop }
            if let own = hatHeights[hat] { return headTop + own }
            // `extraHeight` is measured on the cat: how far the hat rises above his ears.
            let rise = PetRenderer.headTop + outfit.extraHeight + PetRenderer.crown.y
            return max(headTop, -hatSeat.y + rise * hatScale)
        }
    }

    static func anatomy(_ species: Species) -> Anatomy {
        switch species {
        case .cat:
            Anatomy(shadowBox: shadowBox, tailBox: tailBox, bodyBox: bodyBox, stripesBox: stripesBox, faceBox: faceBox,
                    earBox: earBox, earPivot: earPivot, hatSeat: crown, hatScale: 1, headTop: headTop, headX: 0,
                    halfWidth: 64, eyes: CGPoint(x: 0, y: -62), eyeSpread: 21,
                    hitAreas: [CGRect(x: -64, y: -122, width: 128, height: 136)], particleOffset: .zero)
        case .snake:
            SnakeRenderer.anatomy
        case .crab:
            CrabRenderer.anatomy
        }
    }

    // MARK: - Palette

    /// Colours that stay the same whatever his coat. Fur colours come from `CoatPalette`.
    enum Ink {
        /// Particles keep the original brown rim on every coat.
        static let outline = rgb(0x4B2E1E)
        static let cream = rgb(0xFFF4DF)
        static let nose = rgb(0xE8656F)
        static let mouth = rgb(0x6A2424)
        static let tongue = rgb(0xFF8E96)
        static let pupil = rgb(0x2A1810)
        static let collar = rgb(0x2EC4B6)
        static let festiveCollar = rgb(0xD7263D)
        static let bell = rgb(0xFFD447)
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    }

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

    /// Fur, patches, belly, collar and bell, outline, paws.
    static func drawBody(_ look: PetLook, in ctx: CGContext) {
        let coat = look.coat.palette
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.drawLinearGradient(gradient(coat.furTop, coat.furBottom), start: CGPoint(x: 0, y: -96), end: .zero, options: [])

        for patch in coat.patches {
            ctx.saveGState()
            ctx.translateBy(x: patch.center.x, y: patch.center.y)
            ctx.rotate(by: patch.angle)
            ctx.setFillColor(patch.color)
            ctx.fillEllipse(in: CGRect(x: -patch.radii.width, y: -patch.radii.height, width: patch.radii.width * 2, height: patch.radii.height * 2))
            ctx.restoreGState()
        }

        ctx.setFillColor(coat.belly)
        ctx.fillEllipse(in: CGRect(x: -31, y: -25, width: 62, height: 46))

        let collar = CGMutablePath()
        collar.move(to: CGPoint(x: -64, y: -31))
        collar.addQuadCurve(to: CGPoint(x: 64, y: -31), control: CGPoint(x: 0, y: -13))
        ctx.addPath(collar)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(10.5)
        ctx.strokePath()
        ctx.addPath(collar)
        ctx.setStrokeColor(look.outfit == .newYear ? Ink.festiveCollar : Ink.collar)
        ctx.setLineWidth(5.5)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(bodyPath)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(3)
        ctx.strokePath()

        if look.outfit == .newYear {
            drawKnot(ctx)
        } else {
            drawBell(outline: coat.outline, ctx)
        }

        for side in [-1.0, 1.0] {
            let paw = CGRect(x: side * 17 - 11, y: -12, width: 22, height: 15)
            ctx.setFillColor(coat.belly)
            ctx.fillEllipse(in: paw)
            ctx.setStrokeColor(coat.outline)
            ctx.setLineWidth(2.6)
            ctx.strokeEllipse(in: paw)
        }
    }

    /// The bell on his collar, hanging just below the collar's middle.
    static func drawBell(outline: CGColor, _ ctx: CGContext) {
        let bell = CGRect(x: -6.2, y: -27.5, width: 12.4, height: 12.4)
        ctx.setFillColor(Ink.bell)
        ctx.fillEllipse(in: bell)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(2.2)
        ctx.strokeEllipse(in: bell)
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: 0, y: bell.midY + 1))
        ctx.addLine(to: CGPoint(x: 0, y: bell.maxY - 2))
        ctx.strokePath()
    }

    /// A little Chinese knot hanging from the collar in place of the bell, with a tassel.
    static func drawKnot(_ ctx: CGContext) {
        let knot = CGMutablePath()
        knot.move(to: CGPoint(x: 0, y: -29))
        knot.addLine(to: CGPoint(x: 7.5, y: -21.5))
        knot.addLine(to: CGPoint(x: 0, y: -14))
        knot.addLine(to: CGPoint(x: -7.5, y: -21.5))
        knot.closeSubpath()
        ctx.addPath(knot)
        ctx.setFillColor(Ink.festiveCollar)
        ctx.fillPath()
        ctx.addPath(knot)
        ctx.setStrokeColor(Ink.bell)
        ctx.setLineWidth(1.8)
        ctx.strokePath()
        ctx.setStrokeColor(Ink.bell)
        ctx.setLineWidth(1.4)
        ctx.move(to: CGPoint(x: -3.5, y: -21.5))
        ctx.addLine(to: CGPoint(x: 3.5, y: -21.5))
        ctx.move(to: CGPoint(x: 0, y: -25))
        ctx.addLine(to: CGPoint(x: 0, y: -18))
        ctx.strokePath()
        // Tassel.
        ctx.setStrokeColor(Ink.festiveCollar)
        ctx.setLineWidth(2)
        for dx in [-2.0, 0, 2.0] {
            ctx.move(to: CGPoint(x: 0, y: -14))
            ctx.addLine(to: CGPoint(x: dx, y: -7))
        }
        ctx.strokePath()
    }

    /// Tabby stripes on the forehead. They sit in their own layer above the body so they can
    /// slide sideways as the head turns.
    static func drawStripes(_ coat: Coat, in ctx: CGContext) {
        guard let stripe = coat.palette.stripe else { return }
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.setStrokeColor(stripe)
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

    /// The right ear, upright. The left one is the same shape mirrored, in its own colour.
    static func drawEar(_ coat: Coat, left: Bool, in ctx: CGContext) {
        let palette = coat.palette
        let outer = CGPoint(x: 50, y: -62)
        let inner = CGPoint(x: 18, y: -90)
        let tip = CGPoint(x: 46, y: -117)

        let ear = CGMutablePath()
        ear.move(to: outer)
        ear.addArc(tangent1End: tip, tangent2End: inner, radius: 7)
        ear.addLine(to: inner)
        ear.closeSubpath()
        ctx.addPath(ear)
        ctx.setFillColor(left ? palette.earLeft : palette.earRight)
        ctx.fillPath()
        ctx.addPath(ear)
        ctx.setStrokeColor(palette.outline)
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
        ctx.setFillColor(palette.earInner)
        ctx.fillPath()
    }

    // MARK: - Moving parts

    static func drawTail(angle: Double, coat: Coat, in ctx: CGContext) {
        let palette = coat.palette
        // The tip swings further than the middle, so the tail bends instead of pivoting like a stick.
        let base = CGPoint(x: 40, y: -12)
        let c1 = base + CGVector(dx: 34, dy: 6)
        let c2 = base + CGVector(dx: 50, dy: -22).rotated(by: angle * 0.5)
        let end = base + CGVector(dx: 32, dy: -46).rotated(by: angle)

        let tail = CGMutablePath()
        tail.move(to: base)
        tail.addCurve(to: end, control1: c1, control2: c2)
        ctx.addPath(tail)
        ctx.setStrokeColor(palette.outline)
        ctx.setLineWidth(17)
        ctx.strokePath()
        ctx.addPath(tail)
        ctx.setStrokeColor(palette.tail)
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
        ctx.setStrokeColor(palette.tailTip)
        ctx.setLineWidth(11)
        ctx.strokePath()
    }

    /// Eyes, cheeks, whiskers, nose and mouth, facing straight ahead. Turning the head is done
    /// by sliding the whole layer.
    static func drawFace(_ pose: PetPose, coat: Coat, in ctx: CGContext) {
        let palette = coat.palette
        ctx.setFillColor(rgb(0xFF6F7D, 0.28 + 0.5 * pose.blush.clamped(0...1)))
        for side in [-1.0, 1.0] {
            ctx.fillEllipse(in: CGRect(x: side * 37 - 8.5, y: -50, width: 17, height: 10))
        }

        ctx.setStrokeColor(palette.faceLine)
        ctx.setLineWidth(1.8)
        for side in [-1.0, 1.0] {
            ctx.move(to: CGPoint(x: side * 50, y: -52))
            ctx.addLine(to: CGPoint(x: side * 71, y: -56))
            ctx.move(to: CGPoint(x: side * 50, y: -46))
            ctx.addLine(to: CGPoint(x: side * 71, y: -45))
        }
        ctx.strokePath()

        drawEye(at: CGPoint(x: -21, y: -62), look: pose.lookL, pose, outline: palette.outline, line: palette.faceLine, ctx)
        drawEye(at: CGPoint(x: 21, y: -62), look: pose.lookR, pose, outline: palette.outline, line: palette.faceLine, ctx)

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
            ctx.setStrokeColor(palette.outline)
            ctx.setLineWidth(2.2)
            ctx.strokeEllipse(in: hole)
        }

        ctx.move(to: CGPoint(x: m.x - 7.5, y: m.y + 0.5))
        ctx.addQuadCurve(to: CGPoint(x: m.x, y: m.y - 0.5), control: CGPoint(x: m.x - 4, y: m.y + 5.5))
        ctx.addQuadCurve(to: CGPoint(x: m.x + 7.5, y: m.y + 0.5), control: CGPoint(x: m.x + 4, y: m.y + 5.5))
        ctx.setStrokeColor(palette.faceLine)
        ctx.setLineWidth(2.4)
        ctx.strokePath()

        ctx.setFillColor(Ink.nose)
        ctx.fillEllipse(in: CGRect(x: m.x - 3.4, y: m.y - 6.4, width: 6.8, height: 4.8))

        drawNoseBubble(pose.noseBubble, from: CGPoint(x: m.x + 4, y: m.y - 4), ctx)
    }

    /// The snot bubble he blows while asleep, growing out of `nostril` to the lower right.
    static func drawNoseBubble(_ size: Double, from nostril: CGPoint, _ ctx: CGContext) {
        guard size > 0.02 else { return }
        let r = 2 + 8.5 * size
        let centre = CGPoint(x: nostril.x + r * 0.75, y: nostril.y + r * 0.3)
        let bubble = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(rgb(0xBFE9FF, 0.55))
        ctx.fillEllipse(in: bubble)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.9))
        ctx.setLineWidth(1.3)
        ctx.strokeEllipse(in: bubble)
        ctx.setFillColor(rgb(0xFFFFFF, 0.9))
        ctx.fillEllipse(in: CGRect(x: centre.x - r * 0.55, y: centre.y - r * 0.6, width: r * 0.4, height: r * 0.4))
    }

    /// One eye centred on `c`. `size` scales it; `line` draws it shut.
    static func drawEye(at c: CGPoint, look: CGVector, _ pose: PetPose, size: CGFloat = 1,
                        outline: CGColor, line: CGColor, _ ctx: CGContext) {
        let open = pose.eyeOpen.clamped(0...1) * (1 - pose.sleep.clamped(0...1))
        let happy = pose.joy > 0.5

        if happy || open < 0.14 {
            // Shut. Happy eyes arch upward, sleeping eyes sag, a blink is almost flat.
            let bend: CGFloat = (happy ? -11 : 3 + 7 * pose.sleep) * size
            let y = c.y + (happy ? 4 : 1) * size
            ctx.move(to: CGPoint(x: c.x - 10 * size, y: y))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 10 * size, y: y), control: CGPoint(x: c.x, y: y + bend))
            ctx.setStrokeColor(line)
            ctx.setLineWidth(3.2)
            ctx.strokePath()
            return
        }

        let rx: CGFloat = 12.5 * size
        let ry = 14 * size * open
        let white = CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
        ctx.saveGState()
        ctx.addEllipse(in: white)
        ctx.clip()
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(white)
        let r = 7.4 * size * pose.pupil
        let p = CGPoint(x: c.x + look.dx * 5.2 * size, y: c.y + look.dy * 6.2 * size)
        ctx.setFillColor(Ink.pupil)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.66, width: r * 0.62, height: r * 0.62))
        ctx.fillEllipse(in: CGRect(x: p.x + r * 0.2, y: p.y + r * 0.22, width: r * 0.3, height: r * 0.3))
        ctx.restoreGState()
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(2.6)
        ctx.strokeEllipse(in: white)
    }

    // MARK: - Hats

    /// Drawn around the top of his head, in the same space as the body.
    static func drawHat(_ hat: Outfit.Hat, in ctx: CGContext) {
        switch hat {
        case .santa:
            // Floppy red cone with the tip flopping over to the right, white brim and pompom.
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: -27, y: -99))
            cone.addCurve(to: CGPoint(x: 10, y: -136), control1: CGPoint(x: -22, y: -122), control2: CGPoint(x: -8, y: -136))
            cone.addCurve(to: CGPoint(x: 33, y: -122), control1: CGPoint(x: 24, y: -137), control2: CGPoint(x: 32, y: -131))
            cone.addCurve(to: CGPoint(x: 27, y: -99), control1: CGPoint(x: 26, y: -118), control2: CGPoint(x: 24, y: -108))
            cone.closeSubpath()
            fill(cone, rgb(0xE23B3B), width: 2.6, ctx)
            fill(fluffyBand(from: -33, to: 33, y: -96, height: 11), rgb(0xFFFFFF), width: 2.4, ctx)
            fill(CGPath(ellipseIn: CGRect(x: 26, y: -127, width: 14, height: 14), transform: nil), rgb(0xFFFFFF), width: 2.4, ctx)

        case .witch:
            let brim = CGPath(ellipseIn: CGRect(x: -44, y: -104, width: 88, height: 17), transform: nil)
            fill(brim, rgb(0x4B2A6B), width: 2.6, ctx)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: -24, y: -97))
            cone.addCurve(to: CGPoint(x: -2, y: -146), control1: CGPoint(x: -20, y: -118), control2: CGPoint(x: -12, y: -136))
            cone.addQuadCurve(to: CGPoint(x: 18, y: -152), control: CGPoint(x: 8, y: -155))
            cone.addQuadCurve(to: CGPoint(x: 9, y: -138), control: CGPoint(x: 8, y: -144))
            cone.addCurve(to: CGPoint(x: 24, y: -97), control1: CGPoint(x: 12, y: -126), control2: CGPoint(x: 20, y: -112))
            cone.closeSubpath()
            fill(cone, rgb(0x5E3585), width: 2.6, ctx)
            let band = CGMutablePath()
            band.move(to: CGPoint(x: -23, y: -101))
            band.addLine(to: CGPoint(x: 23, y: -101))
            band.addLine(to: CGPoint(x: 21, y: -109))
            band.addLine(to: CGPoint(x: -21, y: -109))
            band.closeSubpath()
            fill(band, rgb(0xFF9A3C), width: 2, ctx)
            let buckle = CGRect(x: -4.5, y: -109, width: 9, height: 8)
            ctx.setStrokeColor(rgb(0xFFD447))
            ctx.setLineWidth(1.8)
            ctx.stroke(buckle)

        case .nightcap:
            // Soft blue cap flopping down the side, with stripes and a pompom.
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: -28, y: -98))
            cap.addCurve(to: CGPoint(x: 24, y: -128), control1: CGPoint(x: -22, y: -124), control2: CGPoint(x: 6, y: -134))
            cap.addCurve(to: CGPoint(x: 44, y: -100), control1: CGPoint(x: 38, y: -124), control2: CGPoint(x: 44, y: -112))
            cap.addCurve(to: CGPoint(x: 26, y: -98), control1: CGPoint(x: 36, y: -104), control2: CGPoint(x: 30, y: -104))
            cap.closeSubpath()
            ctx.saveGState()
            ctx.addPath(cap)
            ctx.clip()
            ctx.setFillColor(rgb(0x6C8FE0))
            ctx.fill(hatBox)
            ctx.setStrokeColor(rgb(0xBFD0FF))
            ctx.setLineWidth(5)
            for offset in stride(from: -30.0, through: 60, by: 13) {
                ctx.move(to: CGPoint(x: offset - 20, y: -96))
                ctx.addLine(to: CGPoint(x: offset + 20, y: -140))
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(cap)
            ctx.setStrokeColor(Ink.outline)
            ctx.setLineWidth(2.6)
            ctx.strokePath()
            fill(fluffyBand(from: -32, to: 30, y: -95, height: 9), rgb(0xF4F6FF), width: 2.2, ctx)
            fill(CGPath(ellipseIn: CGRect(x: 38, y: -103, width: 13, height: 13), transform: nil), rgb(0xF4F6FF), width: 2.2, ctx)
        }
    }

    /// A strip of fluff for a hat brim, its top edge scalloped.
    private static func fluffyBand(from left: CGFloat, to right: CGFloat, y: CGFloat, height: CGFloat) -> CGPath {
        let band = CGMutablePath()
        let bumps = 5
        let step = (right - left) / CGFloat(bumps)
        band.move(to: CGPoint(x: left, y: y))
        band.addLine(to: CGPoint(x: left, y: y - height + 3))
        for i in 0..<bumps {
            let x = left + CGFloat(i) * step
            band.addQuadCurve(to: CGPoint(x: x + step, y: y - height + 3), control: CGPoint(x: x + step / 2, y: y - height - 3))
        }
        band.addLine(to: CGPoint(x: right, y: y))
        band.addQuadCurve(to: CGPoint(x: left, y: y), control: CGPoint(x: (left + right) / 2, y: y + 4))
        band.closeSubpath()
        return band
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

        case .note:
            // An eighth note, swaying as it floats up.
            let s = p.size * pop
            ctx.rotate(by: sin(t * 9) * 0.25)
            let head = CGRect(x: -s * 0.95, y: s * 0.35, width: s * 1.15, height: s * 0.85)
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: s * 0.12, y: s * 0.75))
            stem.addLine(to: CGPoint(x: s * 0.12, y: -s * 1.1))
            stem.addQuadCurve(to: CGPoint(x: s * 0.9, y: -s * 0.15), control: CGPoint(x: s * 0.95, y: -s * 0.75))
            stroke(stem, width: s * 0.32, fill: Ink.cream, ctx)
            fill(CGPath(ellipseIn: head, transform: nil), Ink.cream, ctx)

        case .bolt:
            let s = p.size * pop
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: 0.25 * s, y: -s))
            bolt.addLine(to: CGPoint(x: -0.45 * s, y: 0.1 * s))
            bolt.addLine(to: CGPoint(x: 0.05 * s, y: 0.1 * s))
            bolt.addLine(to: CGPoint(x: -0.25 * s, y: s))
            bolt.addLine(to: CGPoint(x: 0.5 * s, y: -0.2 * s))
            bolt.addLine(to: CGPoint(x: 0, y: -0.2 * s))
            bolt.closeSubpath()
            fill(bolt, Ink.bell, ctx)

        case .bubble:
            // A soap bubble wobbling up: pale fill, white rim, a glint.
            let r = p.size * pop * (1 + 0.25 * t)
            ctx.translateBy(x: sin(t * 9) * 2.5, y: 0)
            let bubble = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.setFillColor(rgb(0xBFE9FF, 0.4))
            ctx.fillEllipse(in: bubble)
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.95))
            ctx.setLineWidth(1.3)
            ctx.strokeEllipse(in: bubble)
            ctx.setFillColor(rgb(0xFFFFFF, 0.95))
            ctx.fillEllipse(in: CGRect(x: -r * 0.55, y: -r * 0.6, width: r * 0.42, height: r * 0.42))

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

    private static func fill(_ path: CGPath, _ color: CGColor, width: CGFloat = 1.6, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(Ink.outline)
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
