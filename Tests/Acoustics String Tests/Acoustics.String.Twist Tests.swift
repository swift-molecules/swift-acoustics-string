import Acoustics_String
import Testing

extension `Acoustics Tests` {
    @Suite struct Twist {}
}

extension `Acoustics Tests`.Twist {
    /// A violin's plain steel E string: 659.26 Hz on 0.325 m, 0.26 mm across, losing as steel does. Its twist runs at
    /// √(G / ρ) for steel, G = 79 GPa and ρ = 7850 kg/m³, with a torsional Q of 17, as Bavu, Smith and Wolfe (2005)
    /// measured on a steel string.
    static let length = 0.325
    static let frequency = 659.26
    static let diameter = 0.000_26
    static let density = 7850 * Double.pi * diameter * diameter / 4
    static let tension = density * 4 * length * length * frequency * frequency
    static let impedance = (tension * density).squareRoot()
    static let twist = Acoustics.String.Twist.solid(
        density: Density.Linear.amount(density),
        speed: Velocity.amount((79e9 / 7850).squareRoot()),
        loss: Loss.amount(1 / 17.0)
    )

    static func string(twisting: Bool, losses: Acoustics.String.Losses? = nil) -> Acoustics.String {
        let radius = diameter / 2
        var string = Acoustics.String(
            length: Space.Physical.metres(length),
            tension: Force.newtons(tension),
            density: Density.Linear.amount(density),
            stiffness: Rigidity.Flexural.amount(2e11 * Double.pi * radius * radius * radius * radius / 4),
            losses: losses ?? .steel(diameter: Space.Physical.metres(diameter)),
            every: Time.Duration.seconds(`Acoustics Tests`.interval)
        )
        if twisting { string.twist = twist }
        return string
    }

    /// Schelleng's (1973) most force, 2 Z₀ v / ((μ_s − μ_d) β), and least, Z₀² v / (2 R (μ_s − μ_d) β²), as in
    /// `Acoustics Tests.Bow`.
    static func most(speed: Double, beta: Double) -> Double {
        let rosin = Acoustics.String.Rosin()
        return 2 * impedance * speed / ((rosin.still - rosin.sliding).underlying * beta)
    }

    static func least(speed: Double, beta: Double, resistance: Double) -> Double {
        let rosin = Acoustics.String.Rosin()
        return impedance * speed / (2 * resistance * (rosin.still - rosin.sliding).underlying * beta * beta)
    }

    /// Bows the E string at `beta` from the bridge, at a bridge of 40 times its impedance, for half a second, and
    /// returns the steps at which the surface under the hair starts to slip.
    static func starts(force: Double, twisting: Bool, beta: Double = 0.1, speed: Double = 0.1) -> [Int] {
        let interval = `Acoustics Tests`.interval
        var string = string(twisting: twisting)
        string.bow = .init(
            place: Space.Physical.metres(length * (1 - beta)),
            speed: Velocity.amount(speed),
            force: Force.newtons(force)
        )
        let dashpot = 40 * impedance
        var end = 0.0
        var starts: [Int] = []
        var was = false
        for step in 0..<Int(0.5 / interval) {
            end += interval * string.pull.across.underlying / dashpot
            string.advance(end: .init(up: .zero, across: Space.Physical.metres(end)))
            let slips = string.rubbing.underlying.magnitude > 1e-6
            if slips && !was { starts.append(step) }
            was = slips
        }
        return starts
    }

    /// Over the last 40 periods: the share of gaps between slips that are one period, within half a percent, and how
    /// many slips a period.
    static func settled(_ starts: [Int]) -> (regular: Double, perPeriod: Double) {
        let interval = `Acoustics Tests`.interval
        let period = 1 / (frequency * interval)
        let total = Int(0.5 / interval)
        let tail = starts.filter { $0 >= total - Int(40 * period) }
        let gaps = zip(tail, tail.dropFirst()).map { Double($1 - $0) }
        // WHY: the stiff string's period is a little shorter than 1 / f.
        let near = gaps.filter { ($0 - period).magnitude < 0.05 * period }.sorted()
        let heard = near.isEmpty ? period : near[near.count / 2]
        let regular = gaps.filter { ($0 - heard).magnitude <= Swift.max(3, 0.005 * heard) }.count
        return (Double(regular) / 40, Double(tail.count) / 40)
    }

    /// A string with a twist but no bow moves across exactly as one without: nothing but the bow couples them.
    @Test func `With no bow the twist changes no bit`() {
        var plain = Self.string(twisting: false)
        var twisted = Self.string(twisting: true)
        for index in 0..<2 {
            let shaped: (Length<Space.Physical, Double>) -> Acoustics.String.Offset<Measure<1, Space.Physical>> = {
                let along = $0.underlying / Self.length
                let tent = Swift.min(along / 0.2, (1 - along) / 0.8)
                return .init(up: Space.Physical.metres(0.0005 * tent), across: Space.Physical.metres(0.001 * tent))
            }
            if index == 0 { plain.displace(shaped) } else { twisted.displace(shaped) }
        }
        for _ in 0..<2_000 {
            plain.advance()
            twisted.advance()
        }
        #expect(plain.shape == twisted.shape)
        #expect(plain.pull == twisted.pull)
    }

    /// The twisting wave's grid: as coarse as its speed allows, and its first mode where c / 2L puts it.
    @Test func `The twist's grid steps its speed`() {
        let twist = Self.twist
        #expect((twist.impedance - Self.density / 2 * twist.speed.underlying).magnitude < 1e-12)
        // WHY: a solid round string's twist carries half its mass per length, so its impedance over the string's is
        // c_t / (2 c₀): about 3.7 for steel's 3170 m/s against the E's 429 m/s.
        let ratio = twist.impedance / Self.impedance
        let across = (Self.tension / Self.density).squareRoot()
        #expect((ratio - twist.speed.underlying / (2 * across)).magnitude < 1e-12)
        #expect(ratio > 3.5 && ratio < 4)
    }

    /// With steel's own loss and no twist, the E string never settles into Helmholtz motion: the corner's ripples
    /// break the grip again and again. With the twist, the surface under the hair loses its ripples to the
    /// twisting wave, and the string settles to one slip a period.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [0.4, 0.5, 0.7])
    func `With the twist the steel E settles where it didn't`(fraction: Double) {
        let force = fraction * Self.most(speed: 0.1, beta: 0.1)
        let plain = Self.settled(Self.starts(force: force, twisting: false))
        let twisted = Self.settled(Self.starts(force: force, twisting: true))
        #expect(plain.regular < 0.5, "without the twist, at \(fraction) × the most")
        #expect(twisted.regular >= 0.9, "with the twist, at \(fraction) × the most")
        #expect((twisted.perPeriod - 1).magnitude <= 0.05, "\(twisted.perPeriod) slips a period")
    }

    /// Above Schelleng's most force the twisting string still can't be let go once a period.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [1.5, 2])
    func `Above Schelleng's most force the twisting string no longer settles`(over: Double) {
        let starts = Self.starts(force: over * Self.most(speed: 0.1, beta: 0.1), twisting: true)
        #expect(Self.settled(starts).regular < 0.2)
    }

    /// Below Schelleng's least force the string slips more than once a period. With the twist it needs about 6 times
    /// his formula here, between 5 and 6: the string's and the twist's losses round the corner too, and rosin's curve
    /// is not his two-valued friction.
    @Test(.enabled(if: `Acoustics Tests`.String.optimized), arguments: [1.0, 3, 5])
    func `Below about six times Schelleng's least force the twisting string slips more than once`(under: Double) {
        let least = Self.least(speed: 0.1, beta: 0.1, resistance: 40)
        let settled = Self.settled(Self.starts(force: under * least, twisting: true))
        #expect(settled.regular < 0.2)
        #expect(settled.perPeriod > 1.5, "at \(under) × the least")
    }

    @Test(.enabled(if: `Acoustics Tests`.String.optimized))
    func `Six times Schelleng's least force is enough with the twist`() {
        let least = Self.least(speed: 0.1, beta: 0.1, resistance: 40)
        #expect(Self.settled(Self.starts(force: 6 * least, twisting: true)).regular >= 0.9)
    }

    /// With the bow held still, and then lifted, the string and its twist only lose energy: the twist's own loss and
    /// the bow's grip take it, and nothing gives it back. The string loses nothing itself here, as in
    /// `Acoustics Tests.Bow`, so every loss is the twist's or the bow's.
    @Test func `Without a moving bow the twisting string only loses energy`() {
        var string = Self.string(twisting: true, losses: Acoustics.String.Losses.none)
        string.displace { place in
            let along = place.underlying / Self.length
            return .init(up: .zero, across: Space.Physical.metres(0.0005 * Swift.min(along / 0.3, (1 - along) / 0.7)))
        }
        string.bow = .init(place: Space.Physical.metres(0.9 * Self.length), speed: .zero, force: Force.newtons(0.3))
        let first = string.energy.underlying
        var last = first
        for step in 0..<6_000 {
            if step == 3_000 { string.bow = nil }
            string.advance()
            let now = string.energy.underlying
            #expect(now <= last * (1 + 1e-12) + 1e-18, "at step \(step)")
            last = now
        }
        #expect(last < 0.5 * first)
    }
}
