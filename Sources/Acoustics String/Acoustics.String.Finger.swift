extension Acoustics.String {
    /// A round fingertip against the string: it stops a note, damps one, or pulls the string until it slips off.
    public struct Finger: Hashable, Sendable {
        /// Where along the string the tip is, from the nut.
        public var place: Length<Space.Physical, Double>
        /// How much of the string the tip covers.
        public var width: Length<Space.Physical, Double>
        /// The tip's radius in the plane across the string.
        public var radius: Length<Space.Physical, Double>
        /// Where the tip's centre is, across the string.
        public var centre: Offset<Measure<1, Space.Physical>>
        /// How fast the centre moves.
        public var speed: Offset<Velocity>
        /// The flesh's push for the whole tip.
        public var contact: Contact
        /// Sliding friction of the skin.
        public var friction: Friction.Value<Double>
        /// The sliding speed under which the skin holds.
        public var creep: Velocity.Value<Double>
        /// Loss while pressed, as Hunt and Crossley's: the push grows by `damping` × the speed into the flesh.
        public var damping: Slowness.Value<Double>

        public init(
            place: Length<Space.Physical, Double>,
            width: Length<Space.Physical, Double>,
            radius: Length<Space.Physical, Double>,
            centre: Offset<Measure<1, Space.Physical>>,
            speed: Offset<Velocity> = .zero,
            contact: Contact,
            friction: Friction.Value<Double> = .zero,
            creep: Velocity.Value<Double> = Velocity.amount(0.001),
            damping: Slowness.Value<Double> = .zero
        ) {
            self.place = place
            self.width = width
            self.radius = radius
            self.centre = centre
            self.speed = speed
            self.contact = contact
            self.friction = friction
            self.creep = creep
            self.damping = damping
        }
    }
}
