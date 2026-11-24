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
        @usableFromInline let damping: Damping
        /// Each memory part's pull and how far its copy follows the string, per step.
        @usableFromInline let pulls: [Double]
        @usableFromInline let follows: [Double]
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

        /// A string that loses what physics says it loses: to the air, and inside its material.
        ///
        /// The grid carries a decay of the form a + b β² + c β⁴ in the wavenumber β; it is matched to `losses` over
        /// the partials up to 16 kHz.
        public init(
            length: Length<Space.Physical, Double>,
            tension: Force.Value<Double>,
            density: Density.Linear.Value<Double>,
            stiffness: Rigidity.Flexural.Value<Double> = .zero,
            losses: Losses = .none,
            board: Board? = nil,
            every interval: Time.Duration.Value<Double>
        ) {
            // WHY: the grid's spacing depends on the losses, and the match on the spacing; two rounds settle both.
            var spacing = 0.0
            var damping = Damping(steady: .zero, rising: .zero, steep: 0)
            for _ in 0..<3 {
                damping = Damping(
                    matching: { frequency in
                        losses.decay(
                            at: Frequency.hertz(frequency),
                            tension: tension,
                            density: density,
                            stiffness: stiffness
                        ).underlying
                    },
                    length: length.underlying,
                    speed: tension.underlying / density.underlying,
                    bending: stiffness.underlying / density.underlying,
                    top: Swift.min(16_000, 0.25 / interval.underlying),
                    spacing: spacing,
                    every: interval.underlying,
                    remembering: true
                )
                let grid = Self.grid(
                    length: length.underlying,
                    tension: tension.underlying,
                    density: density.underlying,
                    stiffness: stiffness.underlying,
                    damping: damping,
                    interval: interval.underlying
                )
                let next = length.underlying / Double(grid.count)
                if next == spacing { break }
                spacing = next
            }
            self.init(
                length: length,
                tension: tension,
                density: density,
                stiffness: stiffness,
                damping: damping,
                board: board,
                every: interval
            )
        }

        /// A string whose ringing dies by a fitted decay: the behaviour before physical losses, kept until they are
        /// heard and approved. Delete it then.
        public init(
            length: Length<Space.Physical, Double>,
            tension: Force.Value<Double>,
            density: Density.Linear.Value<Double>,
            stiffness: Rigidity.Flexural.Value<Double> = .zero,
            decay: Decay,
            board: Board? = nil,
            every interval: Time.Duration.Value<Double>
        ) {
            self.init(
                length: length,
                tension: tension,
                density: density,
                stiffness: stiffness,
                damping: Damping(steady: decay.steady, rising: decay.rising, steep: 0),
                board: board,
                every: interval
            )
        }

        init(
            length: Length<Space.Physical, Double>,
            tension: Force.Value<Double>,
            density: Density.Linear.Value<Double>,
            stiffness: Rigidity.Flexural.Value<Double>,
            damping: Damping,
            board: Board?,
            every interval: Time.Duration.Value<Double>
        ) {
            self.length = length
            self.tension = tension
            self.density = density
            self.stiffness = stiffness
            self.damping = damping
            self.board = board
            self.interval = interval
            let length = length.underlying
            let grid = Self.grid(
                length: length,
                tension: tension.underlying,
                density: density.underlying,
                stiffness: stiffness.underlying,
                damping: damping,
                interval: interval.underlying
            )
            self.stepped = Rigidity.Flexural.amount(grid.stepped)
            self.count = grid.count
            let spacing = length / Double(count)
            self.spacing = Space.Physical.metres(spacing)
            let step = interval.underlying * interval.underlying
            self.pulls = damping.memory.map { $0.strength * step / (spacing * spacing) }
            self.follows = damping.memory.map { 1 - Double.math.exp(-interval.underlying / $0.time) }
            self.up = Line(count + 1, memory: damping.memory.count)
            self.across = Line(count + 1, memory: damping.memory.count)
            self.top = (0...count).map { index in
                guard let board, Double(index) * spacing <= board.reach.underlying else { return -Double.infinity }
                return -board.clearance(Space.Physical.metres(Double(index) * spacing)).underlying
            }
        }
    }
}

extension Acoustics.String {
    /// The number of stretches the grid needs to stay stable, and the stiffness it is stepped with.
    static func grid(
        length: Double,
        tension: Double,
        density: Double,
        stiffness: Double,
        damping: Damping,
        interval: Double
    ) -> (count: Int, stepped: Double) {
        let step = interval * interval
        // WHY: a memory that can't follow pulls as more tension does, so the spacing allows for its whole pull.
        let wave = (tension / density + damping.strength) * step + 4 * damping.rising.underlying * interval
        let steep = 64 * damping.steep * interval
        func points(_ stiff: Double) -> Int {
            // WHY: von Neumann on the step: h⁴ ≥ (c²k² + 4σ₁k) h² + 4κ²k² + 16σ₂k keeps every partial bounded.
            let least = ((wave + (wave * wave + 16 * stiff / density * step + steep).squareRoot()) / 2)
                .squareRoot()
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
        return (points(sized), Swift.min(raised, sized))
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

    /// How fast a partial of this wavenumber dies on the grid, before anything touches the string.
    public func decay(at wavenumber: Wavenumber.Value<Double>) -> Decay::Decay.Value<Double> {
        let beta = wavenumber.underlying
        let angular =
            ((tension.underlying * beta * beta + stiffness.underlying * beta * beta * beta * beta) / density.underlying)
            .squareRoot()
        return Decay::Decay.amount(damping.decay(beta, angular: angular, spacing: spacing.underlying))
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
        for part in damping.memory.indices {
            for index in up.now.indices {
                up.kept[part * up.now.count + index] = up.now[index]
                across.kept[part * across.now.count + index] = across.now[index]
            }
        }
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
                for (number, part) in damping.memory.enumerated() {
                    let kept = number * line.now.count + index
                    let strain = line.now[index] - line.now[index - 1] - line.kept[kept] + line.kept[kept - 1]
                    total += density * part.strength * strain * strain / (2 * spacing)
                }
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
    /// Half the length of string a fingertip presses on: half its width, but never less than one spacing.
    ///
    /// WHY: a tip narrower than the grid would fall between points, and act on the nearest one alone, so a stopped
    /// pitch would jump from point to point as the tip moves. Spread over at least two points, its weight passes
    /// smoothly from one to the next.
    @usableFromInline
    func reach(_ finger: Finger) -> Double {
        Swift.max(finger.width.underlying / 2, spacing.underlying)
    }

    @usableFromInline
    func cover(_ finger: Finger, _ index: Int) -> Double {
        let off = (Double(index) * spacing.underlying - finger.place.underlying) / reach(finger)
        guard off.magnitude < 1 else { return 0 }
        let rest = 1 - off * off
        return rest * rest
    }

    @usableFromInline
    func span(_ finger: Finger) -> Span {
        let spacing = self.spacing.underlying
        let place = finger.place.underlying
        let reach = reach(finger)
        let low = Swift.max(1, Int(((place - reach) / spacing).rounded(.up)))
        let high = Swift.min(
            top.endIndex - 2,
            Int(((place + reach) / spacing).rounded(.down))
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
        let rise = 2 * damping.rising.underlying * interval / (spacing * spacing)
        let steady = damping.steady.underlying * interval
        let steep = 2 * damping.steep * interval / (spacing * spacing * spacing * spacing)
        up.coast(wave: wave, stiff: stiff, rise: rise, steady: steady, steep: steep, pulls: pulls)
        across.coast(wave: wave, stiff: stiff, rise: rise, steady: steady, steep: steep, pulls: pulls)
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
        up.turn(end: end.up.underlying, follows: follows)
        across.turn(end: end.across.underlying, follows: follows)
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
        if let board, top[index] > nextUp, board.friction > .zero || board.damping > .zero {
            let push =
                spacing.underlying * board.contact.force(pressed: Space.Physical.metres(top[index] - nextUp)).underlying
            let drag = slack * push / (2 * interval)
            nextUp = wasUp + (nextUp - wasUp) / (1 + drag * board.damping.underlying)
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
            guard finger.friction > .zero || finger.damping > .zero else { continue }
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
            let out = (movedUp * outUp + movedAcross * outAcross) / (1 + drag * finger.damping.underlying)
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
