import Acoustics_String
import Foundation
import Testing

extension `Acoustics Tests` {
    @Suite struct Bow {}
}

extension `Acoustics Tests`.Bow {
    /// A violin's A string, 440 Hz on 0.325 m at 50 N, with no bending, losing as nylon does and at a bridge of
    /// resistance R: Schelleng's string.
    ///
    /// WHY nylon's loss: with none, nothing on the grid rounds the Helmholtz corner, and the ripple behind it breaks
    /// the bow's grip again within the period at any force; the bowed string never settles. Nylon's loss, which grows
    /// with frequency, is enough.
    static let length = 0.325
    static let tension = 50.0
    static let frequency = 440.0
    static let density = tension / (4 * length * length * frequency * frequency)
    /// The string's wave impedance, √(T μ).
    static let impedance = (tension * density).squareRoot()

    /// How a bow's bowing goes: the string's sliding speed past the bow at every step, and the bridge's motion.
    struct Bowing {
        var rubbing: [Double] = []
        var finite = true
    }

    /// Bows the string at `beta` of its length from the bridge, `speed` and `force` held, for `seconds`. The bridge
    /// is a dashpot of `resistance` times the string's impedance across: Schelleng's bridge resistance R.
    static func bow(
        force: Double,
        speed: Double = 0.1,
        beta: Double = 0.1,
        resistance: Double = 40,
        seconds: Double = 0.25,
        losses: Acoustics.String.Losses = .nylon(diameter: Space.Physical.metres(0.0007)),
        stiffness: Double = 0
    ) -> Bowing {
        let interval = `Acoustics Tests`.interval
        var string = Acoustics.String(
            length: Space.Physical.metres(length),
            tension: Force.newtons(tension),
            density: Density.Linear.amount(density),
            stiffness: Rigidity.Flexural.amount(stiffness),
            losses: losses,
            every: Time.Duration.seconds(interval)
        )
        string.bow = .init(
            place: Space.Physical.metres(length * (1 - beta)),
            speed: Velocity.amount(speed),
            force: Force.newtons(force)
        )
        let dashpot = resistance * impedance
        var end = 0.0
        var bowing = Bowing()
        let steps = Int(seconds / interval)
        bowing.rubbing.reserveCapacity(steps)
        for _ in 0..<steps {
            end += interval * string.pull.across.underlying / dashpot
            string.advance(end: .init(up: .zero, across: Space.Physical.metres(end)))
            bowing.rubbing.append(string.rubbing.underlying)
            if !end.isFinite {
                bowing.finite = false
                break
            }
        }
        return bowing
    }

    /// Over the last `periods` periods: how many times a period the string starts to slip, and the share of the time
    /// it slips.
    static func slips(_ bowing: Bowing, periods: Int = 20) -> (perPeriod: Double, share: Double) {
        let interval = `Acoustics Tests`.interval
        let span = Int(Double(periods) / frequency / interval)
        let tail = bowing.rubbing.suffix(span)
        var starts = 0
        var slipping = 0
        var was = false
        for speed in tail {
            let slips = speed.magnitude > 1e-6
            if slips { slipping += 1 }
            if slips && !was { starts += 1 }
            was = slips
        }
        return (Double(starts) / Double(periods), Double(slipping) / Double(tail.count))
    }

    /// Schelleng's (1973) most force at which the bow can still let the string go once a period:
    /// 2 Z₀ v / ((μ_s − μ_d) β).
    static func most(speed: Double = 0.1, beta: Double = 0.1) -> Double {
        let rosin = Acoustics.String.Rosin()
        return 2 * impedance * speed / ((rosin.still - rosin.sliding).underlying * beta)
    }

    /// Schelleng's (1973) least force that keeps the bow from slipping twice a period: Z₀² v / (2 R (μ_s − μ_d) β²).
    static func least(speed: Double = 0.1, beta: Double = 0.1, resistance: Double = 40) -> Double {
        let rosin = Acoustics.String.Rosin()
        return impedance * impedance * speed
            / (2 * resistance * impedance * (rosin.still - rosin.sliding).underlying * beta * beta)
    }

    /// The share of the last `periods` periods in which the string slips exactly once, a period after the last slip.
    static func regular(_ bowing: Bowing, periods: Int = 40) -> Double {
        let interval = `Acoustics Tests`.interval
        let period = 1 / frequency / interval
        let tail = Array(bowing.rubbing.suffix(Int(Double(periods) * period)))
        var starts: [Int] = []
        for index in tail.indices.dropFirst() where tail[index].magnitude > 1e-6 && tail[index - 1].magnitude <= 1e-6 {
            starts.append(index)
        }
        let gaps = zip(starts, starts.dropFirst()).map { Double($1 - $0) }
        return Double(gaps.filter { ($0 - period).magnitude <= 3 }.count) / Double(periods)
    }

    /// How fast the string slides back under the bow while it slips, on average over the last `periods` periods.
    static func slide(_ bowing: Bowing, periods: Int = 20) -> Double {
        let interval = `Acoustics Tests`.interval
        let tail = bowing.rubbing.suffix(Int(Double(periods) / frequency / interval)).filter { $0.magnitude > 1e-6 }
        return tail.reduce(0, +) / Double(tail.count)
    }

    /// Helmholtz motion: one corner runs round the string, so the bow holds it for 1 − β of each period and lets it
    /// slip once, for β of the period, sliding back at v / β past the bow (Helmholtz 1863; Schelleng 1973). The grid
    /// rounds the corner over a few steps, so the slip is allowed five steps more or less, and to be up to a quarter
    /// slower.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [(0.08, 0.2), (0.1, 0.1), (0.125, 0.3)])
    func `Between Schelleng's forces the string moves in Helmholtz motion`(bowing: (beta: Double, speed: Double)) {
        let force = 0.6 * Self.most(speed: bowing.speed, beta: bowing.beta)
        let bowed = Self.bow(force: force, speed: bowing.speed, beta: bowing.beta, seconds: 0.5)
        #expect(bowed.finite)
        #expect(Self.regular(bowed) >= 0.9, "one slip a period")
        // WHY: the grid rounds the corner over a few steps, which lengthens each slip by those steps and slows it.
        let period = 1 / (Self.frequency * `Acoustics Tests`.interval)
        let share = Self.slips(bowed).share
        #expect(((share - bowing.beta) * period).magnitude < 5, "slips for \(share) of a period at β \(bowing.beta)")
        let slide = -Self.slide(bowed) * bowing.beta / bowing.speed
        #expect(slide > 0.75 && slide < 1.1, "slides back at \(slide) × v / β")
    }

    /// Above Schelleng's most force, 2 Z₀ v / ((μ_s − μ_d) β), the string's pull can't break the bow's grip once a
    /// period, and the motion turns raucous. Just under it, it is still Helmholtz motion.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [0.08, 0.125])
    func `Above Schelleng's most force the bow no longer lets the string go once a period`(beta: Double) {
        let most = Self.most(speed: 0.2, beta: beta)
        #expect(Self.regular(Self.bow(force: 0.75 * most, speed: 0.2, beta: beta, seconds: 0.5)) >= 0.9)
        for over in [1.5, 2] {
            #expect(
                Self.regular(Self.bow(force: over * most, speed: 0.2, beta: beta, seconds: 0.5)) < 0.2,
                "at \(over)×"
            )
        }
    }

    /// Below Schelleng's least force, Z₀² v / (2 R (μ_s − μ_d) β²), the corner's ripple breaks the grip again before
    /// the period is out, and the string slips twice or more a period. Helmholtz motion needs more than his least
    /// force here: the string's own losses round the corner too, and rosin's curve is not his two-valued friction.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [12.0, 24])
    func `Below Schelleng's least force the string slips more than once a period`(resistance: Double) {
        let beta = 0.125
        let least = Self.least(speed: 0.2, beta: beta, resistance: resistance)
        for under in [0.5, 1] {
            let bowed = Self.bow(force: under * least, speed: 0.2, beta: beta, resistance: resistance, seconds: 0.5)
            #expect(Self.regular(bowed) == 0)
            #expect(Self.slips(bowed).share > 1.8 * beta, "at \(under)×")
        }
    }

    /// A bow held still on a ringing string only takes its energy.
    @Test func `A bow held still only takes energy`() {
        let interval = `Acoustics Tests`.interval
        var string = Acoustics.String(
            length: Space.Physical.metres(Self.length),
            tension: Force.newtons(Self.tension),
            density: Density.Linear.amount(Self.density),
            every: Time.Duration.seconds(interval)
        )
        string.displace { place in
            let along = place.underlying / Self.length
            return .init(up: .zero, across: Space.Physical.metres(0.001 * Swift.min(along / 0.3, (1 - along) / 0.7)))
        }
        string.bow = .init(place: Space.Physical.metres(0.9 * Self.length), speed: .zero, force: Force.newtons(0.3))
        var last = string.energy.underlying
        let first = last
        for _ in 0..<4_000 {
            string.advance()
            let now = string.energy.underlying
            #expect(now <= last * (1 + 1e-12) + 1e-18)
            last = now
        }
        #expect(last < 0.5 * first)
    }
}
