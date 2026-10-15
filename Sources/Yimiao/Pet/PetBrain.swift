import CoreGraphics
import Foundation

/// Decides what the pet is doing and turns that into a pose, one frame at a time.
///
/// Each frame starts from a neutral set of targets, layers on whatever applies (sleep, gaze,
/// the running script, being carried), then lets the springs chase the result.
final class PetBrain {
    enum Activity { case idle, thinking, speaking }
    enum Gesture { case hop, wiggle, stretch, yawn, tilt, cheer }

    var activity: Activity = .idle
    var isHeld = false
    /// Horizontal speed of the window while he is being carried, in design points per second.
    var carrySpeed = 0.0
    /// The bubble normally sits above his head; near the top of the screen it flips below.
    var bubbleBelow = false
    private(set) var isAsleep = false
    /// True while something is moving fast enough to deserve the display's full refresh rate.
    var isLively: Bool { livelyHold > 0 }
    private var livelyHold = 0.5

    private var springs = Channel.allCases.map { channel -> Spring in
        let (stiffness, damping) = channel.tuning
        return Spring(channel.rest, stiffness: stiffness, damping: damping)
    }
    fileprivate var sleepTarget = 0.0
    fileprivate var lift = 0.0
    fileprivate var liftVelocity = 0.0

    private var clock = 0.0
    private var breath = 0.0
    private var mouse = CGPoint(x: 0, y: -400)
    private var stillTime = 0.0
    private var attention = 1.0
    private var blinkTimer = 2.0
    private var blinkHold = 0.0
    private var idleTimer = 3.0
    private var dreamTimer = 6.0
    private var snoreTimer = 0.0
    private var noseBubble = 0.0
    private var petMeter = 0.0
    private var pettedTime = 0.0
    private var happyTime = 0.0
    private var heartTimer = 0.0
    private var script: Script?
    private var particles: [Particle] = []

    // MARK: - Input

    /// `point` is the cursor in design points relative to the feet (y down); `travel` is how far it moved.
    func updateMouse(_ point: CGPoint, travel: Double, dt: Double) {
        mouse = point
        guard travel > 0.3 else {
            stillTime += dt
            return
        }
        if stillTime > 6, !isAsleep {
            // Something moved after a long lull: ears up.
            kick(.earL, -5)
            kick(.earR, -5)
        }
        stillTime = 0
        if script?.yieldsToMouse == true { script = nil }
        if !isHeld, hitTest(point) { petMeter += travel }
    }

    /// Whether a point (same space as `updateMouse`) lands on his body, ears included.
    func hitTest(_ point: CGPoint) -> Bool {
        let dx = point.x / 64
        let dy = (point.y + 54 + lift) / 68
        return dx * dx + dy * dy <= 1
    }

    // MARK: - Reactions

    func fallAsleep() {
        guard !isAsleep else { return }
        isAsleep = true
        activity = .idle
        script = .dozeOff()
    }

    func wakeUp() {
        guard isAsleep else { return }
        isAsleep = false
        sleepTarget = 0
        stillTime = 0
        idleTimer = 4
        script = .wake()
    }

    /// A click: he jiggles like jelly.
    func poke() {
        kick(.squash, 2.6)
        blinkHold = 0.1
        interrupt()
    }

    /// He spotted a selection.
    func notice() {
        interrupt()
        kick(.earL, -6)
        kick(.earR, -6)
        kick(.squash, -1.3)
        spawn(.alert, x: 2, y: -136, vx: 0, vy: -12, life: 0.9, size: 8)
    }

    /// The translation landed.
    func celebrate() {
        interrupt()
        // Mid-leap he is already airborne; the landing is celebration enough.
        if script == nil { script = .hop() }
        happyTime = 0.9
        for i in 0..<5 {
            let angle = -Double.pi * (0.12 + 0.19 * Double(i)) + Double.random(in: -0.1...0.1)
            spawn(.spark, x: cos(angle) * 46, y: -64 + sin(angle) * 50, vx: cos(angle) * 55, vy: sin(angle) * 55, life: 0.75, size: 4.5)
        }
    }

    /// Something went wrong.
    func confuse() {
        interrupt()
        if script == nil { script = .headTilt(direction: 1, hold: 1.6) }
        spawn(.question, x: 30, y: -128, vx: 4, vy: -8, life: 1.6, size: 9)
    }

    /// A move to go with something he says. Skipped while he is busy dozing off or waking up.
    func perform(_ gesture: Gesture) {
        guard !isAsleep, script?.interruptible ?? true else { return }
        idleTimer = max(idleTimer, 3)
        switch gesture {
        case .hop: script = .hop()
        case .wiggle: script = .wiggle()
        case .stretch: script = .stretch()
        case .yawn: script = .yawn()
        case .tilt: script = .headTilt(direction: 1, hold: 1.2)
        case .cheer: celebrate()
        }
    }

    /// Airborne for `duration` seconds while the window carries him across the screen.
    /// `direction` is -1 heading left, 1 heading right.
    func leap(for duration: Double, direction: Double) {
        script = .leap(duration: duration, direction: direction)
    }

    /// He was put down after being carried.
    func drop() {
        kick(.squash, 2.4)
        idleTimer = 2
    }

    // MARK: - Frame

    func tick(dt rawDt: Double) -> PetPose {
        let dt = rawDt.clamped(0...0.1)
        clock += dt
        let asleep = value(.sleep).clamped(0...1)
        let awake = 1 - asleep

        var t = Targets()
        t[.sleep] = sleepTarget

        // Breathing never stops; asleep it is slower and deeper.
        breath += dt * 2 * .pi / (2.8 + 1.8 * asleep)
        t[.squash] = 1 + sin(breath) * (0.012 + 0.018 * asleep) + 0.15 * asleep
        t[.earL] = 0.3 * asleep
        t[.earR] = 0.3 * asleep
        t[.tail] = 0.36 * asleep + awake * (sin(clock * 1.9) * 0.1 + sin(clock * 0.7) * 0.05)
        t[.faceY] = 0.45 * asleep
        t[.blush] = 0.3 * asleep

        if !isAsleep {
            gaze(dt, &t)
            blink(dt, &t)
            switch activity {
            case .idle:
                break
            case .thinking:
                // Watching the bubble, ears pricked, tail ticking.
                let y = bubbleBelow ? 0.75 : -0.8
                let x = sin(clock * 2.2) * 0.22
                t.setLook(x, y)
                t[.faceX] = x * 0.4
                t[.faceY] = y * 0.6
                t[.earL] -= 0.14
                t[.earR] -= 0.14
                t[.tail] = sin(clock * 5) * 0.16
            case .speaking:
                // Mouthing the words as they stream in.
                t[.mouth] = 0.2 + 0.45 * abs(sin(clock * 12)) * (0.55 + 0.45 * sin(clock * 3.3))
            }
        }

        if isHeld {
            t[.squash] -= 0.09
            t[.tilt] = (carrySpeed / 1800).clamped(-0.5...0.5)
            t[.pupil] = 0.82
            t[.eyeOpen] = 1
            t[.mouth] = 0.25
            t[.earL] += 0.18
            t[.earR] += 0.18
            t[.tail] = 0.3
        }

        pet(dt, &t)
        runScript(dt, &t)
        scheduleIdle(dt)

        if lift > 0 { t[.squash] -= 0.07 }
        var fastest = 0.0
        for channel in Channel.allCases {
            springs[channel.rawValue].target = t[channel]
            springs[channel.rawValue].step(dt)
            fastest = max(fastest, abs(springs[channel.rawValue].velocity))
        }
        // Breathing and the lazy tail sway stay far below this; blinks, bounces and tracking do not.
        if fastest > 0.6 || lift > 0 || isHeld {
            livelyHold = 0.5
        } else {
            livelyHold -= dt
        }
        if lift > 0 || liftVelocity > 0 {
            liftVelocity -= 1500 * dt
            lift += liftVelocity * dt
            if lift <= 0 {
                lift = 0
                liftVelocity = 0
                kick(.squash, 2.4)
            }
        }

        snore(dt, asleep: asleep)
        advanceParticles(dt)

        var pose = PetPose()
        pose.squash = value(.squash).clamped(0.72...1.4)
        pose.lift = lift
        pose.tilt = value(.tilt)
        pose.earL = value(.earL)
        pose.earR = value(.earR)
        pose.eyeOpen = value(.eyeOpen)
        pose.lookL = CGVector(dx: value(.lookLX).clamped(-1...1), dy: value(.lookLY).clamped(-1...1))
        pose.lookR = CGVector(dx: value(.lookRX).clamped(-1...1), dy: value(.lookRY).clamped(-1...1))
        pose.face = CGVector(dx: value(.faceX), dy: value(.faceY))
        pose.pupil = value(.pupil)
        pose.joy = value(.joy)
        pose.mouth = value(.mouth)
        pose.blush = value(.blush)
        pose.tail = value(.tail)
        pose.sleep = asleep
        pose.noseBubble = noseBubble
        pose.particles = particles
        return pose
    }

    // MARK: - Behaviours

    private func gaze(_ dt: Double, _ t: inout Targets) {
        // He follows the cursor while it moves and loses interest once it has sat still for a while.
        let wanted = stillTime < 6 ? 1.0 : 0.0
        attention += (wanted - attention) * min(1, dt * (wanted > attention ? 10 : 1.2))
        let drift = 1 - attention
        let wanderX = sin(clock * 0.43) * 0.35 + sin(clock * 1.1) * 0.1
        let wanderY = sin(clock * 0.31) * 0.12

        // Each eye aims on its own, so he goes cross-eyed when the cursor sits on his nose.
        let left = aim(from: CGPoint(x: -21, y: -62 - lift), reach: 60)
        let right = aim(from: CGPoint(x: 21, y: -62 - lift), reach: 60)
        t[.lookLX] = left.dx * attention + wanderX * drift
        t[.lookLY] = left.dy * attention + wanderY * drift
        t[.lookRX] = right.dx * attention + wanderX * drift
        t[.lookRY] = right.dy * attention + wanderY * drift

        let head = aim(from: CGPoint(x: 0, y: -60 - lift), reach: 260)
        t[.faceX] = head.dx * attention + wanderX * 0.5 * drift
        t[.faceY] += head.dy * attention
    }

    /// Direction from `origin` to the cursor, shortened when the cursor is close.
    private func aim(from origin: CGPoint, reach: Double) -> CGVector {
        let dx = mouse.x - origin.x
        let dy = mouse.y - origin.y
        let distance = max(hypot(dx, dy), 0.001)
        let pull = distance / (distance + reach)
        return CGVector(dx: dx / distance * pull, dy: dy / distance * pull)
    }

    private func blink(_ dt: Double, _ t: inout Targets) {
        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkHold = 0.085
            blinkTimer = Double.random(in: 0...1) < 0.18 ? 0.26 : Double.random(in: 2.2...6)
        }
        if blinkHold > 0 {
            blinkHold -= dt
            t[.eyeOpen] = 0
        }
    }

    /// Stroking him back and forth fills a meter; past the threshold he melts.
    private func pet(_ dt: Double, _ t: inout Targets) {
        petMeter = max(0, petMeter - 90 * dt)
        if petMeter > 170 {
            petMeter = 110
            pettedTime = 1.3
            happyTime = max(happyTime, 1.3)
        }
        if pettedTime > 0 {
            pettedTime -= dt
            heartTimer -= dt
            if heartTimer <= 0 {
                heartTimer = 0.32
                spawn(.heart, x: Double.random(in: -30...30), y: -104, vx: Double.random(in: -8...8), vy: -30, life: 1.2, size: 6)
            }
        }
        guard happyTime > 0 else { return }
        happyTime -= dt
        t[.joy] = 1
        t[.blush] = 1
        t[.tilt] += sin(clock * 10) * 0.03
        t[.earL] += 0.12
        t[.earR] += 0.12
    }

    private func runScript(_ dt: Double, _ t: inout Targets) {
        guard var running = script else { return }
        running.elapsed += dt
        while running.nextCue < running.cues.count, running.cues[running.nextCue].at <= running.elapsed {
            running.cues[running.nextCue].run(self)
            running.nextCue += 1
        }
        running.shape(running.elapsed, &t)
        script = running.elapsed >= running.duration ? nil : running
    }

    private func scheduleIdle(_ dt: Double) {
        guard script == nil, !isHeld else { return }
        if isAsleep {
            // Dreaming: the odd ear or tail twitch.
            dreamTimer -= dt
            if dreamTimer <= 0 {
                dreamTimer = Double.random(in: 5...13)
                script = Bool.random() ? .earTwitch(left: Bool.random()) : .tailFlick(strength: 0.12)
            }
            return
        }
        guard activity == .idle, happyTime <= 0 else { return }
        idleTimer -= dt
        guard idleTimer <= 0 else { return }
        idleTimer = Double.random(in: 2.5...7)

        var options: [(weight: Double, make: () -> Script)] = [
            (3, { .earTwitch(left: Bool.random()) }),
            (2, { .hop() }),
            (2, { .wiggle() }),
            (2, { .headTilt(direction: Bool.random() ? 1 : -1, hold: 1.1) }),
            (2, { .tailFlick(strength: 0.3) }),
            (1, { .stretch() }),
            (0.7, { .yawn() }),
        ]
        if attention < 0.3 { options.append((4, { .lookAround() })) }
        let total = options.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total)
        for option in options {
            roll -= option.weight
            if roll < 0 {
                script = option.make()
                return
            }
        }
    }

    private func snore(_ dt: Double, asleep: Double) {
        let deep = asleep > 0.9
        let wanted = deep ? 0.3 + 0.7 * (0.5 - 0.5 * sin(breath)) : 0
        noseBubble += (wanted - noseBubble) * min(1, dt * 6)
        guard deep else {
            snoreTimer = 0.4
            return
        }
        snoreTimer -= dt
        if snoreTimer <= 0 {
            snoreTimer = 1.3
            spawn(.zzz, x: 30, y: -104, vx: 9, vy: -15, life: 2.6, size: 4.5)
        }
    }

    private func advanceParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            if particles[i].kind == .spark { particles[i].vy += 90 * dt }
        }
        particles.removeAll { $0.age >= $0.life }
    }

    // MARK: - Plumbing

    private func value(_ channel: Channel) -> Double {
        springs[channel.rawValue].value
    }

    fileprivate func kick(_ channel: Channel, _ velocity: Double) {
        springs[channel.rawValue].velocity += velocity
    }

    /// Drops the running script unless it is one that must finish (falling asleep, waking up).
    private func interrupt() {
        if script?.interruptible ?? true { script = nil }
        idleTimer = max(idleTimer, 2.5)
    }

    private func spawn(_ kind: Particle.Kind, x: Double, y: Double, vx: Double, vy: Double, life: Double, size: Double) {
        particles.append(Particle(kind: kind, x: x, y: y, vx: vx, vy: vy, life: life, size: size))
    }
}

// MARK: - Channels

/// The animated quantities. Each has its own spring.
private enum Channel: Int, CaseIterable {
    case squash, tilt, earL, earR, eyeOpen
    case lookLX, lookLY, lookRX, lookRY, faceX, faceY
    case pupil, joy, mouth, blush, tail, sleep

    var rest: Double {
        switch self {
        case .squash, .eyeOpen, .pupil: 1
        default: 0
        }
    }

    /// Stiffness and damping. Low damping relative to stiffness means more wobble.
    var tuning: (Double, Double) {
        switch self {
        case .squash: (260, 13)
        case .tilt: (150, 11)
        case .earL, .earR: (320, 15)
        case .eyeOpen: (1100, 55)
        case .lookLX, .lookLY, .lookRX, .lookRY: (260, 25)
        case .faceX, .faceY: (120, 17)
        case .pupil: (200, 22)
        case .joy: (300, 28)
        case .mouth: (340, 26)
        case .blush: (50, 13)
        case .tail: (90, 8)
        case .sleep: (28, 10.5)
        }
    }
}

private struct Targets {
    private var values = Channel.allCases.map(\.rest)

    subscript(channel: Channel) -> Double {
        get { values[channel.rawValue] }
        set { values[channel.rawValue] = newValue }
    }

    mutating func setLook(_ x: Double, _ y: Double) {
        self[.lookLX] = x
        self[.lookRX] = x
        self[.lookLY] = y
        self[.lookRY] = y
    }
}

// MARK: - Scripts

/// A short scripted move layered over the base pose: `shape` bends the targets every frame,
/// `cues` fire once at their time.
private struct Script {
    var duration: Double
    var interruptible = true
    /// Dropped the moment the cursor moves, so tracking wins over idle glances.
    var yieldsToMouse = false
    var shape: (Double, inout Targets) -> Void = { _, _ in }
    var cues: [(at: Double, run: (PetBrain) -> Void)] = []
    var elapsed = 0.0
    var nextCue = 0

    static func hop() -> Script {
        Script(
            duration: 0.75,
            shape: { time, t in if time < 0.13 { t[.squash] += 0.15 } },
            cues: [(0.13, { $0.launch(255) })]
        )
    }

    static func earTwitch(left: Bool) -> Script {
        Script(duration: 0.55, shape: { time, t in
            if (0..<0.08).contains(time) || (0.2..<0.28).contains(time) {
                t[left ? .earL : .earR] -= 0.5
            }
        })
    }

    static func lookAround() -> Script {
        let first = Bool.random() ? 1.0 : -1.0
        return Script(duration: 2.6, yieldsToMouse: true, shape: { time, t in
            let x = time < 1 ? first : (time < 1.25 ? 0 : (time < 2.2 ? -first : 0))
            t.setLook(x * 0.8, 0.05)
            t[.faceX] = x * 0.55
        })
    }

    static func wiggle() -> Script {
        Script(duration: 1.3, shape: { time, t in
            t[.tilt] += sin(time * 2 * .pi * 2.6) * 0.085 * sin(time / 1.3 * .pi)
            t[.tail] = sin(time * 17) * 0.28
            if time > 0.15, time < 1.1 { t[.joy] = 1 }
        })
    }

    static func headTilt(direction: Double, hold: Double) -> Script {
        Script(duration: hold + 0.7, shape: { time, t in
            let amount = bump(time, 0, 0.25, hold, hold + 0.3)
            t[.tilt] += direction * 0.13 * amount
            t[direction > 0 ? .earL : .earR] -= 0.2 * amount
        })
    }

    static func tailFlick(strength: Double) -> Script {
        Script(duration: 1.1, shape: { time, t in
            t[.tail] += sin(time * 15) * strength * sin(time / 1.1 * .pi)
        })
    }

    static func stretch() -> Script {
        Script(
            duration: 1.7,
            shape: { time, t in
                let amount = bump(time, 0, 0.5, 1, 1.3)
                t[.squash] -= 0.15 * amount
                t[.earL] += 0.25 * amount
                t[.earR] += 0.25 * amount
                t[.tail] = -0.3 * amount
                if amount > 0.3 { t[.joy] = 1 }
            },
            cues: [(1.3, { $0.kick(.squash, 1.6) })]
        )
    }

    static func yawn() -> Script {
        Script(duration: 2.1, shape: { time, t in
            let amount = bump(time, 0.15, 0.6, 1.2, 1.5)
            t[.mouth] = amount
            t[.squash] -= 0.07 * amount
            t[.earL] += 0.2 * amount
            t[.earR] += 0.2 * amount
            if amount > 0.35 { t[.eyeOpen] = 0 } else if time > 1.2, time < 1.9 { t[.eyeOpen] = 0.45 }
        })
    }

    /// Stretched out mid-air with his eyes on where he is going, then a squashy landing.
    static func leap(duration: Double, direction: Double) -> Script {
        Script(
            duration: duration + 0.4,
            interruptible: false,
            shape: { time, t in
                guard time < duration else { return }
                let air = sin(time / duration * .pi)
                t[.squash] -= 0.13 * air
                t[.tilt] += direction * 0.12 * air
                t[.earL] += 0.3 * air
                t[.earR] += 0.3 * air
                t[.tail] = -0.3 * air
                t.setLook(direction * 0.8, 0.2)
                t[.faceX] = direction * 0.6
            },
            cues: [(duration, { $0.kick(.squash, 2.6) })]
        )
    }

    /// A last yawn, eyelids sinking, then out.
    static func dozeOff() -> Script {
        Script(
            duration: 1.6,
            interruptible: false,
            shape: { time, t in
                t[.mouth] = bump(time, 0.1, 0.5, 0.9, 1.2)
                t[.eyeOpen] = 1 - 0.75 * ramp(time, 0.1, 0.9)
            },
            cues: [(1.1, { $0.sleepTarget = 1 })]
        )
    }

    /// Bleary eyes, a big yawn and stretch, then a shake to get going.
    static func wake() -> Script {
        Script(duration: 2.3, interruptible: false, shape: { time, t in
            let yawning = bump(time, 0.45, 0.8, 1.3, 1.55)
            t[.mouth] = yawning
            t[.squash] -= 0.11 * yawning
            if time < 0.45 { t[.eyeOpen] = 0.35 } else if yawning > 0.4 { t[.eyeOpen] = 0 }
            if time > 1.65, time < 2.15 {
                t[.tilt] += sin((time - 1.65) * 2 * .pi * 5) * 0.07
            }
        })
    }
}

fileprivate extension PetBrain {
    func launch(_ velocity: Double) {
        liftVelocity = velocity
        lift = 0.01
    }
}
