internal import Numeric

extension Acoustics.String {
    /// What a string loses as it rings, from physics: the air it drags along, and friction inside its own material.
    ///
    /// Each partial loses a share of its energy every cycle, its loss factor 1/Q, and the shares add. The laws are
    /// Valette and Cuesta's (1993), as Issanchou, Bilbao, Le Carrou, Touzé and Doaré (2017, eq. 12) state them; the
    /// air's is also Paté, Le Carrou and Fabre's (2014, eqs. 9–10):
    /// - **Air.** A cylinder moving in air is held back by its viscosity and by the air it carries with it (Stokes):
    ///   1/Q = R / (2π μ f), with R = 2π η + 2π d √(π η ρ f), where η and ρ are the air's viscosity and density and
    ///   d the string's outer diameter.
    /// - **Bending.** The material's Young's modulus is complex, E (1 + i δ). Only the share of a partial's energy
    ///   held in bending feels it: 1/Q = 4π² μ E I δ f² / T².
    /// - **Steady.** A loss factor every partial shares: in metal, heat flowing between the stretched and compressed
    ///   sides (thermoelastic loss).
    public struct Losses: Hashable, Sendable {
        /// The outer diameter, which the air flows round.
        public var diameter: Length<Space.Physical, Double>
        /// The air around the string; nil for a string in vacuum.
        public var air: Acoustics.Air?
        /// The loss factor of the material in bending: the imaginary part of its Young's modulus over the real part.
        public var bending: Loss.Value<Double>
        /// The loss factor every partial shares.
        public var steady: Loss.Value<Double>

        public init(
            diameter: Length<Space.Physical, Double>,
            air: Acoustics.Air? = .room,
            bending: Loss.Value<Double>,
            steady: Loss.Value<Double> = .zero
        ) {
            self.diameter = diameter
            self.air = air
            self.bending = bending
            self.steady = steady
        }
    }
}

extension Acoustics.String.Losses {
    /// No loss at all: the string keeps its energy.
    public static let none = Self(diameter: .zero, air: nil, bending: .zero)

    /// The loss factor 1/Q of a partial at `frequency` on a string of this tension, mass per length and bending
    /// stiffness.
    public func loss(
        at frequency: Frequency.Value<Double>,
        tension: Force.Value<Double>,
        density: Density.Linear.Value<Double>,
        stiffness: Rigidity.Flexural.Value<Double>
    ) -> Loss.Value<Double> {
        let f = frequency.underlying
        guard f > 0 else { return .zero }
        let mu = density.underlying
        let pull = tension.underlying
        var total = steady.underlying
        if let air {
            let viscosity = air.viscosity.underlying
            let drag =
                2 * Double.pi * viscosity
                + 2 * Double.pi * diameter.underlying * (Double.pi * viscosity * air.density.underlying * f).squareRoot()
            total += drag / (2 * Double.pi * mu * f)
        }
        total += 4 * Double.pi * Double.pi * mu * stiffness.underlying * bending.underlying * f * f / (pull * pull)
        return Loss.amount(total)
    }

    /// The amplitude decay of a partial at `frequency`: π f / Q.
    public func decay(
        at frequency: Frequency.Value<Double>,
        tension: Force.Value<Double>,
        density: Density.Linear.Value<Double>,
        stiffness: Rigidity.Flexural.Value<Double>
    ) -> Decay::Decay.Value<Double> {
        let loss = loss(at: frequency, tension: tension, density: density, stiffness: stiffness)
        return Decay::Decay.amount(Double.pi * frequency.underlying * loss.underlying)
    }
}

extension Acoustics.String.Losses {
    /// A plain steel string in room air: δ = 4.5 × 10⁻³ in bending and a thermoelastic 1/Q = 2.03 × 10⁻⁴, as
    /// Issanchou, Bilbao, Le Carrou, Touzé and Doaré (2017, §4.2) select for a steel guitar string.
    ///
    /// Wound strings lose more, by friction between their windings (Paté et al. 2014, p. 3047); no value for that is
    /// in print, so it is left out.
    public static func steel(diameter: Length<Space.Physical, Double>, in air: Acoustics.Air? = .room) -> Self {
        Self(diameter: diameter, air: air, bending: Loss.amount(4.5e-3), steady: Loss.amount(2.03e-4))
    }

    /// A plain nylon string in room air: η_B = 2.0 × 10⁻² in bending and a steady η_F = 4.0 × 10⁻⁴, as Woodhouse
    /// (2004, Table I) fits to the plain nylon trebles of a classical guitar.
    ///
    /// His eq. (8) is η = [T (η_F + η_A / ω) + B η_B (nπ/L)²] / [T + B (nπ/L)²]; its bending part, B η_B (nπ/L)² / T,
    /// is this law's, so η_B is δ. η_F is the "internal friction" of the monofilament (p. 956), so it is the steady
    /// loss; η_A / ω is his fitted stand-in for the air, which the air's own law replaces here. Table I gives η_B as
    /// 2.4, 2.0 and 2.0 × 10⁻² on the three plain strings, "of the order of 2 %" on all six (p. 956), and η_F as 40, 40
    /// and 14 × 10⁻⁵; the second string's pair is taken.
    public static func nylon(diameter: Length<Space.Physical, Double>, in air: Acoustics.Air? = .room) -> Self {
        Self(diameter: diameter, air: air, bending: Loss.amount(2.0e-2), steady: Loss.amount(4.0e-4))
    }

    /// A plain gut string in room air, losing what plain nylon loses.
    ///
    /// No loss factor measured on gut is in open print: Lynch-Aird and Woodhouse could not test gut in their dynamic
    /// analyser (2018, p. 3) and found gut's pluck loss factors "largely useless" (2023, §3.1.4). What is in print is
    /// Woodhouse's finding that a lute's plain gut strings behave, "in terms of damping, … very similar to the nylon
    /// strings" (Euphonics, §7.2, 2022), so gut takes nylon's values. Woodhouse and Lynch-Aird (2019, Table 1) is where
    /// a value for gut itself is to be read.
    public static func gut(diameter: Length<Space.Physical, Double>, in air: Acoustics.Air? = .room) -> Self {
        nylon(diameter: diameter, in: air)
    }
}
