import Acoustics_String
import Foundation
import Testing
import Wavenumber

enum `Acoustics Tests` {}

extension `Acoustics Tests` {
    @Suite struct String {}

    static let interval = 1 / 96_000.0

    fileprivate static func string(
        decay: Acoustics.String.Decay = .none,
        board: Acoustics.String.Board? = nil
    ) -> Acoustics.String {
        Acoustics.String(
            length: 1.06,
            tension: 290,
            density: 0.0062,
            stiffness: 0.004,
            decay: decay,
            board: board,
            every: Time.Duration.seconds(interval)
        )
    }

    static func string(
        losses: Acoustics.String.Losses,
        board: Acoustics.String.Board? = nil
    ) -> Acoustics.String {
        Acoustics.String(
            length: 1.06,
            tension: 290,
            density: 0.0062,
            stiffness: 0.004,
            losses: losses,
            board: board,
            every: Time.Duration.seconds(interval)
        )
    }

    static func metres(_ scalar: Double) -> Length<Space.Physical, Double> { Space.Physical.metres(scalar) }

    /// The flesh of a fingertip: 12.2 N at 2⁻¹⁰ m (about a millimetre), Hertzian.
    static let flesh = Contact(pushing: 12.207_031_25, at: 0x1p-10, exponent: 1.5)

    static func board(friction: Double = 0, damping: Double = 0) -> Acoustics.String.Board {
        Acoustics.String.Board(
            reach: 0.86,
            contact: .init(pushing: 122_070.3125, at: 0x1p-10, exponent: 1.5),
            friction: Friction.amount(friction),
            damping: Slowness.amount(damping)
        ) { Space.Physical.metres(0.0008 + 0.006 * $0.underlying / 0.86) }
    }

    static func pulled(
        _ depth: Acoustics.String.Offset<Measure<1, Space.Physical>>,
        at place: Double
    ) -> (Length<Space.Physical, Double>) ->
        Acoustics.String.Offset<Measure<1, Space.Physical>>
    {
        { along in
            let along = along.underlying
            let share = along < place ? along / place : (1.06 - along) / (1.06 - place)
            return .init(up: depth.up * share, across: depth.across * share)
        }
    }

    static func drift(
        _ string: inout Acoustics.String,
        steps: Int
    ) -> (
        least: Double, most: Double, start: Double
    ) {
        let start = string.energy.underlying
        var least = start
        var most = start
        (0..<steps).forEach { _ in
            string.advance()
            let energy = string.energy.underlying
            least = min(least, energy)
            most = max(most, energy)
        }
        return (least, most, start)
    }
}

extension `Acoustics Tests`.String {
    @Test
    func
        `The bare string's partials are the stiff string's own: a tenth of a cent low down, five cents at 2 kHz`()
    {
        var worst = 0.0
        for partial in [1.0, 2, 3, 5, 8, 13, 21] {
            var string = `Acoustics Tests`.string()
            string.displace { .init(up: `Acoustics Tests`.metres(0.001 * sin(partial * Double.pi * $0.underlying / 1.06))) }
            let middle = string.count / (2 * Int(partial)) + 1
            string.advance()
            let before = string.shape[middle].up.underlying
            string.advance()
            let now = string.shape[middle].up.underlying
            string.advance()
            let after = string.shape[middle].up.underlying
            let heard = acos((after + before) / (2 * now)) / (2 * Double.pi * `Acoustics Tests`.interval)
            let wavenumber = partial * Double.pi / 1.06
            let wanted =
                (290 / 0.0062 * wavenumber * wavenumber + 0.004 / 0.0062 * pow(wavenumber, 4)).squareRoot()
                / (2 * Double.pi)
            worst = max(worst, abs(1_200 * log2(heard / wanted)))
            if partial <= 3 { #expect(abs(1_200 * log2(heard / wanted)) < 0.1) }
        }
        #expect(worst < 5)
    }

    @Test func `Without loss a released string keeps its energy`() {
        var string = `Acoustics Tests`.string()
        string.displace(`Acoustics Tests`.pulled(.init(up: 0.004, across: 0.007), at: 0.86))
        let energy = `Acoustics Tests`.drift(&string, steps: 20_000)
        #expect(energy.start > 0)
        #expect((energy.most - energy.least) / energy.start < 1e-10)
    }

    @Test func `Without loss a string that rattles on the fingerboard keeps its energy`() {
        var string = `Acoustics Tests`.string(board: `Acoustics Tests`.board())
        string.displace(`Acoustics Tests`.pulled(.init(up: 0.009, across: 0.004), at: 0.86))
        var touched = false
        let start = string.energy.underlying
        var worst = 0.0
        (0..<30_000).forEach { _ in
            string.advance()
            worst = max(worst, abs(string.energy.underlying - start))
            if !touched {
                touched = string.shape.indices.contains {
                    string.shape[$0].up.underlying < -(0.0008 + 0.006 * Double($0) * string.spacing.underlying / 0.86)
                        && Double($0) * string.spacing.underlying <= 0.86
                }
            }
        }
        #expect(touched)
        #expect(worst / start < 1e-9)
    }

    @Test func `Without loss a string held down by a still fingertip keeps its energy`() {
        var string = `Acoustics Tests`.string(board: `Acoustics Tests`.board())
        string.fingers = [
            .init(
                place: 0.30,
                width: 0.014,
                radius: 0.007,
                centre: .init(up: 0.0035, across: 0.0005),
                contact: `Acoustics Tests`.flesh
            )
        ]
        string.displace(`Acoustics Tests`.pulled(.init(up: 0.002, across: 0.006), at: 0.86))
        let energy = `Acoustics Tests`.drift(&string, steps: 30_000)
        #expect(string.shape[Int(0.30 / string.spacing.underlying)].up < -0.001)
        #expect((energy.most - energy.least) / energy.start < 1e-9)
    }

    @Test func `With loss, friction and a damping fingertip the energy only falls`() {
        var string = `Acoustics Tests`.string(
            decay: .init(steady: 0.8, rising: 0.0004),
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

    @Test func `Strings and the body they pull at one bridge keep their energy together`() {
        var string = `Acoustics Tests`.string()
        string.displace(`Acoustics Tests`.pulled(.init(up: 0.004, across: 0.007), at: 0.86))
        var other = `Acoustics Tests`.string()
        other.displace(`Acoustics Tests`.pulled(.init(up: -0.002, across: 0.003), at: 0.5))
        var bridge = Acoustics.String.Bridge(
            strings: [string, other],
            body: Acoustics.Resonator(
                [(98.0, 1.0, 0.3), (183.0, -0.8, 0.9), (412.0, 0.5, -0.7), (1_530.0, 0.9, 0.4)].map {
                    .init(frequency: Frequency.hertz($0.0), decay: 0, mass: 0.4, reach: 0, driven: [$0.1, $0.2])
                },
                every: Time.Duration.seconds(`Acoustics Tests`.interval)
            )
        )
        let start = bridge.energy.underlying
        var worst = 0.0
        var moved = 0.0
        (0..<40_000).forEach { _ in
            bridge.advance()
            worst = max(worst, abs(bridge.energy.underlying - start))
            moved = max(moved, abs(bridge.body.felt[0].underlying))
        }
        #expect(moved > 1e-6)
        #expect(worst / start < 1e-9)
    }

    /// Plucks with a fingertip drawn across 20 cm from the bridge, a finger stopping the string at `stop` if given.
    static func plucked(
        stop: Double?,
        width: Double = 0.014,
        lasting time: Double
    ) -> (pulled: Double, kept: Double, heard: Double) {
        let interval = `Acoustics Tests`.interval
        var string = `Acoustics Tests`.string(
            decay: .init(steady: 0.8, rising: 0.0004),
            board: `Acoustics Tests`.board(friction: 0.3, damping: 20)
        )
        let flesh = `Acoustics Tests`.flesh
        let pressed = stop.map { -(0.0008 + 0.006 * $0 / 0.86) + 0.007 - 0.0008 } ?? 0
        var fingers: [Acoustics.String.Finger] = []
        if let stop {
            fingers.append(
                .init(
                    place: `Acoustics Tests`.metres(stop),
                    width: `Acoustics Tests`.metres(width),
                    radius: 0.007,
                    centre: .init(up: 0.008),
                    contact: flesh,
                    friction: 0.8,
                    damping: 40
                )
            )
        }
        fingers.append(
            .init(
                place: 0.86,
                width: 0.014,
                radius: 0.007,
                centre: .init(up: 0.004, across: -0.0085),
                contact: flesh,
                friction: 0.8,
                damping: 10
            )
        )
        string.fingers = fingers
        let plucking = fingers.endIndex - 1
        let place = Int(0.86 / string.spacing.underlying)
        var pulled = 0.0
        var kept = 0.0
        var trace: [Double] = []
        (0..<Int(time / interval)).forEach { step in
            let now = Double(step) * interval
            if stop != nil {
                let down = min(now / 0.03, 1)
                string.fingers[0].centre.up = `Acoustics Tests`.metres(0.008 + (pressed - 0.008) * down)
                string.fingers[0].speed.up = Velocity.amount(down < 1 ? (pressed - 0.008) / 0.03 : 0)
            }
            if now > 0.04, now < 0.08 {
                string.fingers[plucking].speed.across = 0.3
                string.fingers[plucking].centre.across += `Acoustics Tests`.metres(0.3 * interval)
            } else if now >= 0.08 {
                string.fingers[plucking].speed.across = 0
                string.fingers[plucking].centre.up = 0.05
            }
            string.advance()
            let here = string.shape[place].across.underlying
            if now < 0.08 { pulled = max(pulled, abs(here)) }
            if now >= 0.08 { kept = max(kept, abs(here)) }
            if now > 0.12 { trace.append(here) }
        }
        var crossings: [Double] = []
        for index in trace.indices.dropFirst() where trace[index - 1] < 0 && trace[index] >= 0 {
            crossings.append(Double(index) - trace[index] / (trace[index] - trace[index - 1]))
        }
        let heard =
            crossings.count > 1
            ? Double(crossings.dropLast().count) / ((crossings[crossings.endIndex - 1] - crossings[0]) * interval) : 0
        return (pulled, kept, heard)
    }

    @Test func `A fingertip drawn across pulls the string along, then the string slips off and rings`() {
        let pluck = Self.plucked(stop: nil, lasting: 0.3)
        #expect(pluck.pulled > 0.002)
        #expect(pluck.pulled < 0.008)
        #expect(pluck.kept > 0.0005)
        #expect(abs(1_200 * log2(pluck.heard / 102.02)) < 15)
    }

    @Test func `A note stopped by a fingertip sounds a little sharp of its bare length, by about half the tip`() {
        let pluck = Self.plucked(stop: 0.30, lasting: 0.45)
        let cents = 1_200 * log2(pluck.heard / (102.02 * 1.06 / 0.76))
        #expect(cents > 0)
        #expect(cents < 35)
    }
}

extension `Acoustics Tests`.String {
    @Test func `A decay set by two ring times makes the lowest partial fall 60 dB in its time`() {
        let bare = `Acoustics Tests`.string()
        let time = 0.3
        var string = `Acoustics Tests`.string(
            decay: .init(
                low: (bare.frequency, Time.Duration.seconds(time)),
                high: (2_000, 0.1),
                tension: bare.tension,
                density: bare.density,
                stiffness: bare.stiffness
            )
        )
        string.displace { along in
            .init(up: `Acoustics Tests`.metres(0.001 * Foundation.sin(Double.pi * along.underlying / 1.06)), across: 0)
        }
        let start = string.energy
        (0..<Int(time / `Acoustics Tests`.interval)).forEach { _ in string.advance() }
        let fall = 10 * Foundation.log10(start / string.energy)
        #expect(abs(fall - 60) < 1)
    }
}

extension `Acoustics Tests`.String {
    @Test func `A stiff string's partial near 2.3 kHz sounds within a cent of its law, not five flat`() {
        let string = `Acoustics Tests`.string()
        let along = 2_200.0 / string.frequency.underlying
        let mode = along.rounded()
        let wavenumber = mode * Double.pi / string.length.underlying
        let tension = string.tension.underlying
        let density = string.density.underlying
        let stiffness = string.stiffness.underlying
        let wanted =
            (tension / density * wavenumber * wavenumber
            + stiffness / density * wavenumber * wavenumber * wavenumber * wavenumber)
            .squareRoot() / (2 * Double.pi)
        var ringing = string
        ringing.displace { place in
            .init(up: `Acoustics Tests`.metres(0.0001 * Foundation.sin(wavenumber * place.underlying)), across: 0)
        }
        let point = Int(0.37 / ringing.spacing.underlying)
        var last = ringing.shape[point].up.underlying
        var crossings: [Double] = []
        (1...Int(0.05 / `Acoustics Tests`.interval)).forEach { step in
            ringing.advance()
            let now = ringing.shape[point].up.underlying
            if last < 0, now >= 0 {
                crossings.append((Double(step) - now / (now - last)) * `Acoustics Tests`.interval)
            }
            last = now
        }
        let periods = Double(crossings.dropFirst().count)
        let heard = periods / ((crossings.last ?? 0) - (crossings.first ?? 0))
        #expect(abs(1_200 * Foundation.log2(heard / wanted)) < 1)
    }
}

extension `Acoustics Tests`.String {
    @Test func `The string's laws balance their dimensions`() {
        typealias D = Quantity.Dimension
        let length = D.of(Measure<1, Space.Physical>.self)
        let speed = D.of(Velocity.self)
        // c² = T / μ
        #expect(D.of(Force.self) / D.of(Density.Linear.self) == speed * speed)
        // ω² = (T / μ) β² + (EI / μ) β⁴, with β a wavenumber
        let wavenumber = D.of(Wavenumber.self)
        let angular = D.of(Frequency.Angular.self)
        #expect(speed * speed * wavenumber * wavenumber == angular * angular)
        #expect(D.of(Rigidity.Flexural.self) / D.of(Density.Linear.self) * wavenumber * wavenumber * wavenumber * wavenumber == angular * angular)
        // the rising decay: a viscosity times a squared wavenumber is a decay rate
        #expect(D.of(Viscosity.Kinematic.self) * wavenumber * wavenumber == D.of(Decay::Decay.self))
        // a point of the grid: linear density times spacing is a mass
        #expect(D.of(Density.Linear.self) * length == D.of(Mass.self))
    }
}
