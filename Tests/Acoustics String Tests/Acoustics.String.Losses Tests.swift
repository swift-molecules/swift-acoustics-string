import Foundation
import Testing
@testable import Acoustics_String

extension `Acoustics Tests` {
    @Suite struct Losses {}
}

extension `Acoustics Tests`.Losses {
    /// The test string's partial `n`: its wavenumber and frequency by the stiff string's law.
    static func partial(_ n: Double, of string: Acoustics.String) -> (wavenumber: Double, frequency: Double) {
        let beta = n * Double.pi / string.length.underlying
        let tension = string.tension.underlying
        let density = string.density.underlying
        let stiffness = string.stiffness.underlying
        let frequency =
            (tension / density * beta * beta + stiffness / density * beta * beta * beta * beta).squareRoot()
            / (2 * Double.pi)
        return (beta, frequency)
    }

    /// A plain steel string of the test string's mass: 1.0 mm across at 7850 kg/m³.
    static let steel = Acoustics.String.Losses.steel(diameter: 0.001)
}

extension `Acoustics Tests`.Losses {
    /// Issanchou, Bilbao, Le Carrou, Touzé and Doaré (2017, §4.2): "Selected values are δve = 4.5 × 10⁻³ and
    /// Q⁻¹te = 2.03 × 10⁻⁴."
    @Test func `Steel loses 4.5 × 10⁻³ in bending and 2.03 × 10⁻⁴ to heat, as Issanchou et al. select`() {
        let steel = Acoustics.String.Losses.steel(diameter: 0.001)
        #expect(steel.bending == 4.5e-3)
        #expect(steel.steady == 2.03e-4)
        #expect(steel.air == .room)
    }

    /// Woodhouse (2004, Table I, second string, B₃, plain nylon): "η_B (×10⁻²) … 2.0" and "η_F (×10⁻⁵) … 40".
    @Test func `Nylon loses 2.0 × 10⁻² in bending and 4.0 × 10⁻⁴ steadily, as Woodhouse fits`() {
        let nylon = Acoustics.String.Losses.nylon(diameter: 0.001)
        #expect(nylon.bending == 2.0e-2)
        #expect(nylon.steady == 40e-5)
        #expect(nylon.air == .room)
    }

    /// Woodhouse and Lynch-Aird (2019, Table I): natural gut, E′ 6.0 GPa and E″ 0.24 GPa; p. 520: "fixed values
    /// E = 6 GPa, η_E = 0.04".
    @Test func `Gut loses 0.04 in bending and nothing steadily, as Woodhouse and Lynch-Aird fit`() {
        let gut = Acoustics.String.Losses.gut(diameter: 0.001)
        #expect(gut.bending == 0.04)
        #expect(abs(gut.bending.underlying - 0.24 / 6.0) < 1e-15)
        #expect(gut.steady == .zero)
        #expect(gut.air == .room)
    }

    /// Woodhouse's bending term (2004, eq. 8), B η_B k² / (T + B k²) with k = nπ/L, is this law's to first order in
    /// x = B k² / T: this law gives B δ k² (1 + x) / T, so the two differ by exactly (1 + x)². On his second string
    /// (Table I: L 0.65 m, T 53.4 N, ρ 0.52 g/m, B 160 × 10⁻⁶ N m²), with no air and no steady loss.
    @Test func `Nylon's bending loss is Woodhouse's eq. 8 bending term to first order in the stiffness`() {
        let losses = Acoustics.String.Losses(diameter: 0.001, air: nil, bending: 2.0e-2)
        let (length, tension, density, stiffness) = (0.65, 53.4, 0.52e-3, 160e-6)
        for n in [1.0, 10, 40] {
            let k = n * Double.pi / length
            let x = stiffness * k * k / tension
            let frequency = (tension / density * k * k + stiffness / density * k * k * k * k).squareRoot() / (2 * Double.pi)
            let woodhouse = stiffness * 2.0e-2 * k * k / (tension + stiffness * k * k)
            let found = losses.loss(
                at: Frequency.hertz(frequency),
                tension: Force.newtons(tension),
                density: Density.Linear.amount(density),
                stiffness: Rigidity.Flexural.amount(stiffness)
            ).underlying
            #expect(abs(found / (woodhouse * (1 + x) * (1 + x)) - 1) < 1e-12)
        }
    }

    /// Issanchou et al. (2017, eq. 12, on their Table 1 string: L 1.002 m, d 0.43 mm, T 180.5 N, μ 1.17 × 10⁻³ kg/m,
    /// B 1.78 × 10⁻⁵, in air of η 1.8 × 10⁻⁵ Pa·s and ρ 1.2 kg/m³):
    /// Q⁻¹ = R / (2π μ ν) + 4π² μ E I δ ν² / T² + Q⁻¹te, with R = 2π η + 2π d √(π η ρ ν) and E I = B T L² / π².
    @Test func `A partial's loss is the air's, the bending's and the heat's, by Issanchou et al.'s law`() {
        let air = Acoustics.Air(density: 1.2, speed: 343, viscosity: 1.8e-5)
        let losses = Acoustics.String.Losses.steel(diameter: 0.43e-3, in: air)
        let (length, diameter, tension, density, inharmonicity) = (1.002, 0.43e-3, 180.5, 1.17e-3, 1.78e-5)
        let stiffness = inharmonicity * tension * length * length / (Double.pi * Double.pi)
        for frequency in [196.0, 1_000, 5_000] {
            let drag = 2 * Double.pi * 1.8e-5 + 2 * Double.pi * diameter * (Double.pi * 1.8e-5 * 1.2 * frequency).squareRoot()
            let wanted =
                drag / (2 * Double.pi * density * frequency)
                + 4 * Double.pi * Double.pi * density * stiffness * 4.5e-3 * frequency * frequency / (tension * tension)
                + 2.03e-4
            let found = losses.loss(
                at: Frequency.hertz(frequency),
                tension: Force.newtons(tension),
                density: Density.Linear.amount(density),
                stiffness: Rigidity.Flexural.amount(stiffness)
            ).underlying
            #expect(abs(found / wanted - 1) < 1e-12)
            let decay = losses.decay(
                at: Frequency.hertz(frequency),
                tension: Force.newtons(tension),
                density: Density.Linear.amount(density),
                stiffness: Rigidity.Flexural.amount(stiffness)
            ).underlying
            #expect(abs(decay / (Double.pi * frequency * wanted) - 1) < 1e-12)
        }
    }

    @Test func `No loss is no loss: every partial keeps its energy`() {
        let string = `Acoustics Tests`.string(losses: .none)
        for n in [1.0, 10, 100] {
            #expect(string.decay(at: Wavenumber.amount(Self.partial(n, of: string).wavenumber)) == .zero)
        }
    }
}

extension `Acoustics Tests`.Losses {
    /// The grid carries a + b β² + c β⁴ and its memory; the law grows as √f in air, as f in heat and as f³ in bending.
    /// Without the memory the match held only within −40 % and +30 %; with it, within −3 % and +8 % for steel, and
    /// −16 % and +10 % for a very lossy string, on every partial that rings for 50 ms or longer.
    @Test func `The grid's decay follows the physical law within −20 % and +15 % on every partial that rings`() {
        for losses in [Self.steel, .steel(diameter: 0.001, in: nil), .init(diameter: 0.001, bending: 0.05)] {
            let string = `Acoustics Tests`.string(losses: losses)
            var worst = (low: 1.0, high: 1.0)
            var n = 1.0
            while true {
                let partial = Self.partial(n, of: string)
                guard partial.frequency <= 16_000 else { break }
                let wanted = losses.decay(
                    at: Frequency.hertz(partial.frequency),
                    tension: string.tension,
                    density: string.density,
                    stiffness: string.stiffness
                ).underlying
                if 3 * Foundation.log(10.0) / wanted >= 0.05 {
                    let ratio = string.decay(at: Wavenumber.amount(partial.wavenumber)).underlying / wanted
                    worst = (min(worst.low, ratio), max(worst.high, ratio))
                }
                n += 1
            }
            #expect(worst.low > 0.8, "lowest \(worst.low)")
            #expect(worst.high < 1.15, "highest \(worst.high)")
        }
    }

    /// Rings one partial alone and reads its decay from how its own amplitude falls: the string's shape projected on
    /// the partial, with its speed, as √(q² + (q′/ω)²).
    ///
    /// WHY: not from the energy, which also holds the string's memory; its slowest part relaxes on its own and, late
    /// on, holds more energy than a high partial does.
    static func rung(_ n: Double, losses: Acoustics.String.Losses, for time: Double) -> (found: Double, wanted: Double) {
        var string = `Acoustics Tests`.string(losses: losses)
        let partial = partial(n, of: string)
        string.displace { along in
            .init(up: `Acoustics Tests`.metres(0.0001 * Foundation.sin(partial.wavenumber * along.underlying)), across: 0)
        }
        let spacing = string.spacing.underlying
        let interval = `Acoustics Tests`.interval
        let angular = 2 * Double.pi * partial.frequency
        func amplitude(_ string: Acoustics.String, _ before: [Double]) -> Double {
            let shape = string.shape.map { $0.up.underlying }
            var now = 0.0
            var speed = 0.0
            for index in shape.indices {
                let mode = Foundation.sin(partial.wavenumber * Double(index) * spacing)
                now += shape[index] * mode
                speed += (shape[index] - before[index]) * mode / interval
            }
            return (now * now + speed * speed / (angular * angular)).squareRoot()
        }
        let settle = Int(0.02 / interval)
        (0..<settle).forEach { _ in string.advance() }
        var before = string.shape.map { $0.up.underlying }
        string.advance()
        let start = amplitude(string, before)
        let steps = Int(time / interval)
        (0..<steps).forEach { _ in
            before = string.shape.map { $0.up.underlying }
            string.advance()
        }
        let found = Foundation.log(start / amplitude(string, before)) / (Double(steps) * interval)
        return (found, string.decay(at: Wavenumber.amount(partial.wavenumber)).underlying)
    }

    @Test func `A partial rung alone dies at the rate the grid's decay gives it, low and high`() {
        let lossy = Acoustics.String.Losses(diameter: 0.001, bending: 0.05, steady: 0.002)
        for n in [1.0, 6, 30] {
            let rung = Self.rung(n, losses: lossy, for: 0.1)
            #expect(abs(rung.found / rung.wanted - 1) < 0.03, "partial \(n): \(rung.found) against \(rung.wanted)")
        }
    }

    @Test func `With physical losses, friction and a damping fingertip the energy only falls`() {
        var string = `Acoustics Tests`.string(
            losses: .init(diameter: 0.001, bending: 0.5, steady: 0.002),
            board: `Acoustics Tests`.board(friction: 0.3, damping: 20)
        )
        string.fingers = [
            .init(
                place: 0.30,
                width: 0.014,
                radius: 0.007,
                centre: .init(up: 0.0035, across: 0.0005),
                contact: `Acoustics Tests`.flesh,
                friction: 0.6,
                damping: 30
            )
        ]
        string.displace(`Acoustics Tests`.pulled(.init(up: 0.002, across: 0.006), at: 0.86))
        var last = string.energy.underlying
        let start = last
        var rise = 0.0
        (0..<30_000).forEach { _ in
            string.advance()
            let energy = string.energy.underlying
            rise = max(rise, energy - last)
            last = energy
        }
        #expect(rise < 1e-6 * start)
        #expect(last < 0.9 * start)
    }
}

extension `Acoustics Tests`.Losses {
    /// swift-molecules/swift-acoustics#1: a lute string set to ring 5 s at its pitch and 6 s at 2.5 kHz went NaN,
    /// because the fitted decay gave a negative viscosity, which feeds the grid's highest partials.
    @Test func `A decay that falls with frequency is carried without any negative loss, and the string stays bounded`() {
        let length = 0.6
        let tension = 29.4
        let density = tension / (4 * length * length * 98.0 * 98.0)
        let stiffness = 6e9 * Double.pi * Foundation.pow((4 * density / (Double.pi * 1_320)).squareRoot(), 4) / 64
        let interval = 1 / 96_000.0
        let damping = Acoustics.String.Damping(
            matching: { frequency in
                let low = 3 * Foundation.log(10.0) / 5
                let high = 3 * Foundation.log(10.0) / 6
                return low + (high - low) * (frequency - 98) / (2_500 - 98)
            },
            length: length,
            speed: tension / density,
            bending: stiffness / density,
            top: 16_000
        )
        #expect(damping.steady >= .zero)
        #expect(damping.rising >= .zero)
        #expect(damping.steep >= 0)
        var string = Acoustics.String(
            length: `Acoustics Tests`.metres(length),
            tension: Force.newtons(tension),
            density: Density.Linear.amount(density),
            stiffness: Rigidity.Flexural.amount(stiffness),
            damping: damping,
            board: nil,
            every: Time.Duration.seconds(interval)
        )
        string.displace { along in
            let along = along.underlying
            let share = along < 0.5 ? along / 0.5 : (length - along) / (length - 0.5)
            return .init(up: `Acoustics Tests`.metres(0.002 * share), across: `Acoustics Tests`.metres(0.001 * share))
        }
        let start = string.energy.underlying
        var most = start
        (0..<96_000).forEach { _ in
            string.advance()
            most = max(most, string.energy.underlying)
        }
        #expect(string.energy.underlying.isFinite)
        #expect(most <= start * (1 + 1e-9))
        #expect(string.energy.underlying < start)
    }
}

extension `Acoustics Tests` {
    @Suite struct Fingers {}
}

extension `Acoustics Tests`.Fingers {
    /// The push a fingertip pressing 4 mm into the resting string gives each point, nut to bridge.
    static func pushes(at place: Double, width: Double) -> [Double] {
        var string = `Acoustics Tests`.string(losses: .none)
        string.fingers = [
            .init(
                place: `Acoustics Tests`.metres(place),
                width: `Acoustics Tests`.metres(width),
                radius: 0.007,
                centre: .init(up: 0.003),
                contact: `Acoustics Tests`.flesh
            )
        ]
        let spans = string.fingers.map(string.span)
        return (0...string.count).map { index in
            guard index > 0, index < string.count else { return 0 }
            return abs(string.slope(index, 0, 0, spans).up)
        }
    }

    @Test func `A fingertip narrower than the grid hands its push smoothly from one point to the next as it slides`() {
        let spacing = `Acoustics Tests`.string(losses: .none).spacing.underlying
        let point = Int((0.30 / spacing).rounded())
        var shares: [Double] = []
        for quarter in 0...4 {
            let pushes = Self.pushes(at: (Double(point) + Double(quarter) / 4) * spacing, width: spacing / 2)
            let total = pushes.reduce(0, +)
            #expect(total > 0)
            #expect(pushes.indices.allSatisfy { pushes[$0] == 0 || $0 == point || $0 == point + 1 })
            shares.append(pushes[point + 1] / total)
        }
        #expect(shares[0] < 1e-12)
        #expect(shares[4] > 1 - 1e-12)
        for index in shares.indices.dropFirst() {
            #expect(shares[index] - shares[index - 1] > 0.1, "\(shares)")
            #expect(shares[index] - shares[index - 1] < 0.5, "\(shares)")
        }
    }
}
