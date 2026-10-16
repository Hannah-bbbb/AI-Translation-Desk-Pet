import CoreGraphics

/// Small things that float off the pet: snores, hearts, a "!" when he spots a selection,
/// notes when he hears music, sparks of electricity when he is plugged in.
struct Particle {
    enum Kind { case zzz, heart, spark, alert, question, note, bolt }

    var kind: Kind
    /// Design points relative to the feet; y grows downward.
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    var size: Double
    var age = 0.0

    var progress: Double { (age / life).clamped(0...1) }
}

/// Everything the renderer needs to draw one frame.
struct PetPose {
    /// 1 is the resting shape; above 1 he is flatter and wider, below 1 taller and thinner.
    var squash = 1.0
    /// How far the feet are off the ground.
    var lift = 0.0
    /// Roll around the feet, in radians.
    var tilt = 0.0
    /// Ear rotation in radians; positive droops outward, negative perks inward.
    var earL = 0.0
    var earR = 0.0
    /// 1 wide open, 0 shut.
    var eyeOpen = 1.0
    /// Where each pupil points, inside the unit disc.
    var lookL = CGVector.zero
    var lookR = CGVector.zero
    /// Shifts the whole face a little, which reads as the head turning.
    var face = CGVector.zero
    var pupil = 1.0
    /// Above 0.5 the eyes become happy arcs.
    var joy = 0.0
    /// 0 closed, 1 a full yawn.
    var mouth = 0.0
    var blush = 0.0
    var tail = 0.0
    /// 0 awake, 1 asleep.
    var sleep = 0.0
    /// Size of the snot bubble he blows while asleep, 0…1.
    var noseBubble = 0.0
    var particles: [Particle] = []
}
