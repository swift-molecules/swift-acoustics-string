extension Acoustics.String {
    /// A place or a force in the plane across the string: `up` is away from the fingerboard, `across` along it.
    public struct Offset: Hashable, Sendable {
        public var up: Double
        public var across: Double

        public init(up: Double = 0, across: Double = 0) {
            self.up = up
            self.across = across
        }
    }
}

extension Acoustics.String.Offset {
    public static let zero = Self()
}
