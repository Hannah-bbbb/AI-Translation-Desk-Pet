import Foundation

/// A damped spring chasing `target`. Every moving part of the pet runs through one of these,
/// so nothing ever snaps from one pose to the next.
struct Spring {
    var value: Double
    var target: Double
    var velocity = 0.0
    var stiffness: Double
    var damping: Double

    init(_ value: Double, stiffness: Double, damping: Double) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(_ dt: Double) {
        // Stiff springs (the eyelids) blow up at display-link step sizes, so integrate in small slices.
        let slices = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(slices)
        for _ in 0..<slices {
            velocity += (stiffness * (target - value) - damping * velocity) * h
            value += velocity * h
        }
    }
}

extension Comparable {
    func clamped(_ range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// 0 before `a`, 1 after `b`, eased in between.
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = ((t - a) / (b - a)).clamped(0...1)
    return x * x * (3 - 2 * x)
}

/// Rises over `a…b`, holds, falls over `c…d`.
func bump(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
    ramp(t, a, b) * (1 - ramp(t, c, d))
}
