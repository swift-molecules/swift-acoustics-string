extension Acoustics.String {
    /// A fingerboard under the string, from the nut to `reach`.
    public struct Board: Sendable {
        /// How far the board reaches from the nut.
        public var reach: Length<Space.Physical, Double>
        /// The board's push on one metre of string.
        public var contact: Contact
        /// Sliding friction against the board.
        public var friction: Friction.Value<Double>
        /// The sliding speed under which friction holds.
        public var creep: Velocity.Value<Double>
        /// Loss while pressed, in s/m: the push grows by `damping` × the speed into the board. No atom holds this
        /// kind yet, so it is a scalar.
        public var damping: Double
        @usableFromInline var clearance: @Sendable (Length<Space.Physical, Double>) -> Length<Space.Physical, Double>

        /// - Parameter clearance: the gap between the resting string and the board, by distance from the nut.
        public init(
            reach: Length<Space.Physical, Double>,
            contact: Contact,
            friction: Friction.Value<Double> = .zero,
            creep: Velocity.Value<Double> = Velocity.amount(0.001),
            damping: Double = 0,
            clearance: @escaping @Sendable (Length<Space.Physical, Double>) -> Length<Space.Physical, Double>
        ) {
            self.reach = reach
            self.contact = contact
            self.friction = friction
            self.creep = creep
            self.damping = damping
            self.clearance = clearance
        }
    }
}
