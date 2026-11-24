internal import Numeric

extension Acoustics.String {
    /// How the string twists: a wave of turning that runs along it, apart from its moving across.
    ///
    /// A bow grips the string at its surface, not at its centre, so the force that drags the string across also turns
    /// it, and the hair feels the surface move at v + r ω: the string's speed across plus its radius times how fast it
    /// turns (Bavu, Smith and Wolfe 2005, "Torsional waves in a bowed string", Acta Acustica united with Acustica 91,
    /// 241–246).
    ///
    /// The turning is held here as the surface's own displacement, r θ. Measured that way the twisting wave is a
    /// second string: its `inertia` is the rotary inertia per length over r², its pull `inertia` × `speed`², and its
    /// impedance at the surface `inertia` × `speed`.
    public struct Twist: Hashable, Sendable {
        /// How fast a twist runs along the string: √(G J / I), torsional rigidity over rotary inertia per length.
        public var speed: Velocity.Value<Double>
        /// The rotary inertia per length over the radius squared: the mass per length the surface's turning carries.
        public var inertia: Density.Linear.Value<Double>
        /// The share of a twisting mode's energy lost each cycle, 1/Q, the same at every mode.
        public var loss: Loss.Value<Double>

        public init(speed: Velocity.Value<Double>, inertia: Density.Linear.Value<Double>, loss: Loss.Value<Double>) {
            precondition(speed > .zero && inertia > .zero && loss >= .zero, "A twist needs a speed and an inertia.")
            self.speed = speed
            self.inertia = inertia
            self.loss = loss
        }
    }
}

extension Acoustics.String.Twist {
    /// The twisting of a solid round string of mass per length `density`, whose twist runs at `speed`.
    ///
    /// WHY: a round section turns with rotary inertia ρ J per length, J = π r⁴ / 2, which over r² is ρ π r² / 2, half
    /// the mass per length (Saint-Venant's torsion of a circular bar). Its twist runs at √(G / ρ).
    public static func solid(
        density: Density.Linear.Value<Double>,
        speed: Velocity.Value<Double>,
        loss: Loss.Value<Double>
    ) -> Self {
        Self(speed: speed, inertia: Density.Linear.amount(density.underlying / 2), loss: loss)
    }

    /// The twisting wave's impedance at the surface, in N·s/m: how much force across the surface it takes to turn it
    /// at a metre a second. No atom holds mechanical impedance here, so it is a scalar.
    public var impedance: Double { inertia.underlying * speed.underlying }
}

extension Acoustics.String {
    /// The twisting wave as the grid steps it: a line of its own, with its own spacing, rigid at the nut and bridge.
    @usableFromInline
    struct Twisting: Sendable {
        @usableFromInline var line: Line
        @usableFromInline let count: Int
        @usableFromInline let spacing: Double
        @usableFromInline let wave: Double
        @usableFromInline let rise: Double
        @usableFromInline let steady: Double
        /// The loss that grows with the wavenumber squared, in m²/s.
        @usableFromInline let rising: Double
        /// A point's mass, with the steady loss's share, as the bow's force moves it.
        @usableFromInline let mass: Double
        /// The pull along the twisting line, inertia × speed².
        @usableFromInline let pull: Double
        @usableFromInline let inertia: Double

        /// WHY: a twist runs several times faster than a wave across, so on the string's grid it would need steps
        /// several times shorter. It gets a grid of its own, as coarse as its speed allows, which costs a few dozen
        /// points at most.
        ///
        /// A loss the same share of every mode's energy decays mode n at η ω_n / 2. The grid's losses are a + b β²;
        /// they are matched to that at the first two modes, and lose more above, where the bow hardly drives the
        /// twist.
        init(_ twist: Twist, length: Double, interval: Double) {
            let speed = twist.speed.underlying
            let loss = twist.loss.underlying
            let first = Double.pi / length
            let second = 2 * first
            let rising = loss * speed / (2 * (first + second))
            self.rising = rising
            let steadily = Swift.max(0, loss * speed * first / 2 - rising * first * first)
            // WHY: von Neumann on the step: h² ≥ c²k² + 4 b k keeps every mode bounded.
            let least = (speed * speed * interval * interval + 4 * rising * interval).squareRoot()
            count = Swift.max(2, Int(length / least))
            spacing = length / Double(count)
            wave = speed * speed * interval * interval / (spacing * spacing)
            rise = 2 * rising * interval / (spacing * spacing)
            steady = steadily * interval
            inertia = twist.inertia.underlying
            pull = inertia * speed * speed
            mass = inertia * spacing * (1 + steady)
            line = Line(count + 1)
        }

        /// Where every point of the twisting line would be one step on, with nothing touching it.
        @usableFromInline
        mutating func coast() {
            line.coast(wave: wave, stiff: 0, rise: rise, steady: steady, steep: 0)
        }

        /// The point at or before `place` on the twisting line, and the share of the bow it and the next take. The
        /// rigid ends take none.
        @usableFromInline
        func beside(_ place: Double) -> (index: Int, near: Double, far: Double) {
            let along = Swift.min(Swift.max(place / spacing, 0), Double(count))
            let index = Swift.min(Int(along.rounded(.down)), count - 1)
            let far = along - Double(index)
            return (index, index > 0 ? 1 - far : 0, index + 1 < count ? far : 0)
        }

        /// The energy in the twisting.
        ///
        /// WHY the last term: the loss that grows with β² is taken over the last step, so what the step keeps from
        /// falling is the energy less σ₁ / (2k) times the stretch's change over that step; with it the sum only falls.
        @usableFromInline
        func energy(_ interval: Double) -> Double {
            let taut = pull / spacing
            let lagging = inertia * rising / (2 * interval * spacing)
            var total = 0.0
            for index in line.now.indices.dropFirst() {
                let speed = index == line.now.endIndex - 1 ? 0 : (line.now[index] - line.before[index]) / interval
                let stretch = line.now[index] - line.now[index - 1]
                let stretched = line.before[index] - line.before[index - 1]
                total += inertia * spacing * speed * speed / 2
                total += taut * stretch * stretched / 2
                total -= lagging * (stretch - stretched) * (stretch - stretched)
            }
            return total
        }
    }
}
