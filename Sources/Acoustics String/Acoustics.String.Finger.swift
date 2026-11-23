extension Acoustics.String {
    /// A round fingertip against the string: it stops a note, damps one, or pulls the string until it slips off.
    public struct Finger: Hashable, Sendable {
        /// Where along the string the tip is, from the nut, in metres.
        public var place: Double
        /// How much of the string the tip covers, in metres.
        public var width: Double
        /// The tip's radius in the plane across the string.
        public var radius: Double
        /// Where the tip's centre is, across the string.
        public var centre: Offset
        /// How fast the centre moves, in m/s.
        public var speed: Offset
        /// The flesh's push for the whole tip.
        public var contact: Contact
        /// Sliding friction of the skin.
        public var friction: Double
        /// The sliding speed under which the skin holds, in m/s.
        public var creep: Double
        /// Loss in the flesh while pressed, in s/m.
        public var damping: Double

        public init(
            place: Double,
            width: Double,
            radius: Double,
            centre: Offset,
            speed: Offset = .zero,
            contact: Contact,
            friction: Double = 0,
            creep: Double = 0.001,
            damping: Double = 0
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
