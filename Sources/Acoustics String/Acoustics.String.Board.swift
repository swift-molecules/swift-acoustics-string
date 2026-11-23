extension Acoustics.String {
    /// A fingerboard under the string, from the nut to `reach`.
    public struct Board: Sendable {
        /// How far the board reaches from the nut, in metres.
        public var reach: Double
        /// The board's push per metre of string.
        public var contact: Contact
        /// Sliding friction against the board.
        public var friction: Double
        /// The sliding speed under which friction holds, in m/s.
        public var creep: Double
        /// Loss while pressed, in s/m.
        public var damping: Double
        @usableFromInline var clearance: @Sendable (Double) -> Double

        /// - Parameter clearance: the gap between the resting string and the board, by distance from the nut.
        public init(
            reach: Double,
            contact: Contact,
            friction: Double = 0,
            creep: Double = 0.001,
            damping: Double = 0,
            clearance: @escaping @Sendable (Double) -> Double
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
