import CoreGraphics
import Foundation

/// Draws the pixel crab: a block body 8 pixels wide and 6 tall with two square eyes, arms
/// sticking out at the sides and four stubby legs, 12 by 8 pixels in all.
///
/// Smooth squashing and rolling would smear the pixels, so his whole figure goes into one
/// layer, redrawn only when a pixel-sized step of the pose changes. The brain's channels are
/// read in pixel terms: the eyes move in half-pixel steps, the ears' perk and droop raise and
/// lower his arms, a crouch shortens his legs, and his own scuttle walks him a few half pixels
/// sideways with his legs stepping. He does not lean: a sliding body would leave a leg behind.
enum CrabRenderer {
    /// Design points per pixel.
    static let unit: CGFloat = 9

    static let anatomy = PetRenderer.Anatomy(
        shadowBox: CGRect(x: -50, y: -6, width: 100, height: 12),
        tailBox: PetRenderer.tailBox,
        bodyBox: PetRenderer.bodyBox,
        stripesBox: PetRenderer.stripesBox,
        // Room for scuttling two pixels either way.
        faceBox: CGRect(x: -84, y: -126, width: 168, height: 132),
        earBox: PetRenderer.earBox,
        earPivot: PetRenderer.earPivot,
        hatSeat: CGPoint(x: 0, y: -72),
        hatScale: 1,
        headTop: 72,
        headX: 0,
        halfWidth: 56,
        eyes: CGPoint(x: 0, y: -58.5),
        eyeSpread: 22.5,
        hitAreas: [CGRect(x: -62, y: -82, width: 124, height: 92)],
        particleOffset: CGVector(dx: 0, dy: 40),
        species: .crab,
        // Pixel hats sit half a pixel down over his top edge.
        hatHeights: [.santa: 7 * unit / 2, .witch: 9 * unit / 2]
    )

    private static let shell = PetRenderer.rgb(0xD97757)
    private static let eye = PetRenderer.rgb(0x141414)
    private static let mouth = PetRenderer.rgb(0x5A2418)
    private static let tongue = PetRenderer.rgb(0xFF8E96)
    private static let blush = PetRenderer.rgb(0xF7A3A3)

    // MARK: - Pose in pixels

    enum Eyes: Int32 { case open, half, shut, sleeping, happy }

    /// One frame of him, in pixel steps. Two poses that look the same make equal frames.
    struct Frame: Equatable {
        /// Eye offset in half pixels, -1…1.
        var lookX = 0, lookY = 0
        var eyes = Eyes.open
        var sparkle = false
        /// 0 closed, up to 3 wide open.
        var mouth = 0
        var blush = false
        /// Arm offsets in half pixels; positive is lower.
        var armL = 0, armR = 0
        /// Leg length in half pixels; 4 is standing.
        var legs = 4
        /// Sideways steps in half pixels; positive is to the right. Each step swaps which legs are up.
        var scuttle = 0
        var clawsOpen = false
        var hat: Outfit.Hat?
        /// How opaque the nightcap is, in quarters, while he drifts off.
        var capFade = 4
        var bow = false
        /// Size of the bubble he blows asleep, in half pixels; 0 is none.
        var bubble = 0

        var key: [Int32] {
            [Int32(lookX), Int32(lookY), eyes.rawValue, sparkle ? 1 : 0, Int32(mouth), blush ? 1 : 0,
             Int32(armL), Int32(armR), Int32(legs), Int32(scuttle), clawsOpen ? 1 : 0,
             hat.map { [.santa: 1, .witch: 2, .nightcap: 3][$0]! } ?? 0,
             Int32(capFade), bow ? 1 : 0, Int32(bubble)]
        }
    }

    /// Reads a pose in pixel steps.
    static func frame(for pose: PetPose, outfit: Outfit) -> Frame {
        var f = Frame()
        // Half a pixel at most: one more and an eye reaches the edge of his body and reads as a notch.
        f.lookX = halves(pose.lookL.dx * 0.6 + pose.lookR.dx * 0.6 + pose.face.dx * 0.8, limit: 1)
        f.lookY = halves(pose.lookL.dy * 0.6 + pose.lookR.dy * 0.6 + pose.face.dy * 0.8, limit: 1)

        let open = pose.eyeOpen.clamped(0...1) * (1 - pose.sleep.clamped(0...1))
        if pose.joy > 0.5 {
            f.eyes = .happy
        } else if pose.sleep > 0.5 {
            f.eyes = .sleeping
        } else if open < 0.2 {
            f.eyes = .shut
        } else if open < 0.7 {
            f.eyes = .half
        }
        f.sparkle = f.eyes == .open && pose.pupil > 1.2
        f.mouth = pose.mouth < 0.12 ? 0 : min(3, 1 + Int(pose.mouth * 3))
        f.blush = pose.blush > 0.45

        // The tail has nothing to move, so a lively swing of it flaps his arms in turn.
        let flap = pose.sleep > 0.5 ? 0 : (pose.tail * 4.4).rounded(.towardZero)
        f.armL = (Int((pose.earL * 6.6).rounded()) - Int(flap)).clamped(-2...2)
        f.armR = (Int((pose.earR * 6.6).rounded()) + Int(flap)).clamped(-2...2)

        f.legs = pose.squash > 1.2 ? 1 : pose.squash > 1.12 ? 2 : pose.squash > 1.05 ? 3 : pose.squash < 0.9 ? 5 : 4
        f.scuttle = Int((pose.scuttle / Double(unit / 2)).rounded()).clamped(-4...4)
        f.clawsOpen = pose.claw > 0.5

        f.hat = outfit.hat ?? (pose.sleep > 0.3 ? .nightcap : nil)
        f.capFade = outfit.hat == nil ? Int((ramp(pose.sleep, 0.3, 0.85) * 4).rounded()) : 4
        f.bow = outfit == .newYear
        f.bubble = pose.noseBubble < 0.1 ? 0 : min(3, 1 + Int(pose.noseBubble * 3))
        return f
    }

    /// How high to draw him for a hop: the lift in half-pixel steps.
    static func lift(_ lift: Double) -> Double {
        (lift / Double(unit / 2)).rounded() * Double(unit / 2)
    }

    /// `value` in half pixels, where ±1 is a strong look, rounded and kept within `limit`.
    private static func halves(_ value: Double, limit: Int) -> Int {
        Int((value * 1.6).rounded()).clamped(-limit...limit)
    }

    // MARK: - Drawing

    static func drawShadow(in ctx: CGContext) {
        ctx.setShouldAntialias(false)
        ctx.setFillColor(PetRenderer.rgb(0x000000, 0.17))
        ctx.fill(CGRect(x: -4 * unit, y: -unit / 4, width: 8 * unit, height: unit / 2))
        ctx.fill(CGRect(x: -4.5 * unit, y: -unit / 4 + unit / 8, width: 9 * unit, height: unit / 4))
    }

    static func draw(_ f: Frame, in ctx: CGContext) {
        ctx.setShouldAntialias(false)
        let legs = CGFloat(f.legs) / 2
        // Grid origin: the top-left pixel of the 12-wide grid, with x and y in pixels from there.
        let left = -6 + CGFloat(f.scuttle) / 2
        let top = -(6 + legs)
        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: (left + x) * unit, y: (top + y) * unit, width: w * unit, height: h * unit)
        }

        ctx.setFillColor(shell)
        // Mid-step, every other leg is lifted half a pixel.
        let stepping = f.scuttle % 2 != 0
        for (index, x) in [2.0, 4, 7, 9].enumerated() {
            let lifted: CGFloat = stepping && index % 2 == 0 ? 0.5 : 0
            ctx.fill(px(x, 6, 1, max(0.5, legs - lifted)))
        }
        ctx.fill(px(2, 0, 8, 6))
        drawArm(px(0, 2 + CGFloat(f.armL) / 2, 2, 2), open: f.clawsOpen, outerOnLeft: true, ctx)
        drawArm(px(10, 2 + CGFloat(f.armR) / 2, 2, 2), open: f.clawsOpen, outerOnLeft: false, ctx)

        let ex = CGFloat(f.lookX) / 2, ey = CGFloat(f.lookY) / 2
        for x: CGFloat in [3, 8] {
            drawEye(f, at: px(x + ex, 1 + ey, 1, 1), ctx)
        }

        if f.blush {
            ctx.setFillColor(blush)
            ctx.fill(px(2.5, 2.5, 1, 0.5))
            ctx.fill(px(8.5, 2.5, 1, 0.5))
        }

        if f.mouth > 0 {
            let width: CGFloat = [0, 1, 1.5, 2][f.mouth]
            let height: CGFloat = [0, 0.5, 0.75, 1][f.mouth]
            let hole = px(6 - width / 2, 2.25, width, height)
            ctx.setFillColor(mouth)
            ctx.fill(hole)
            if f.mouth >= 2 {
                ctx.setFillColor(tongue)
                ctx.fill(CGRect(x: hole.minX + unit / 4, y: hole.maxY - unit / 4, width: hole.width - unit / 2, height: unit / 4))
            }
        }

        if f.bubble > 0 {
            // A pixel ring out of his mouth, growing and shrinking with his breath.
            let size = CGFloat(f.bubble) / 2 + 0.5
            let ring = px(6, 2.5, size, size)
            let q = unit / 4
            ctx.setFillColor(PetRenderer.rgb(0xBFE9FF, 0.45))
            ctx.fill(ring.insetBy(dx: q, dy: q))
            ctx.setFillColor(PetRenderer.rgb(0xFFFFFF, 0.95))
            ctx.fill(CGRect(x: ring.minX + q, y: ring.minY, width: ring.width - 2 * q, height: q))
            ctx.fill(CGRect(x: ring.minX + q, y: ring.maxY - q, width: ring.width - 2 * q, height: q))
            ctx.fill(CGRect(x: ring.minX, y: ring.minY + q, width: q, height: ring.height - 2 * q))
            ctx.fill(CGRect(x: ring.maxX - q, y: ring.minY + q, width: q, height: ring.height - 2 * q))
            ctx.fill(CGRect(x: ring.minX + 2 * q, y: ring.minY + 2 * q, width: q, height: q))
        }

        if f.bow { drawSprite(bow, centreX: (left + 6) * unit, bottom: (top + 4.75) * unit, ctx) }
        if let hat = f.hat {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(f.capFade) / 4)
            drawSprite(sprite(for: hat), centreX: (left + 6) * unit, bottom: (top + 0.5) * unit, ctx)
            ctx.restoreGState()
        }
    }

    /// A claw, 2 by 2 pixels. Open, its outer column has a one-pixel notch, like pincers apart.
    private static func drawArm(_ r: CGRect, open: Bool, outerOnLeft: Bool, _ ctx: CGContext) {
        ctx.setFillColor(shell)
        guard open else {
            ctx.fill(r)
            return
        }
        let h = unit / 2
        let outer = outerOnLeft ? r.minX : r.maxX - h
        ctx.fill(CGRect(x: outerOnLeft ? r.minX + h : r.minX, y: r.minY, width: r.width - h, height: r.height))
        ctx.fill(CGRect(x: outer, y: r.minY, width: h, height: h))
        ctx.fill(CGRect(x: outer, y: r.maxY - h, width: h, height: h))
    }

    private static func drawEye(_ f: Frame, at r: CGRect, _ ctx: CGContext) {
        let q = unit / 4
        ctx.setFillColor(eye)
        switch f.eyes {
        case .open:
            ctx.fill(r)
            if f.sparkle {
                ctx.setFillColor(PetRenderer.rgb(0xFFFFFF))
                ctx.fill(CGRect(x: r.minX + q, y: r.minY + q, width: q, height: q))
            }
        case .half:
            ctx.fill(CGRect(x: r.minX, y: r.minY + 2 * q, width: r.width, height: 2 * q))
        case .shut:
            ctx.fill(CGRect(x: r.minX - q, y: r.minY + 3 * q, width: r.width + 2 * q, height: q))
        case .sleeping:
            // Drooping lids: a line with its ends turned down.
            ctx.fill(CGRect(x: r.minX, y: r.minY + 2 * q, width: r.width, height: q))
            ctx.fill(CGRect(x: r.minX - q, y: r.minY + 3 * q, width: q, height: q))
            ctx.fill(CGRect(x: r.maxX, y: r.minY + 3 * q, width: q, height: q))
        case .happy:
            // ^ in half pixels.
            let h = unit / 2
            ctx.fill(CGRect(x: r.minX - q, y: r.minY + h, width: h, height: h))
            ctx.fill(CGRect(x: r.minX + q, y: r.minY, width: h, height: h))
            ctx.fill(CGRect(x: r.minX + 3 * q, y: r.minY + h, width: h, height: h))
        }
    }

    // MARK: - Sprites

    /// Hats and the New Year bow, drawn in half pixels. Each letter is a colour; dots are empty.
    private static let santa = [
        "...........WW...",
        "..........WWWW..",
        ".......RRRRWW...",
        ".....RRRRRR.....",
        "....RRRRRRRR....",
        "...RRRRRRRRRR...",
        "..RRRRRRRRRRRR..",
        ".WWWWWWWWWWWWWW.",
    ]
    private static let witch = [
        "..........P.....",
        ".........PP.....",
        "........PPP.....",
        ".......PPPP.....",
        "......PPPPP.....",
        ".....PPPPPPP....",
        "....PPPPPPPP....",
        "....OOOYYOOO....",
        "PPPPPPPPPPPPPPPP",
        ".DDDDDDDDDDDDDD.",
    ]
    private static let nightcap = [
        "......BBBBBB......",
        "....BBBLLBBBBB....",
        "...BBBBBBLLBBBBB..",
        "...BLLBBBBBBLLBBWW",
        "...BBBBBBBBBBBBBWW",
        "..WWWWWWWWWWWWWW..",
    ]
    private static let bow = [
        "RRR.RRR",
        "RRRYRRR",
        "RRR.RRR",
    ]

    private static func sprite(for hat: Outfit.Hat) -> [String] {
        switch hat {
        case .santa: santa
        case .witch: witch
        case .nightcap: nightcap
        }
    }

    private static let palette: [Character: CGColor] = [
        "R": PetRenderer.rgb(0xE23B3B), "W": PetRenderer.rgb(0xFFFFFF),
        "P": PetRenderer.rgb(0x5E3585), "D": PetRenderer.rgb(0x4B2A6B),
        "O": PetRenderer.rgb(0xFF9A3C), "Y": PetRenderer.rgb(0xFFD447),
        "B": PetRenderer.rgb(0x6C8FE0), "L": PetRenderer.rgb(0xBFD0FF),
    ]

    /// Draws a sprite centred on `centreX`, with its bottom row ending at `bottom`.
    private static func drawSprite(_ rows: [String], centreX: CGFloat, bottom: CGFloat, _ ctx: CGContext) {
        let h = unit / 2
        let width = CGFloat(rows.map(\.count).max() ?? 0) * h
        let originX = centreX - width / 2
        let originY = bottom - CGFloat(rows.count) * h
        for (row, line) in rows.enumerated() {
            for (column, letter) in line.enumerated() {
                guard let colour = palette[letter] else { continue }
                ctx.setFillColor(colour)
                ctx.fill(CGRect(x: originX + CGFloat(column) * h, y: originY + CGFloat(row) * h, width: h, height: h))
            }
        }
    }
}
