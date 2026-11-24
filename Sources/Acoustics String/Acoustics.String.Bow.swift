internal import Numeric

extension Acoustics.String {
    /// A rosined bow drawn across the string: it grips the string where it touches and drags it along, until the
    /// string's pull breaks the grip and it slips back.
    ///
    /// The bow touches the string at one place, between two points of the grid, and acts across the string, along the
    /// top. How hard it grips is the friction of rosin at the speed the string slides under the hair
    /// (`Acoustics.String.Rosin`), times the force pressing the bow into the string.
    public struct Bow: Hashable, Sendable {
        /// Where along the string the hair touches it, from the nut.
        public var place: Length<Space.Physical, Double>
        /// How fast the bow is drawn across the string.
        public var speed: Velocity.Value<Double>
        /// How hard the bow is pressed into the string.
        public var force: Force.Value<Double>
        /// How rosin grips the string as it slides.
        public var rosin: Rosin
        /// How wide the ribbon of hair is along the string. The hair moves as one, so it grips or slips as one, and
        /// presses hardest at its middle. Zero touches at one place.
        public var width: Length<Space.Physical, Double>

        public init(
            place: Length<Space.Physical, Double>,
            speed: Velocity.Value<Double>,
            force: Force.Value<Double>,
            rosin: Rosin = .init(),
            width: Length<Space.Physical, Double> = .zero
        ) {
            self.place = place
            self.speed = speed
            self.force = force
            self.rosin = rosin
            self.width = width
        }
    }

    /// How rosin's friction falls as the string slides faster under the hair: μ(v) = μ_d + a e^(−|v|/v_a) +
    /// b e^(−|v|/v_b).
    ///
    /// The values are the steady-sliding curve Smith and Woodhouse (2000, "The tribology of rosin", J. Mech. Phys.
    /// Solids 48, 1633–1681) fitted to rosin: μ_d = 0.35, a = 0.4 at 0.01 m/s, b = 0.45 at 0.1 m/s, so 1.2 held
    /// still. They also show the friction of rosin in stick and slip follows its temperature, not only its speed
    /// (their "thermal" model); this curve leaves that out.
    public struct Rosin: Hashable, Sendable {
        /// The friction left at high sliding speed.
        public var sliding: Friction.Value<Double>
        /// The first rise above `sliding` toward rest, and the speed it falls away over.
        public var slow: Friction.Value<Double>
        public var slowSpeed: Velocity.Value<Double>
        /// The second rise, and the speed it falls away over.
        public var fast: Friction.Value<Double>
        public var fastSpeed: Velocity.Value<Double>

        public init(
            sliding: Friction.Value<Double> = Friction.amount(0.35),
            slow: Friction.Value<Double> = Friction.amount(0.4),
            slowSpeed: Velocity.Value<Double> = Velocity.amount(0.01),
            fast: Friction.Value<Double> = Friction.amount(0.45),
            fastSpeed: Velocity.Value<Double> = Velocity.amount(0.1)
        ) {
            self.sliding = sliding
            self.slow = slow
            self.slowSpeed = slowSpeed
            self.fast = fast
            self.fastSpeed = fastSpeed
        }
    }
}

extension Acoustics.String.Rosin {
    /// The friction held still: the most the bow can grip with.
    public var still: Friction.Value<Double> { sliding + slow + fast }

    /// The friction at sliding speed `speed`, either way.
    @inlinable
    public func friction(sliding speed: Double) -> Double {
        let speed = speed.magnitude
        return sliding.underlying + slow.underlying * Double.math.exp(-speed / slowSpeed.underlying)
            + fast.underlying * Double.math.exp(-speed / fastSpeed.underlying)
    }
}

extension Acoustics.String {
    /// The force the hair puts on the string across it, given that with no bow the string under the hair would move
    /// `free` faster than the bow over the two steps, and that a force f changes that by `give` × f.
    ///
    /// WHY: the string's speed under the hair is its move over two steps, so the step is implicit in the friction,
    /// and solving it is solving one equation. The bow holds (sticks) if a force within the most rosin grips with
    /// brings the string to the bow's speed. Otherwise it slips, at a sliding speed v with v + give × F μ(v) = free.
    /// Where both, or two slips, solve it, the string keeps doing what it did: one that was sliding goes on sliding at
    /// the speed nearest its last, one that held goes on holding. That is the hysteresis of McIntyre, Schumacher and
    /// Woodhouse (1983, "On the oscillations of musical instruments", J. Acoust. Soc. Am. 74, 1325–1345), Friedlander's
    /// construction with its jump rule.
    @usableFromInline
    static func grip(
        _ free: Double,
        give: Double,
        force: Double,
        rosin: Rosin,
        slipping: inout Double
    ) -> Double {
        guard force > 0, give > 0 else {
            slipping = free
            return 0
        }
        guard free != 0 else {
            slipping = 0
            return 0
        }
        let pressed = give * force
        let ahead = free.magnitude
        let direction: Double = free > 0 ? 1 : -1
        func excess(_ sliding: Double) -> Double { sliding + pressed * rosin.friction(sliding: sliding) - ahead }
        let holds = ahead <= pressed * rosin.still.underlying
        let going = slipping != 0 && (slipping > 0) == (free > 0)
        if holds && !going {
            slipping = 0
            return -free / give
        }
        // The slips: where `excess` crosses zero on (0, ahead]. It is below zero at rest unless the bow holds, and
        // above zero at `ahead`.
        var roots = InlineArray<4, Double>(repeating: 0)
        var found = 0
        let samples = 48
        var low = 0.0
        var lowExcess = excess(0)
        var sample = 1
        while sample <= samples, found < 4 {
            // WHY: rosin changes on the scale of its own speeds; samples spaced evenly in the logarithm see both.
            let high = ahead * Double.math.pow(2, -24 * Double(samples - sample) / Double(samples))
            let highExcess = sample == samples ? pressed * rosin.friction(sliding: ahead) : excess(high)
            if (lowExcess < 0) != (highExcess < 0) {
                var a = low
                var b = high
                var aExcess = lowExcess
                for _ in 0..<60 {
                    let middle = (a + b) / 2
                    let middleExcess = excess(middle)
                    if (middleExcess < 0) == (aExcess < 0) {
                        a = middle
                        aExcess = middleExcess
                    } else {
                        b = middle
                    }
                    if b - a <= 1e-15 * ahead { break }
                }
                roots[found] = (a + b) / 2
                found += 1
            }
            low = high
            lowExcess = highExcess
            sample += 1
        }
        guard found > 0 else {
            // Only holding solves it.
            slipping = 0
            return -free / give
        }
        var chosen = roots[0]
        if going {
            let last = slipping.magnitude
            for index in 1..<found where (roots[index] - last).magnitude < (chosen - last).magnitude {
                chosen = roots[index]
            }
        }
        slipping = direction * chosen
        return -direction * force * rosin.friction(sliding: chosen)
    }

    /// How much of the bow's push point `index` takes, of a bow whose middle is `along` spacings from the nut and which
    /// reaches `reach` spacings either side: shared by the hair's cover there, or between the two points beside its
    /// middle for a bow narrower than a spacing. Over all points the shares add to one.
    @usableFromInline
    static func share(_ index: Int, along: Double, reach: Double, whole: Double) -> Double {
        guard reach > 1 else {
            let first = along.rounded(.down)
            let offset = Double(index) - first
            return offset == 0 ? 1 - (along - first) : offset == 1 ? along - first : 0
        }
        return cover((Double(index) - along) / reach) / whole
    }

    /// Lets the bow grip or slip on the string, after everything else has moved it this step.
    @usableFromInline
    mutating func rub(_ bow: Bow, _ slack: Double) {
        let interval = self.interval.underlying
        let along = bow.place.underlying / spacing.underlying
        let reach = bow.width.underlying / (2 * spacing.underlying)
        let first = reach > 1 ? Int((along - reach).rounded(.up)) : Int(along.rounded(.down))
        let last = reach > 1 ? Int((along + reach).rounded(.down)) : first + 1
        var whole = 0.0
        if reach > 1 {
            for index in first...last { whole += Self.cover((Double(index) - along) / reach) }
        }
        var moving = 0.0
        var spread = 0.0
        for index in first...last where index > 0 && index < count {
            let weight = Self.share(index, along: along, reach: reach, whole: whole)
            moving += weight * (across.ahead[index] - across.before[index])
            spread += weight * weight
        }
        guard spread > 0 else { return }
        var free = moving / (2 * interval) - bow.speed.underlying
        var give = slack * spread / (2 * interval)
        // WHY: the hair grips the surface, which moves across and turns; it feels both, and its force drives both.
        var turning: (index: Int, near: Double, far: Double, slack: Double)?
        if let twisting {
            let (index, near, far) = twisting.beside(bow.place.underlying)
            let line = twisting.line
            let turned =
                near * (line.ahead[index] - line.before[index]) + far * (line.ahead[index + 1] - line.before[index + 1])
            let twistSlack = interval * interval / twisting.mass
            free += turned / (2 * interval)
            give += twistSlack * (near * near + far * far) / (2 * interval)
            turning = (index, near, far, twistSlack)
        }
        let force = Self.grip(
            free,
            give: give,
            force: bow.force.underlying,
            rosin: bow.rosin,
            slipping: &slipping
        )
        for index in first...last where index > 0 && index < count {
            across.ahead[index] += slack * Self.share(index, along: along, reach: reach, whole: whole) * force
        }
        if let turning {
            twisting?.line.ahead[turning.index] += turning.slack * turning.near * force
            twisting?.line.ahead[turning.index + 1] += turning.slack * turning.far * force
        }
        rubbing = Velocity.amount(free + give * force)
        gripping = Force.newtons(force)
    }
}
