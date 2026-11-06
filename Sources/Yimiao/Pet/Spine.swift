import CoreGraphics

/// The middle line of a tube made of cubic Béziers, with a width that changes along it.
/// Positions along it run from 0 to the number of curves: 1.5 is halfway along the second.
struct Spine {
    typealias Cubic = (CGPoint, CGPoint, CGPoint, CGPoint)

    struct Sample {
        var point: CGPoint
        /// Unit normal, pointing to the underside for a spine running left to right.
        var normal: CGVector
        var half: CGFloat

        /// A point across the tube: 1 on the underside edge, 0 on the middle line, -1 on top.
        func edge(_ across: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.dx * half * across, y: point.y + normal.dy * half * across)
        }
    }

    var curves: [Cubic]
    /// Widths at positions along the spine, eased in between.
    var widths: [(at: CGFloat, width: CGFloat)]
    var stepsPerCurve = 18

    var samples: [Sample] {
        let total = curves.count * stepsPerCurve
        return (0...total).map { sample(at: CGFloat($0) / CGFloat(stepsPerCurve)) }
    }

    func frame(at u: CGFloat) -> (CGPoint, CGVector, CGFloat) {
        let s = sample(at: u)
        return (s.point, s.normal, s.half)
    }

    private func sample(at u: CGFloat) -> Sample {
        let index = min(Int(u), curves.count - 1)
        let t = u - CGFloat(index)
        let c = curves[index]
        let v = 1 - t
        let point = CGPoint(
            x: v * v * v * c.0.x + 3 * v * v * t * c.1.x + 3 * v * t * t * c.2.x + t * t * t * c.3.x,
            y: v * v * v * c.0.y + 3 * v * v * t * c.1.y + 3 * v * t * t * c.2.y + t * t * t * c.3.y
        )
        var dx = 3 * v * v * (c.1.x - c.0.x) + 6 * v * t * (c.2.x - c.1.x) + 3 * t * t * (c.3.x - c.2.x)
        var dy = 3 * v * v * (c.1.y - c.0.y) + 6 * v * t * (c.2.y - c.1.y) + 3 * t * t * (c.3.y - c.2.y)
        let length = max(hypot(dx, dy), 0.0001)
        dx /= length
        dy /= length
        return Sample(point: point, normal: CGVector(dx: -dy, dy: dx), half: width(at: u) / 2)
    }

    private func width(at u: CGFloat) -> CGFloat {
        guard let first = widths.first, let last = widths.last else { return 10 }
        if u <= first.at { return first.width }
        for (a, b) in zip(widths, widths.dropFirst()) where u <= b.at {
            let x = (u - a.at) / (b.at - a.at)
            return a.width + (b.width - a.width) * x * x * (3 - 2 * x)
        }
        return last.width
    }

    /// The tube's outline. `forFill` closes it; for the stroke, an open end is left out.
    func outline(closedStart: Bool, closedEnd: Bool, forFill: Bool) -> CGPath {
        let samples = self.samples
        let bottom = samples.map { $0.edge(1) }
        let top = samples.map { $0.edge(-1) }
        let first = samples[0], last = samples[samples.count - 1]
        // Along the spine is the normal turned a quarter.
        let forward = CGVector(dx: last.normal.dy, dy: -last.normal.dx)
        let backward = CGVector(dx: -first.normal.dy, dy: first.normal.dx)
        let path = CGMutablePath()

        /// A round end through the point half a width beyond `s`.
        func cap(_ s: Sample, to end: CGPoint, outward: CGVector, from start: CGPoint) {
            let r = s.half
            let apex = CGPoint(x: s.point.x + outward.dx * r, y: s.point.y + outward.dy * r)
            path.addQuadCurve(to: apex, control: CGPoint(x: start.x + outward.dx * r, y: start.y + outward.dy * r))
            path.addQuadCurve(to: end, control: CGPoint(x: end.x + outward.dx * r, y: end.y + outward.dy * r))
        }

        if !forFill, !closedStart, closedEnd {
            // Open at the start: bottom edge out, round the tip, top edge back.
            path.move(to: bottom[0])
            for p in bottom.dropFirst() { path.addLine(to: p) }
            cap(last, to: top[top.count - 1], outward: forward, from: bottom[bottom.count - 1])
            for p in top.reversed().dropFirst() { path.addLine(to: p) }
            return path
        }
        path.move(to: top[0])
        for p in top.dropFirst() { path.addLine(to: p) }
        if closedEnd {
            cap(last, to: bottom[bottom.count - 1], outward: forward, from: top[top.count - 1])
        } else if forFill {
            path.addLine(to: bottom[bottom.count - 1])
        } else {
            path.move(to: bottom[bottom.count - 1])
        }
        for p in bottom.reversed().dropFirst() { path.addLine(to: p) }
        if closedStart { cap(first, to: top[0], outward: backward, from: bottom[0]) }
        if forFill { path.closeSubpath() }
        return path
    }
}
