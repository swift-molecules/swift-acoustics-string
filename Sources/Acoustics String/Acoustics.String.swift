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
        /// Where the string is under each press of the fingers, now and a step before: up and across, by press.
        @usableFromInline var held: [Double] = []
        /// How many presses each finger had when `held` was kept.
        @usableFromInline var pattern: [Int] = []
        /// Each region's factored matrix where nothing touches it, by where its vertices are.
        @usableFromInline var factorings: [(places: [Double], matrix: [Double])] = []

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
        pattern = []
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
        let presses = fingers.isEmpty ? [] : presses()
        let regions = regions(presses)
        var total = 0.0
        for line in [up, across] {
            let curve = Self.bend(line.now)
            let curved = Self.bend(line.before)
            var region = 0
            for index in line.now.indices.dropFirst() {
                let speed =
                    index == line.now.endIndex - 1 ? 0 : (line.now[index] - line.before[index]) / interval
                total += density * spacing * speed * speed / 2
                total +=
                    taut * (line.now[index] - line.now[index - 1])
                    * (line.before[index] - line.before[index - 1]) / 2
                while region < regions.count, regions[region].removed.upperBound <= index { region += 1 }
                if region == regions.count || !regions[region].removed.contains(index) {
                    total += stiff * curve[index] * curved[index] / 2
                }
                for (number, part) in damping.memory.enumerated() {
                    let kept = number * line.now.count + index
                    let strain = line.now[index] - line.now[index - 1] - line.kept[kept] + line.kept[kept - 1]
                    total += density * part.strength * strain * strain / (2 * spacing)
                }
            }
        }
        // WHY: before the nodes are kept, they are where the stores balance.
        let kept = pattern == fingers.map(samples)
        var inside = [Bool](repeating: false, count: count + 1)
        for region in regions {
            for vertex in region.vertices where vertex >= 0 { inside[vertex] = true }
            for before in [false, true] {
                var level =
                    vertices(region, before ? up.before : up.now, before ? across.before : across.now, before: before)
                if !kept {
                    var unused: [Double] = []
                    level = solve(region, presses, from: level, toward: level, start: level, .rest, factored: &unused)
                }
                total += stored(region, presses, level.0, level.1) / 2
            }
        }
        for index in up.now.indices.dropFirst().dropLast() where !inside[index] {
            total += lying(index, up.now[index]) / 2
            total += lying(index, up.before[index]) / 2
        }
        return Energy.joules(total)
    }
}

extension Acoustics.String {
    /// The board's energy at point `index`, the point at `up`.
    @usableFromInline
    func lying(_ index: Int, _ up: Double) -> Double {
        guard let board, top[index] > up else { return 0 }
        return spacing.underlying * board.contact.energy(pressed: Space.Physical.metres(top[index] - up)).underlying
    }

    /// The board's push up on point `index` at `up`.
    @usableFromInline
    func lifting(_ index: Int, _ up: Double) -> Double {
        guard let board, top[index] > up else { return 0 }
        return spacing.underlying * board.contact.force(pressed: Space.Physical.metres(top[index] - up)).underlying
    }

    /// Finds where the string rests under every press, now and a step before, for fingers just set or changed.
    @usableFromInline
    mutating func keep(_ presses: [Press], _ regions: [Region]) {
        held = [Double](repeating: 0, count: 4 * presses.count)
        for region in regions {
            for before in [false, true] {
                var level = vertices(
                    region,
                    before ? up.before : up.now,
                    before ? across.before : across.now,
                    before: before,
                    straight: true
                )
                var unused: [Double] = []
                level = solve(region, presses, from: level, toward: level, start: level, .rest, factored: &unused)
                for index in region.vertices.indices where region.vertices[index] < 0 {
                    let base = 4 * (-1 - region.vertices[index]) + (before ? 2 : 0)
                    held[base] = level.0[index]
                    held[base + 1] = level.1[index]
                }
            }
        }
        pattern = fingers.map(samples)
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
        let presses = fingers.isEmpty ? [] : presses()
        let regions = regions(presses)
        var inside = [Bool](repeating: false, count: regions.isEmpty ? 0 : count + 1)
        if !regions.isEmpty {
            up.ahead[count] = end.up.underlying
            across.ahead[count] = end.across.underlying
            if pattern != fingers.map(samples) { keep(presses, regions) }
            // WHY: a region bends its own points; the grid's bending there comes out of the step.
            let shared = 1 + steady
            for region in regions {
                for vertex in region.vertices where vertex >= 0 { inside[vertex] = true }
                for index in region.removed {
                    let upCurve = up.bend[index] * stiff / shared
                    let acrossCurve = across.bend[index] * stiff / shared
                    up.ahead[index - 1] += upCurve
                    up.ahead[index] -= 2 * upCurve
                    up.ahead[index + 1] += upCurve
                    across.ahead[index - 1] += acrossCurve
                    across.ahead[index] -= 2 * acrossCurve
                    across.ahead[index + 1] += acrossCurve
                }
            }
            up.ahead[0] = 0
            across.ahead[0] = 0
            up.ahead[count] = end.up.underlying
            across.ahead[count] = end.across.underlying
        }
        if board != nil {
            var index = 1
            while index < count {
                if inside.isEmpty || !inside[index], top[index] > up.ahead[index] || top[index] > up.before[index] {
                    settle(index, mass, slack)
                }
                index += 1
            }
        }
        if !regions.isEmpty {
            var next = held
            for press in presses.indices {
                next[4 * press + 2] = held[4 * press]
                next[4 * press + 3] = held[4 * press + 1]
            }
            var kept: [(places: [Double], matrix: [Double])] = []
            for region in regions {
                let from = vertices(region, up.before, across.before, before: true)
                let toward = vertices(region, up.ahead, across.ahead, before: false)
                var start = toward
                for index in region.vertices.indices where region.vertices[index] < 0 {
                    // WHY: a node starts from where it would coast.
                    start.0[index] = 2 * start.0[index] - from.0[index]
                    start.1[index] = 2 * start.1[index] - from.1[index]
                }
                // WHY: a region's matrix where nothing touches is kept while its vertices stay where they are.
                var factored = factorings.first { $0.places == region.places }?.matrix ?? []
                let ahead = solve(region, presses, from: from, toward: toward, start: start, .step(slack: slack), factored: &factored)
                if !factored.isEmpty { kept.append((region.places, factored)) }
                for index in region.vertices.indices {
                    let vertex = region.vertices[index]
                    if vertex > 0, vertex < count {
                        up.ahead[vertex] = ahead.0[index]
                        across.ahead[vertex] = ahead.1[index]
                    } else if vertex < 0 {
                        next[4 * (-1 - vertex)] = ahead.0[index]
                        next[4 * (-1 - vertex) + 1] = ahead.1[index]
                    }
                }
            }
            held = next
            factorings = kept
        }
        up.turn(end: end.up.underlying, follows: follows)
        across.turn(end: end.across.underlying, follows: follows)
    }

    /// Lets the board push a point it lies on, then takes the board's losses at the point.
    @usableFromInline
    mutating func settle(_ index: Int, _ mass: Double, _ slack: Double) {
        let interval = self.interval.underlying
        let wasUp = up.before[index]
        let wasAcross = across.before[index]
        var nextUp = Contact.settle(
            from: Space.Physical.metres(wasUp),
            toward: Space.Physical.metres(up.ahead[index]),
            mass: Mass.kilograms(mass),
            every: self.interval,
            energy: { Energy.joules(lying(index, $0.underlying)) },
            slope: { Force.newtons(-lifting(index, $0.underlying)) }
        ).underlying
        var nextAcross = across.ahead[index]
        if let board, board.friction > .zero || board.damping > .zero, case let push = lifting(index, nextUp), push > 0 {
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
