internal import Numeric

extension Acoustics {
    /// A stiff string between a nut and a bridge, free to move in both directions across itself.
    ///
    /// The string is a row of points stepped together. Everything that touches it (a fingerboard, a fingertip) is a
    /// stored energy at each point, so with no loss set the string and what it touches keep their energy exactly.
    public struct String: Sendable {
        public let length: Length<Space.Physical, Double>
        public let tension: Force.Value<Double>
        /// Mass per length.
        public let density: Density.Linear.Value<Double>
        /// Bending stiffness.
        public let stiffness: Rigidity.Flexural.Value<Double>
        /// The stiffness the grid is stepped with: a little more than `stiffness`, so the grid's own flattening of
        /// high partials is cancelled and they sound where the stiff string's law puts them.
        @usableFromInline let stepped: Rigidity.Flexural.Value<Double>
        public let decay: Decay
        public let interval: Time.Duration.Value<Double>
        /// The distance between neighbouring points.
        public let spacing: Length<Space.Physical, Double>
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
            length: Length<Space.Physical, Double>,
            tension: Force.Value<Double>,
            density: Density.Linear.Value<Double>,
            stiffness: Rigidity.Flexural.Value<Double> = .zero,
            decay: Decay = .none,
            board: Board? = nil,
            every interval: Time.Duration.Value<Double>
        ) {
            self.length = length
            self.tension = tension
            self.density = density
            self.stiffness = stiffness
            self.decay = decay
            self.board = board
            self.interval = interval
            let length = length.underlying
            let tension = tension.underlying
            let density = density.underlying
            let stiffness = stiffness.underlying
            let interval = interval.underlying
            let step = interval * interval
            let wave = tension / density * step + 4 * decay.rising.underlying * interval
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
            self.stepped = Rigidity.Flexural.amount(Swift.min(raised, sized))
            self.count = points(sized)
            let spacing = length / Double(count)
            self.spacing = Space.Physical.metres(spacing)
            self.up = Line(count + 1)
            self.across = Line(count + 1)
            self.top = (0...count).map { index in
                guard let board, Double(index) * spacing <= board.reach.underlying else { return -Double.infinity }
                return -board.clearance(Space.Physical.metres(Double(index) * spacing)).underlying
            }
        }
    }
}

extension Acoustics.String {
    /// The lowest frequency of the bare string between rigid ends.
    public var frequency: Frequency.Value<Double> {
        let tension = self.tension.underlying
        let density = self.density.underlying
        let stiffness = self.stiffness.underlying
        let wavenumber = Double.pi / length.underlying
        return Frequency.hertz(
            (tension / density * wavenumber * wavenumber
                + stiffness / density * wavenumber * wavenumber * wavenumber * wavenumber).squareRoot()
                / (2 * Double.pi)
        )
    }

    /// Where the string is, point by point from nut to bridge.
    public var shape: [Offset<Measure<1, Space.Physical>>] {
        up.now.indices.map {
            Offset(up: Space.Physical.metres(up.now[$0]), across: Space.Physical.metres(across.now[$0]))
        }
    }

    /// The string's force on the bridge.
    public var pull: Offset<Force> {
        let tension = self.tension.underlying
        let stepped = self.stepped.underlying
        let spacing = self.spacing.underlying
        return Offset(
            up: Force.newtons(Self.pull(up, tension / spacing, stepped / (spacing * spacing * spacing))),
            across: Force.newtons(Self.pull(across, tension / spacing, stepped / (spacing * spacing * spacing)))
        )
    }

    @usableFromInline
    static func pull(_ line: Line, _ taut: Double, _ stiff: Double) -> Double {
        let last = line.now.endIndex - 1
        let curve = last >= 2 ? line.now[last] - 2 * line.now[last - 1] + line.now[last - 2] : 0
        return -taut * (line.now[last] - line.now[last - 1]) - stiff * curve
    }

    /// Sets the string at rest in a shape; the ends keep to what the shape gives them.
    public mutating func displace(
        _ shape: (Length<Space.Physical, Double>) -> Offset<Measure<1, Space.Physical>>
    ) {
        for index in up.now.indices {
            let offset = index == 0 ? Offset.zero : shape(Space.Physical.metres(Double(index) * spacing.underlying))
            up.now[index] = offset.up.underlying
            up.before[index] = offset.up.underlying
            across.now[index] = offset.across.underlying
            across.before[index] = offset.across.underlying
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

    /// The energy in the string and in whatever presses on it.
    public var energy: Energy.Value<Double> {
        let interval = self.interval.underlying
        let density = self.density.underlying
        let spacing = self.spacing.underlying
        let taut = tension.underlying / spacing
        let stiff = stepped.underlying / (spacing * spacing * spacing)
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
        return Energy.joules(total)
    }
}

extension Acoustics.String {
    @usableFromInline
    func cover(_ finger: Finger, _ index: Int) -> Double {
        let off = (Double(index) * spacing.underlying - finger.place.underlying) / (finger.width.underlying / 2)
        guard off.magnitude < 1 else { return 0 }
        let rest = 1 - off * off
        return rest * rest
    }

    @usableFromInline
    func span(_ finger: Finger) -> Span {
        let spacing = self.spacing.underlying
        let place = finger.place.underlying
        let width = finger.width.underlying
        let low = Swift.max(1, Int(((place - width / 2) / spacing).rounded(.up)))
        let high = Swift.min(
            top.endIndex - 2,
            Int(((place + width / 2) / spacing).rounded(.down))
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
                Swift.max(1, Int((place / spacing).rounded()))
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
            total +=
                spacing.underlying * board.contact.energy(pressed: Space.Physical.metres(top[index] - up)).underlying
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            let rise = up - finger.centre.up.underlying
            let side = across - finger.centre.across.underlying
            let pressed = finger.radius.underlying - (rise * rise + side * side).squareRoot()
            if pressed > 0 {
                total +=
                    part(finger, spans[which], index)
                    * finger.contact.energy(pressed: Space.Physical.metres(pressed)).underlying
            }
        }
        return total
    }

    /// The slope of the stored energy at a point, up and across, in newtons.
    @usableFromInline
    func slope(_ index: Int, _ up: Double, _ across: Double, _ spans: [Span]) -> (up: Double, across: Double) {
        var total = (up: 0.0, across: 0.0)
        if let board, top[index] > up {
            total.up -=
                spacing.underlying * board.contact.force(pressed: Space.Physical.metres(top[index] - up)).underlying
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            let radius = finger.radius.underlying
            let rise = up - finger.centre.up.underlying
            let side = across - finger.centre.across.underlying
            let away = (rise * rise + side * side).squareRoot()
            guard radius > away, away > 0 else { continue }
            let push =
                part(finger, spans[which], index)
                * finger.contact.force(pressed: Space.Physical.metres(radius - away)).underlying
            total.up -= push * rise / away
            total.across -= push * side / away
        }
        return total
    }

    /// Steps the string once, with the bridge end moved to `end`.
    public mutating func advance(end: Offset<Measure<1, Space.Physical>> = .zero) {
        let interval = self.interval.underlying
        let tension = self.tension.underlying
        let density = self.density.underlying
        let spacing = self.spacing.underlying
        let step = interval * interval
        let wave = tension * step / (density * spacing * spacing)
        let stiff = stepped.underlying * step / (density * spacing * spacing * spacing * spacing)
        let rise = 2 * decay.rising.underlying * interval / (spacing * spacing)
        let steady = decay.steady.underlying * interval
        up.coast(wave: wave, stiff: stiff, rise: rise, steady: steady)
        across.coast(wave: wave, stiff: stiff, rise: rise, steady: steady)
        let mass = density * spacing * (1 + steady)
        let slack = step / mass
        let spans = fingers.map(span)
        if board != nil {
            var index = 1
            while index < count {
                if top[index] > up.ahead[index] || top[index] > up.before[index] {
                    settle(index, mass, slack, spans)
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
                if !boarded, !earlier { settle(index, mass, slack, spans) }
                index += 1
            }
        }
        up.turn(end: end.up.underlying)
        across.turn(end: end.across.underlying)
    }

    /// Lets what is stored at one point push it, then takes the losses of whatever it touches.
    @usableFromInline
    mutating func settle(_ index: Int, _ mass: Double, _ slack: Double, _ spans: [Span]) {
        let interval = self.interval.underlying
        let wasUp = up.before[index]
        let wasAcross = across.before[index]
        var nextUp = Contact.settle(
            from: Space.Physical.metres(wasUp),
            toward: Space.Physical.metres(up.ahead[index]),
            mass: Mass.kilograms(mass),
            every: self.interval,
            energy: { Energy.joules(stored(index, $0.underlying, wasAcross, spans)) },
            slope: { Force.newtons(slope(index, $0.underlying, wasAcross, spans).up) }
        ).underlying
        var nextAcross = Contact.settle(
            from: Space.Physical.metres(wasAcross),
            toward: Space.Physical.metres(across.ahead[index]),
            mass: Mass.kilograms(mass),
            every: self.interval,
            energy: { Energy.joules(stored(index, nextUp, $0.underlying, spans)) },
            slope: { Force.newtons(slope(index, nextUp, $0.underlying, spans).across) }
        ).underlying
        if let board, top[index] > nextUp, board.friction > .zero || board.damping > 0 {
            let push =
                spacing.underlying * board.contact.force(pressed: Space.Physical.metres(top[index] - nextUp)).underlying
            let drag = slack * push / (2 * interval)
            nextUp = wasUp + (nextUp - wasUp) / (1 + drag * board.damping)
            nextAcross =
                wasAcross
                + Self.rub(
                    nextAcross - wasAcross,
                    slack * push * board.friction.underlying,
                    2 * interval * board.creep.underlying
                )
        }
        for which in fingers.indices where index >= spans[which].low && index <= spans[which].high {
            let finger = fingers[which]
            guard finger.friction > .zero || finger.damping > 0 else { continue }
            let radius = finger.radius.underlying
            let speedUp = finger.speed.up.underlying
            let speedAcross = finger.speed.across.underlying
            let rise = nextUp - finger.centre.up.underlying
            let side = nextAcross - finger.centre.across.underlying
            let away = (rise * rise + side * side).squareRoot()
            guard radius > away, away > 0 else { continue }
            let push =
                part(finger, spans[which], index)
                * finger.contact.force(pressed: Space.Physical.metres(radius - away)).underlying
            let drag = slack * push / (2 * interval)
            let outUp = rise / away
            let outAcross = side / away
            let movedUp = nextUp - wasUp - 2 * interval * speedUp
            let movedAcross = nextAcross - wasAcross - 2 * interval * speedAcross
            let out = (movedUp * outUp + movedAcross * outAcross) / (1 + drag * finger.damping)
            let along = Self.rub(
                movedAcross * outUp - movedUp * outAcross,
                slack * push * finger.friction.underlying,
                2 * interval * finger.creep.underlying
            )
            nextUp = wasUp + 2 * interval * speedUp + out * outUp - along * outAcross
            nextAcross = wasAcross + 2 * interval * speedAcross + out * outAcross + along * outUp
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
