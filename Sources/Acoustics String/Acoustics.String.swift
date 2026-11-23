internal import Numeric

extension Acoustics {
    /// A stiff string between a nut and a bridge, free to move in both directions across itself.
    ///
    /// The string is a row of points stepped together. Everything that touches it (a fingerboard, a fingertip) is a
    /// stored energy at each point, so with no loss set the string and what it touches keep their energy exactly.
    public struct String: Sendable {
        public let length: Double
        public let tension: Double
        /// Mass per metre.
        public let density: Double
        /// Bending stiffness, in N·m².
        public let stiffness: Double
        /// The stiffness the grid is stepped with: a little more than `stiffness`, so the grid's own flattening of
        /// high partials is cancelled and they sound where the stiff string's law puts them.
        @usableFromInline let stepped: Double
        public let decay: Decay
        public let interval: Double
        /// The distance between neighbouring points.
        public let spacing: Double
        /// The number of stretches between points; the nut is point 0 and the bridge point `count`.
        public let count: Int
        public let board: Board?
        public var fingers: [Finger] = []
        @usableFromInline var up: Line
        @usableFromInline var across: Line
        @usableFromInline var top: [Double]
        @usableFromInline var low: [Int] = []
        @usableFromInline var high: [Int] = []
        @usableFromInline var share: [Double] = []

        public init(
            length: Double,
            tension: Double,
            density: Double,
            stiffness: Double = 0,
            decay: Decay = .none,
            board: Board? = nil,
            every interval: Double
        ) {
            self.length = length
            self.tension = tension
            self.density = density
            self.stiffness = stiffness
            self.decay = decay
            self.board = board
            self.interval = interval
            let step = interval * interval
            let wave = tension / density * step + 4 * decay.rising * interval
            func points(_ stiff: Double) -> Int {
                let least = ((wave + (wave * wave + 16 * stiff / density * step).squareRoot()) / 2).squareRoot()
                return Swift.max(2, Int(length / least))
            }
            // WHY: The grid flattens a partial of wavenumber β by c²β⁴(h² − c²k²)/12 in ω²; a stiff string sharpens it by
            // κ²β⁴. Stepping with κ² raised by that much cancels the flattening to this order. The spacing is chosen
            // for the raised stiffness, which is never less than the one stepped with, so the grid stays stable.
            var sized = stiffness
            var raised = stiffness
            for _ in 0..<8 {
                let spacing = length / Double(points(sized))
                let speed = tension / density
                raised = stiffness + density * speed * (spacing * spacing - speed * step) / 12
                if raised <= sized { break }
                sized = raised
            }
            self.stepped = Swift.min(raised, sized)
            self.count = points(sized)
            self.spacing = length / Double(count)
            self.up = Line(count + 1)
            self.across = Line(count + 1)
            let spacing = self.spacing
            self.top = (0...count).map { index in
                guard let board, Double(index) * spacing <= board.reach else { return -Double.infinity }
                return -board.clearance(Double(index) * spacing)
            }
        }
    }
}

extension Acoustics.String {
    /// The lowest frequency of the bare string between rigid ends, in hertz.
    public var frequency: Double {
        let wavenumber = Double.pi / length
        return
            (tension / density * wavenumber * wavenumber
            + stiffness / density * wavenumber * wavenumber * wavenumber * wavenumber).squareRoot()
            / (2 * Double.pi)
    }

    /// Where the string is, point by point from nut to bridge.
    public var shape: [Offset] {
        up.now.indices.map { Offset(up: up.now[$0], across: across.now[$0]) }
    }

    /// The string's force on the bridge.
    public var pull: Offset {
        Offset(
            up: Self.pull(up, tension / spacing, stepped / (spacing * spacing * spacing)),
            across: Self.pull(across, tension / spacing, stepped / (spacing * spacing * spacing))
        )
    }

    @usableFromInline
    static func pull(_ line: Line, _ taut: Double, _ stiff: Double) -> Double {
        let last = line.now.endIndex - 1
        let curve = last >= 2 ? line.now[last] - 2 * line.now[last - 1] + line.now[last - 2] : 0
        return -taut * (line.now[last] - line.now[last - 1]) - stiff * curve
    }

    /// Sets the string at rest in a shape; the ends keep to what the shape gives them.
    public mutating func displace(_ shape: (Double) -> Offset) {
        for index in up.now.indices {
            let offset = index == 0 ? Offset.zero : shape(Double(index) * spacing)
            up.now[index] = offset.up
            up.before[index] = offset.up
            across.now[index] = offset.across
            across.before[index] = offset.across
        }
        up.bent = Self.bend(up.before)
        across.bent = Self.bend(across.before)
    }

    @usableFromInline
    static func bend(_ line: [Double]) -> [Double] {
        line.indices.map { index in
            index == 0 || index == line.endIndex - 1
                ? 0 : line[index + 1] - 2 * line[index] + line[index - 1]
        }
    }

    /// The energy in the string and in whatever presses on it, in joules.
    public var energy: Double {
        let taut = tension / spacing
        let stiff = stepped / (spacing * spacing * spacing)
        var total = 0.0
        for line in [up, across] {
            let curve = Self.bend(line.now)
            let curved = Self.bend(line.before)
            for index in line.now.indices.dropFirst() {
                let speed =
                    index == line.now.endIndex - 1 ? 0 : (line.now[index] - line.before[index]) / interval
                total += density * spacing * speed * speed / 2
                total +=
                    taut * (line.now[index] - line.now[index - 1])
                    * (line.before[index] - line.before[index - 1]) / 2
                total += stiff * curve[index] * curved[index] / 2
            }
        }
        let spans = fingers.map(span)
        for index in up.now.indices.dropFirst().dropLast() {
            total += stored(index, up.now[index], across.now[index], spans) / 2
            total += stored(index, up.before[index], across.before[index], spans) / 2
        }
        return total
    }
}

extension Acoustics.String {
    @usableFromInline
    func cover(_ finger: Finger, _ index: Int) -> Double {
        let off = (Double(index) * spacing - finger.place) / (finger.width / 2)
        guard off.magnitude < 1 else { return 0 }
        let rest = 1 - off * off
        return rest * rest
    }

    @usableFromInline
    func span(_ finger: Finger) -> Span {
        let low = Swift.max(1, Int(((finger.place - finger.width / 2) / spacing).rounded(.up)))
        let high = Swift.min(
            top.endIndex - 2,
            Int(((finger.place + finger.width / 2) / spacing).rounded(.down))
        )
        var whole = 0.0
        var index = low
        while index <= high {
            whole += cover(finger, index)
            index += 1
        }
        guard whole > 0 else {
            let nearest = Swift.min(
                top.endIndex - 2,
                Swift.max(1, Int((finger.place / spacing).rounded()))
            )
            return Span(low: nearest, high: nearest, whole: 0)
        }
        return Span(low: low, high: high, whole: whole)
    }

    @usableFromInline
    func part(_ finger: Finger, _ span: Span, _ index: Int) -> Double {
        span.whole > 0 ? cover(finger, index) / span.whole : 1
    }

    @usableFromInline
    func stored(_ index: Int, _ up: Double, _ across: Double, _ spans: [Span]) -> Double {
        var total = 0.0
        if let board, top[index] > up {
            total += spacing * board.contact.energy(pressed: top[index] - up)
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            let rise = up - finger.centre.up
            let side = across - finger.centre.across
            let pressed = finger.radius - (rise * rise + side * side).squareRoot()
            if pressed > 0 {
                total += part(finger, spans[which], index) * finger.contact.energy(pressed: pressed)
            }
        }
        return total
    }

    /// The slope of the stored energy at a point: up and across.
    @usableFromInline
    func slope(_ index: Int, _ up: Double, _ across: Double, _ spans: [Span]) -> Offset {
        var total = Offset.zero
        if let board, top[index] > up {
            total.up -= spacing * board.contact.force(pressed: top[index] - up)
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            let rise = up - finger.centre.up
            let side = across - finger.centre.across
            let away = (rise * rise + side * side).squareRoot()
            guard finger.radius > away, away > 0 else { continue }
            let push =
                part(finger, spans[which], index) * finger.contact.force(pressed: finger.radius - away)
            total.up -= push * rise / away
            total.across -= push * side / away
        }
        return total
    }

    /// Steps the string once, with the bridge end moved to `end`.
    public mutating func advance(end: Offset = .zero) {
        let step = interval * interval
        let wave = tension * step / (density * spacing * spacing)
        let stiff = stepped * step / (density * spacing * spacing * spacing * spacing)
        let rise = 2 * decay.rising * interval / (spacing * spacing)
        let steady = decay.steady * interval
        up.coast(wave: wave, stiff: stiff, rise: rise, steady: steady)
        across.coast(wave: wave, stiff: stiff, rise: rise, steady: steady)
        let slack = step / (density * spacing * (1 + steady))
        let spans = fingers.map(span)
        if board != nil {
            var index = 1
            while index < count {
                if top[index] > up.ahead[index] || top[index] > up.before[index] {
                    settle(index, slack, spans)
                }
                index += 1
            }
        }
        for which in fingers.indices {
            var index = spans[which].low
            while index <= spans[which].high {
                let boarded =
                    board != nil && (top[index] > up.ahead[index] || top[index] > up.before[index])
                let earlier = fingers.indices.prefix(which).contains {
                    index >= spans[$0].low && index <= spans[$0].high
                }
                if !boarded, !earlier { settle(index, slack, spans) }
                index += 1
            }
        }
        up.turn(end: end.up)
        across.turn(end: end.across)
    }

    /// Lets what is stored at one point push it, then takes the losses of whatever it touches.
    @usableFromInline
    mutating func settle(_ index: Int, _ slack: Double, _ spans: [Span]) {
        let wasUp = up.before[index]
        let wasAcross = across.before[index]
        var nextUp = Contact.settle(
            from: wasUp,
            toward: up.ahead[index],
            slack: slack,
            energy: { stored(index, $0, wasAcross, spans) },
            slope: { slope(index, $0, wasAcross, spans).up }
        )
        var nextAcross = Contact.settle(
            from: wasAcross,
            toward: across.ahead[index],
            slack: slack,
            energy: { stored(index, nextUp, $0, spans) },
            slope: { slope(index, nextUp, $0, spans).across }
        )
        if let board, top[index] > nextUp, board.friction > 0 || board.damping > 0 {
            let push = spacing * board.contact.force(pressed: top[index] - nextUp)
            let drag = slack * push / (2 * interval)
            nextUp = wasUp + (nextUp - wasUp) / (1 + drag * board.damping)
            nextAcross =
                wasAcross
                + Self.rub(
                    nextAcross - wasAcross,
                    slack * push * board.friction,
                    2 * interval * board.creep
                )
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            guard finger.friction > 0 || finger.damping > 0 else { continue }
            let rise = nextUp - finger.centre.up
            let side = nextAcross - finger.centre.across
            let away = (rise * rise + side * side).squareRoot()
            guard finger.radius > away, away > 0 else { continue }
            let push =
                part(finger, spans[which], index) * finger.contact.force(pressed: finger.radius - away)
            let drag = slack * push / (2 * interval)
            let outUp = rise / away
            let outAcross = side / away
            let movedUp = nextUp - wasUp - 2 * interval * finger.speed.up
            let movedAcross = nextAcross - wasAcross - 2 * interval * finger.speed.across
            let out = (movedUp * outUp + movedAcross * outAcross) / (1 + drag * finger.damping)
            let along = Self.rub(
                movedAcross * outUp - movedUp * outAcross,
                slack * push * finger.friction,
                2 * interval * finger.creep
            )
            nextUp = wasUp + 2 * interval * finger.speed.up + out * outUp - along * outAcross
            nextAcross = wasAcross + 2 * interval * finger.speed.across + out * outAcross + along * outUp
        }
        up.ahead[index] = nextUp
        across.ahead[index] = nextAcross
    }

    /// A slide over two steps after friction: it holds below `creep`, and takes a fixed amount off above it.
    @usableFromInline
    static func rub(_ slide: Double, _ grip: Double, _ creep: Double) -> Double {
        guard grip > 0 else { return slide }
        let held = slide / (1 + grip / creep)
        if held.magnitude <= creep { return held }
        return slide > 0 ? slide - grip : slide + grip
    }
}
