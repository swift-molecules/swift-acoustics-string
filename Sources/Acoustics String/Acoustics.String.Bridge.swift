extension Acoustics.String {
    /// Strings pulling one bridge on a body: each step their pull drives the body, and the body's motion at the
    /// bridge carries the strings' ends.
    ///
    /// With no loss set anywhere the strings and the body keep their energy together.
    public struct Bridge: Sendable {
        /// The strings, low to high. A player sets fingers on them between steps.
        public var strings: [Acoustics.String]
        /// The body, driven up and across at the bridge by its first two drives.
        public private(set) var body: Acoustics.Resonator

        public init(strings: [Acoustics.String], body: Acoustics.Resonator) {
            self.strings = strings
            self.body = body
        }
    }
}

extension Acoustics.String.Bridge {
    /// What each direction around the body is given now.
    public var heard: [Double] { body.heard }

    /// The energy in the strings and the body.
    public var energy: Energy.Value<Double> { strings.reduce(body.energy) { $0 + $1.energy } }

    /// Steps the strings and the body once: the strings pull the bridge, the bridge carries the strings' ends.
    public mutating func advance() {
        var up = 0.0
        var across = 0.0
        for string in strings {
            let pull = string.pull
            up += pull.up.underlying
            across += pull.across.underlying
        }
        body.advance(driven: [Force.newtons(up), Force.newtons(across)])
        let end = Acoustics.String.Offset(up: body.felt[0], across: body.felt[1])
        for index in strings.indices { strings[index].advance(end: end) }
    }
}
