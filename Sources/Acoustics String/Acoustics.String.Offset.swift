extension Acoustics.String {
    /// An amount in the plane across the string, of one kind (a place, a speed, a force): `up` is away from the
    /// fingerboard, `across` along it.
    public struct Offset<Kind: Quantity.Kind>: Hashable, Sendable {
        public var up: Tagged<Kind, Double>
        public var across: Tagged<Kind, Double>

        @inlinable
        public init(up: Tagged<Kind, Double> = .zero, across: Tagged<Kind, Double> = .zero) {
            self.up = up
            self.across = across
        }
    }
}

extension Acoustics.String.Offset {
    @inlinable
    public static var zero: Self { Self() }
}
