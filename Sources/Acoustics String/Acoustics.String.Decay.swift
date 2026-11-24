internal import Numeric

extension Acoustics.String {
    /// How a string's own ringing dies: a rate every partial shares and one that grows with how sharply it bends.
    public struct Decay: Hashable, Sendable {
        /// Amplitude decay shared by all partials.
        public var steady: Decay::Decay.Value<Double>
        /// Extra decay per squared wavenumber: the string's own viscosity, which damps a partial by this times its
        /// wavenumber squared.
        public var rising: Viscosity.Kinematic.Value<Double>

        public init(
            steady: Decay::Decay.Value<Double> = .zero,
            rising: Viscosity.Kinematic.Value<Double> = .zero
        ) {
            self.steady = steady
            self.rising = rising
        }
    }
}

extension Acoustics.String.Decay {
    public static let none = Self()

    /// The decay under which two frequencies each fall 60 dB in the times given.
    public init(
        low: (frequency: Frequency.Value<Double>, time: Time.Duration.Value<Double>),
        high: (frequency: Frequency.Value<Double>, time: Time.Duration.Value<Double>),
        tension: Force.Value<Double>,
        density: Density.Linear.Value<Double>,
        stiffness: Rigidity.Flexural.Value<Double>
    ) {
        let speed = tension.underlying / density.underlying
        let bending = stiffness.underlying / density.underlying
        func wavenumber(_ frequency: Double) -> Double {
            let angular = 2 * Double.pi * frequency
            guard bending > 0 else { return angular * angular / speed }
            return (-speed + (speed * speed + 4 * bending * angular * angular).squareRoot())
                / (2 * bending)
        }
        let near = wavenumber(low.frequency.underlying)
        let far = wavenumber(high.frequency.underlying)
        let scale = 3 * Double.math.log(10) / (far - near)
        self.init(
            steady: Decay::Decay.amount(scale * (far / low.time.underlying - near / high.time.underlying)),
            rising: Viscosity.Kinematic.amount(scale * (1 / high.time.underlying - 1 / low.time.underlying))
        )
    }
}
