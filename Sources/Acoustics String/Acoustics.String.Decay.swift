internal import Numeric

extension Acoustics.String {
    /// How a string's own ringing dies: a rate every partial shares and one that grows with how sharply it bends.
    public struct Decay: Hashable, Sendable {
        /// Amplitude decay shared by all partials, per second.
        public var steady: Double
        /// Extra decay per squared wavenumber, in m²/s.
        public var rising: Double

        public init(steady: Double = 0, rising: Double = 0) {
            self.steady = steady
            self.rising = rising
        }
    }
}

extension Acoustics.String.Decay {
    public static let none = Self()

    /// The decay under which two frequencies each fall 60 dB in the times given.
    public init(
        low: (frequency: Double, time: Double),
        high: (frequency: Double, time: Double),
        tension: Double,
        density: Double,
        stiffness: Double
    ) {
        let speed = tension / density
        let bending = stiffness / density
        func wavenumber(_ frequency: Double) -> Double {
            let angular = 2 * Double.pi * frequency
            guard bending > 0 else { return angular * angular / speed }
            return (-speed + (speed * speed + 4 * bending * angular * angular).squareRoot())
                / (2 * bending)
        }
        let near = wavenumber(low.frequency)
        let far = wavenumber(high.frequency)
        let scale = 3 * Double.math.log(10) / (far - near)
        self.init(
            steady: scale * (far / low.time - near / high.time),
            rising: scale * (1 / high.time - 1 / low.time)
        )
    }
}
