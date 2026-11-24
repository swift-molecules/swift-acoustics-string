extension Acoustics.String {
    /// One sample of a fingertip: where along the string it is, whose it is and how much of the tip it stands for.
    @usableFromInline
    struct Press: Sendable {
        @usableFromInline var place: Double
        @usableFromInline var finger: Int
        @usableFromInline var share: Double

        @usableFromInline
        init(place: Double, finger: Int, share: Double) {
            self.place = place
            self.finger = finger
            self.share = share
        }
    }

    /// Where fingertips press the string, solved together each step: the points near the tips, and a node of the
    /// string without mass under each press.
    @usableFromInline
    struct Region: Sendable {
        /// Nut to bridge: a point's index, or `-1 - press` for the node under a press.
        @usableFromInline var vertices: [Int] = []
        @usableFromInline var places: [Double] = []
        /// What tension stores along the region above what the grid's straight stretches store: `c / 2 (w_a − w_b)²`.
        @usableFromInline var springs: [Spring] = []
        /// What bending stores: `weight × (slope after − slope before)²` at a vertex, its neighbours in the bending.
        @usableFromInline var bends: [Bend] = []
        /// The grid's own bending is left out at these points: the region bends them instead.
        @usableFromInline var removed: Range<Int> = 0..<0
        /// How far apart, in unknowns, two unknowns of the region can be and still act on each other.
        @usableFromInline var band = 0

        @usableFromInline
        init() {}
    }

    @usableFromInline
    struct Spring: Sendable {
        @usableFromInline var a: Int
        @usableFromInline var b: Int
        @usableFromInline var stiffness: Double

        @usableFromInline
        init(a: Int, b: Int, stiffness: Double) {
            self.a = a
            self.b = b
            self.stiffness = stiffness
        }
    }

    @usableFromInline
    struct Bend: Sendable {
        @usableFromInline var a: Int
        @usableFromInline var b: Int
        @usableFromInline var c: Int
        @usableFromInline var ca: Double
        @usableFromInline var cb: Double
        @usableFromInline var cc: Double
        @usableFromInline var weight: Double

        @usableFromInline
        init(a: Int, b: Int, c: Int, ca: Double, cb: Double, cc: Double, weight: Double) {
            self.a = a
            self.b = b
            self.c = c
            self.ca = ca
            self.cb = cb
            self.cc = cc
            self.weight = weight
        }
    }
}

extension Acoustics.String {
    /// How much a fingertip presses at a place `off` across its half-width from its middle: 1 there, 0 at its edges.
    @usableFromInline
    static func cover(_ off: Double) -> Double {
        guard off.magnitude < 1 else { return 0 }
        let rest = 1 - off * off
        return rest * rest
    }

    /// How many samples a fingertip is taken at: at least two to a spacing, and an odd number, so one is at its middle.
    @usableFromInline
    func samples(_ finger: Finger) -> Int {
        2 * Int((finger.width.underlying / spacing.underlying).rounded(.up)) + 1
    }

    /// Every fingertip as samples spread evenly over its width, finger by finger, each finger's along the string.
    ///
    /// WHY: a tip that pressed the points themselves pinned them, so a stopped pitch moved a whole spacing at a time.
    /// The samples slide with the tip, and the string is held where they are.
    @usableFromInline
    func presses() -> [Press] {
        var presses: [Press] = []
        let length = self.length.underlying
        for (which, finger) in fingers.enumerated() {
            let reach = finger.width.underlying / 2
            let count = samples(finger)
            var whole = 0.0
            for sample in 0..<count { whole += Self.cover(-1 + Double(2 * sample + 1) / Double(count)) }
            for sample in 0..<count {
                let off = -1 + Double(2 * sample + 1) / Double(count)
                presses.append(
                    Press(
                        place: Swift.min(Swift.max(finger.place.underlying + reach * off, 0), length),
                        finger: which,
                        share: Self.cover(off) / whole
                    )
                )
            }
        }
        return presses
    }

    /// The regions the presses make, nut to bridge.
    ///
    /// WHY: a tip pressing the string onto the board holds it where the tip is, seldom at a point, and the string bends
    /// there. So each press holds a node of the string of its own, without mass, and the string runs straight from
    /// vertex to vertex. Bending is taken at the vertices too, each by its share of the length, so the string's free
    /// length, and a stopped pitch with it, move smoothly as a tip slides between points. Points under a tip are left
    /// out of the bending: the tip's evenly spaced nodes stand for them, so the string bends the same wherever the tip
    /// is between points. The last point before a tip, as the tip's edge comes within half a spacing of it, is handed
    /// out of the bending smoothly; at the edge it is gone, as it is once the tip covers it.
    @usableFromInline
    func regions(_ presses: [Press]) -> [Region] {
        guard !presses.isEmpty else { return [] }
        let spacing = self.spacing.underlying
        // Each finger's presses, the points they reach, and where the tip's edges are, in spacings.
        var spans: [(first: Int, last: Int, low: Int, high: Int)] = []
        var start = 0
        while start < presses.count {
            var end = start
            while end < presses.count, presses[end].finger == presses[start].finger { end += 1 }
            let low = Int((presses[start].place / spacing).rounded(.down))
            let high = Swift.min(count, Int((presses[end - 1].place / spacing).rounded(.up)))
            spans.append((start, end - 1, low, high))
            start = end
        }
        spans.sort { $0.low < $1.low }
        var regions: [Region] = []
        var group = 0
        while group < spans.count {
            var end = group + 1
            var reach = spans[group].high + 2
            while end < spans.count, spans[end].low - 2 <= reach {
                reach = Swift.max(reach, spans[end].high + 2)
                end += 1
            }
            regions.append(region(spans[group..<end], presses))
            group = end
        }
        return regions
    }

    /// One region: the fingers `spans`, which reach one another.
    @usableFromInline
    func region(_ spans: ArraySlice<(first: Int, last: Int, low: Int, high: Int)>, _ presses: [Press]) -> Region {
        let spacing = self.spacing.underlying
        let tension = self.tension.underlying
        let stiffness = stepped.underlying
        let shortest = spacing * 0x1p-20
        var region = Region()
        var lowest = count
        var highest = 0
        for span in spans {
            lowest = Swift.min(lowest, span.low)
            highest = Swift.max(highest, span.high)
        }
        let first = Swift.max(0, lowest - 2)
        let last = Swift.min(count, highest + 2)
        region.removed = Swift.max(1, lowest - 1)..<Swift.max(Swift.max(1, lowest - 1), Swift.min(count - 1, highest + 1) + 1)

        // The vertices in order: a node at a point's place goes after it on the tip's nut side and before it on the
        // tip's bridge side, so a tip's nodes are never on the far side of a point they reach.
        var keys: [(place: Double, order: Int, vertex: Int)] = []
        for point in first...last { keys.append((Double(point), 1, point)) }
        for span in spans {
            let middle = (presses[span.first].place + presses[span.last].place) / 2
            for press in span.first...span.last {
                keys.append((presses[press].place / spacing, presses[press].place <= middle ? 2 : 0, -1 - press))
            }
        }
        keys.sort { $0.place < $1.place || ($0.place == $1.place && $0.order < $1.order) }
        region.vertices = keys.map { $0.vertex }
        region.places = keys.map { $0.vertex >= 0 ? Double($0.vertex) * spacing : presses[-1 - $0.vertex].place }
        let vertices = region.vertices
        let places = region.places

        // Tension: each stretch with nodes stores what its pieces store above what the straight stretch does.
        var widest = 1
        var previous = 0
        for index in 1..<vertices.count where vertices[index] >= 0 {
            if index - previous > 1 {
                for piece in previous..<index {
                    let length = Swift.max(places[piece + 1] - places[piece], shortest)
                    region.springs.append(Spring(a: piece, b: piece + 1, stiffness: tension / length))
                }
                region.springs.append(Spring(a: previous, b: index, stiffness: -tension / spacing))
                widest = Swift.max(widest, index - previous)
            }
            previous = index
        }

        // Bending: the vertices it is taken through, every node and every point no tip covers.
        func covered(_ point: Int) -> Bool {
            let place = Double(point)
            for span in spans
            where presses[span.first].place / spacing < place && place < presses[span.last].place / spacing {
                return true
            }
            return false
        }
        var members: [Int] = []
        for index in vertices.indices where vertices[index] < 0 || !covered(vertices[index]) { members.append(index) }
        func sampled(_ member: Int) -> Bool {
            let vertex = vertices[members[member]]
            return vertex < 0 || region.removed.contains(vertex)
        }
        func movable(_ member: Int) -> Bool {
            let vertex = vertices[members[member]]
            return vertex > 0 && vertex < count
        }

        // The points handed out at the tips' edges: each with how much it still bends, and the members it touches.
        var edges: [(member: Int, kept: Double)] = []
        var touched = [Bool](repeating: false, count: members.count)
        func hand(_ edge: Int, _ node: Int) {
            guard edge >= 1, edge + 1 < members.count, movable(edge) else { return }
            guard !touched[edge - 1], !touched[edge], !touched[edge + 1] else { return }
            let gap = (places[members[node]] - places[members[edge]]).magnitude
            let near = gap / (spacing / 2)
            guard near < 1 else { return }
            edges.append((edge, near * near))
            touched[edge - 1] = true
            touched[edge] = true
            touched[edge + 1] = true
        }
        for span in spans {
            let firstNode = members.firstIndex { vertices[$0] == -1 - span.first } ?? 0
            let lastNode = members.firstIndex { vertices[$0] == -1 - span.last } ?? 0
            hand(firstNode - 1, firstNode)
            hand(lastNode + 1, lastNode)
        }

        func bend(_ a: Int, _ b: Int, _ c: Int, _ share: Double) {
            guard share > 0 else { return }
            let before = Swift.max(places[members[b]] - places[members[a]], shortest)
            let after = Swift.max(places[members[c]] - places[members[b]], shortest)
            region.bends.append(
                Bend(
                    a: members[a],
                    b: members[b],
                    c: members[c],
                    ca: 1 / before,
                    cb: -1 / before - 1 / after,
                    cc: 1 / after,
                    weight: share * stiffness / (before + after)
                )
            )
            widest = Swift.max(widest, members[c] - members[a])
        }
        var member = 1
        while member + 1 < members.count {
            defer { member += 1 }
            guard sampled(member) else { continue }
            guard let edge = edges.first(where: { ($0.member - 1)...($0.member + 1) ~= member }) else {
                bend(member - 1, member, member + 1, 1)
                continue
            }
            bend(member - 1, member, member + 1, edge.kept)
            if member == edge.member - 1, member >= 1 {
                bend(member - 1, member, member + 2, 1 - edge.kept)
            } else if member == edge.member + 1 {
                bend(member - 2, member, member + 1, 1 - edge.kept)
            }
        }
        region.band = 2 * widest + 1
        return region
    }
}

extension Acoustics.String {
    /// The board's level under a press, if the board reaches it.
    @usableFromInline
    func level(_ place: Double) -> Double? {
        guard board != nil else { return nil }
        let along = place / spacing.underlying
        let stretch = Swift.min(count - 1, Swift.max(0, Int(along.rounded(.down))))
        guard top[stretch].isFinite, top[stretch + 1].isFinite else { return nil }
        let part = along - Double(stretch)
        return top[stretch] * (1 - part) + top[stretch + 1] * part
    }

    /// What a region stores with its vertices at `ups` and `acrosses`: tension above the straight stretches, bending,
    /// the board under its points and nodes, and the flesh on its nodes.
    @usableFromInline
    func stored(_ region: Region, _ presses: [Press], _ ups: [Double], _ acrosses: [Double]) -> Double {
        var total = 0.0
        for spring in region.springs {
            let up = ups[spring.a] - ups[spring.b]
            let across = acrosses[spring.a] - acrosses[spring.b]
            total += spring.stiffness * (up * up + across * across) / 2
        }
        for bend in region.bends {
            let up = bend.ca * ups[bend.a] + bend.cb * ups[bend.b] + bend.cc * ups[bend.c]
            let across = bend.ca * acrosses[bend.a] + bend.cb * acrosses[bend.b] + bend.cc * acrosses[bend.c]
            total += bend.weight * (up * up + across * across)
        }
        for index in region.vertices.indices {
            let vertex = region.vertices[index]
            if vertex >= 0 {
                if vertex > 0, vertex < count { total += lying(vertex, ups[index]) }
                continue
            }
            let press = presses[-1 - vertex]
            let finger = fingers[press.finger]
            if let board, let level = level(press.place), level > ups[index] {
                total +=
                    finger.width.underlying * press.share
                    * board.contact.energy(pressed: Space.Physical.metres(level - ups[index])).underlying
            }
            let rise = ups[index] - finger.centre.up.underlying
            let side = acrosses[index] - finger.centre.across.underlying
            let away = (rise * rise + side * side).squareRoot()
            if away < finger.radius.underlying {
                total +=
                    press.share
                    * finger.contact.energy(pressed: Space.Physical.metres(finger.radius.underlying - away)).underlying
            }
        }
        return total
    }

    /// The region's vertices at one level: the points' from `ups` and `acrosses`, the nodes' as kept in `held`.
    @usableFromInline
    func vertices(
        _ region: Region,
        _ ups: [Double],
        _ acrosses: [Double],
        before: Bool,
        straight: Bool = false
    ) -> ([Double], [Double]) {
        var level: (up: [Double], across: [Double]) = ([], [])
        vertices(region, ups, acrosses, before: before, straight: straight, into: &level)
        return level
    }

    /// The same, written into `level`.
    @usableFromInline
    func vertices(
        _ region: Region,
        _ ups: [Double],
        _ acrosses: [Double],
        before: Bool,
        straight: Bool = false,
        into level: inout (up: [Double], across: [Double])
    ) {
        var upward: [Double] = []
        var sideways: [Double] = []
        swap(&upward, &level.up)
        swap(&sideways, &level.across)
        defer {
            swap(&upward, &level.up)
            swap(&sideways, &level.across)
        }
        Self.size(&upward, region.vertices.count)
        Self.size(&sideways, region.vertices.count)
        var y = upward.mutableSpan
        var z = sideways.mutableSpan
        for index in region.vertices.indices {
            let vertex = region.vertices[index]
            if vertex >= 0 {
                y[index] = ups[vertex]
                z[index] = acrosses[vertex]
            } else if !straight, case let base = 4 * (-1 - vertex) + (before ? 2 : 0), base + 1 < held.count {
                y[index] = held[base]
                z[index] = held[base + 1]
            } else {
                // WHY: a node not yet kept starts on the straight string.
                let place = region.places[index] / spacing.underlying
                let stretch = Swift.min(count - 1, Int(place.rounded(.down)))
                let part = place - Double(stretch)
                y[index] = ups[stretch] * (1 - part) + ups[stretch + 1] * part
                z[index] = acrosses[stretch] * (1 - part) + acrosses[stretch + 1] * part
            }
        }
    }
}

extension Acoustics.String {
    /// What a solve writes as it goes, kept from step to step so a step allocates nothing for it.
    @usableFromInline
    struct Work: Sendable {
        @usableFromInline var unknown: [Int] = []
        @usableFromInline var columns: [Int] = []
        @usableFromInline var matrix: [Double] = []
        @usableFromInline var miss: [Double] = []
        @usableFromInline var saved: [Double] = []
        @usableFromInline var savedMiss: [Double] = []
        @usableFromInline var change: [Double] = []
        @usableFromInline var middleUp: [Double] = []
        @usableFromInline var middleAcross: [Double] = []
        @usableFromInline var reaches: [Double] = []
        @usableFromInline var sites: [Site] = []
        /// A region's vertices two steps before, where they would coast, and where its solve starts and ends.
        @usableFromInline var from: (up: [Double], across: [Double]) = ([], [])
        @usableFromInline var toward: (up: [Double], across: [Double]) = ([], [])
        @usableFromInline var level: (up: [Double], across: [Double]) = ([], [])
        /// Whether each point is in a region.
        @usableFromInline var inside: [Bool] = []

        @usableFromInline
        init() {}
    }

    /// The fingers' presses and the regions they make.
    ///
    /// WHY: both follow from where the tips are along the string and how wide they are, and nothing else that changes;
    /// they are kept while no tip moves along the string, so a held or lifted tip doesn't lay them out every step.
    @usableFromInline
    struct Layout: Sendable {
        /// Each finger's place and width, in turn.
        @usableFromInline var tips: [Double] = []
        @usableFromInline var presses: [Press] = []
        @usableFromInline var regions: [Region] = []
        /// Each region's matrix as laid by its masses, springs and bending, once a step has laid it.
        @usableFromInline var assembled: [[Double]] = []

        @usableFromInline
        init() {}
    }

    /// The presses and regions for the fingers as they are now, laid out afresh only when a tip has moved along the
    /// string or changed width.
    @usableFromInline
    mutating func laid() -> (presses: [Press], regions: [Region]) {
        var same = !plain && layout.tips.count == 2 * fingers.count
        if same {
            for (index, finger) in fingers.enumerated()
            where layout.tips[2 * index] != finger.place.underlying
                || layout.tips[2 * index + 1] != finger.width.underlying
            {
                same = false
                break
            }
        }
        if !same {
            layout.tips.removeAll(keepingCapacity: true)
            for finger in fingers {
                layout.tips.append(finger.place.underlying)
                layout.tips.append(finger.width.underlying)
            }
            layout.presses = fingers.isEmpty ? [] : presses()
            layout.regions = regions(layout.presses)
            layout.assembled = [[Double]](repeating: [], count: layout.regions.count)
        }
        return (layout.presses, layout.regions)
    }

    /// Whether `pattern` is each finger's count of samples, as kept with `held`.
    @usableFromInline
    var patterned: Bool {
        guard pattern.count == fingers.count else { return false }
        for (index, finger) in fingers.enumerated() where pattern[index] != samples(finger) { return false }
        return true
    }
}

extension Acoustics.String {
    /// How a region is solved.
    @usableFromInline
    enum Solve {
        /// One step on: the points move as their masses and the explicit step say, the nodes balance, and every store
        /// pushes by its change across the two steps, so what the string loses the stores gain exactly.
        case step(slack: Double)
        /// The nodes alone, at rest where the stores balance, the points held.
        case rest
    }

    /// Solves a region: `from` is where its vertices were two steps before (or, at rest, where the points are),
    /// `toward` where the points would coast, and the result where every vertex is one step on.
    ///
    /// WHY: one Newton's solve over the region's points and nodes, its matrix banded. The stores that are springs
    /// push by their slope at the middle of the two steps; the board and the flesh each by the change of what they
    /// store over the change of how far they are pressed, so the energy the solve moves is exact. The losses of the
    /// flesh and the board are a push against each node's and point's motion over the two steps, frozen at where it
    /// was then, so they only take energy.
    @usableFromInline
    func solve(
        _ region: Region,
        _ presses: [Press],
        from: (up: [Double], across: [Double]),
        toward: (up: [Double], across: [Double]),
        start: (up: [Double], across: [Double]),
        _ way: Solve,
        factored: inout [Double]
    ) -> (up: [Double], across: [Double]) {
        var work = Work()
        var assembled: [Double] = []
        var level = start
        solve(
            region,
            presses,
            from: from,
            toward: toward,
            start: &level,
            way,
            factored: &factored,
            assembled: &assembled,
            work: &work
        )
        return level
    }

    /// `solve`, from `start` and into it, writing as it goes into `work`.
    @usableFromInline
    func solve(
        _ region: Region,
        _ presses: [Press],
        from: (up: [Double], across: [Double]),
        toward: (up: [Double], across: [Double]),
        start: inout (up: [Double], across: [Double]),
        _ way: Solve,
        factored: inout [Double],
        assembled: inout [Double],
        work: inout Work
    ) {
        let vertices = region.vertices
        let total = vertices.count
        let twice = 2 * interval.underlying
        let spacing = self.spacing.underlying
        var resting = false
        var slack = 1.0
        switch way {
        case .step(let given): slack = given
        case .rest: resting = true
        }
        // The unknowns: up and across at each vertex that moves, in order.
        var unknown: [Int] = []
        swap(&unknown, &work.unknown)
        defer { swap(&unknown, &work.unknown) }
        Self.fill(&unknown, -1, total)
        var unknowns = 0
        for index in 0..<total {
            let vertex = vertices[index]
            let moves = resting ? vertex < 0 : vertex < 0 || (vertex > 0 && vertex < count)
            if moves {
                unknown[index] = unknowns
                unknowns += 2
            }
        }
        var ups: [Double] = []
        var acrosses: [Double] = []
        swap(&ups, &start.up)
        swap(&acrosses, &start.across)
        defer {
            swap(&ups, &start.up)
            swap(&acrosses, &start.across)
        }
        guard unknowns > 0 else { return }
        let band = Swift.min(region.band, unknowns - 1)
        let row = 2 * band + 1
        var matrix: [Double] = []
        var miss: [Double] = []
        var saved: [Double] = []
        var savedMiss: [Double] = []
        var change: [Double] = []
        var middleUp: [Double] = []
        var middleAcross: [Double] = []
        var reaches: [Double] = []
        var columns: [Int] = []
        var sites: [Site] = []
        swap(&matrix, &work.matrix)
        swap(&miss, &work.miss)
        swap(&saved, &work.saved)
        swap(&savedMiss, &work.savedMiss)
        swap(&change, &work.change)
        swap(&middleUp, &work.middleUp)
        swap(&middleAcross, &work.middleAcross)
        swap(&reaches, &work.reaches)
        swap(&columns, &work.columns)
        swap(&sites, &work.sites)
        defer {
            swap(&matrix, &work.matrix)
            swap(&miss, &work.miss)
            swap(&saved, &work.saved)
            swap(&savedMiss, &work.savedMiss)
            swap(&change, &work.change)
            swap(&middleUp, &work.middleUp)
            swap(&middleAcross, &work.middleAcross)
            swap(&reaches, &work.reaches)
            swap(&columns, &work.columns)
            swap(&sites, &work.sites)
        }
        // WHY: only sized; each is written before it is read.
        Self.size(&matrix, unknowns * row)
        Self.size(&miss, unknowns)
        Self.size(&saved, unknowns * row)
        Self.size(&savedMiss, unknowns)
        Self.size(&change, unknowns)
        Self.size(&middleUp, total)
        Self.size(&middleAcross, total)
        Self.size(&columns, band)
        sites.removeAll(keepingCapacity: true)
        // A Jacobian of the springs at the middle is half their stiffness; at rest, all of it.
        let half = resting ? 1.0 : 0.5

        var building = true
        // WHY: the matrix's place for row `i`, column `j`.
        func at(_ i: Int, _ j: Int) -> Int { i * row + j - i + band }

        // What the losses push with, frozen two steps before.
        var lossy = false
        if case .step = way {
            for finger in fingers where finger.friction > .zero || finger.damping > .zero { lossy = true }
            if let board, board.friction > .zero || board.damping > .zero { lossy = true }
        }

        // Each friction (in `sites`): the unknowns it slides along and by how much, how far it has slid, its most and
        // its creep.
        // WHY: the arrays a round writes are handed in, so each is written through one span, not looked up afresh.
        func assemble(
            _ matrix: inout [Double],
            _ miss: inout [Double],
            _ sites: inout [Site],
            _ middleUp: inout [Double],
            _ middleAcross: inout [Double]
        ) -> (worst: Double, touching: Bool) {
            var touching = false
            var m = matrix.mutableSpan
            var r = miss.mutableSpan
            var mu = middleUp.mutableSpan
            var ma = middleAcross.mutableSpan
            let ups = ups.span
            let acrosses = acrosses.span
            func add(_ m: inout MutableSpan<Double>, _ i: Int, _ j: Int, _ value: Double) {
                guard building else { return }
                m[at(i, j)] += value
            }
            // WHY: the masses', springs' and bending's part of the matrix is the same every round and every step while
            // the region is, and every entry takes it before anything that touches; so it is laid once and kept in
            // `assembled`, and a round starts from it with the same bits.
            let laying = building && (plain || assembled.count != m.count)
            func lay(_ m: inout MutableSpan<Double>, _ i: Int, _ j: Int, _ value: Double) {
                guard laying else { return }
                m[at(i, j)] += value
            }
            if laying {
                for index in 0..<m.count { m[index] = 0 }
            } else if building {
                let laid = assembled.span
                for index in 0..<m.count { m[index] = laid[index] }
            }
            for index in 0..<r.count { r[index] = 0 }
            sites.removeAll(keepingCapacity: true)
            for index in 0..<total {
                let fromUp = resting ? ups[index] : from.up[index]
                let fromAcross = resting ? acrosses[index] : from.across[index]
                mu[index] = (fromUp + ups[index]) / 2
                ma[index] = (fromAcross + acrosses[index]) / 2
                let at = unknown[index]
                if at >= 0, !resting, vertices[index] >= 0 {
                    r[at] = ups[index] - toward.up[index]
                    r[at + 1] = acrosses[index] - toward.across[index]
                    lay(&m, at, at, 1)
                    lay(&m, at + 1, at + 1, 1)
                }
            }
            for spring in region.springs {
                let up = spring.stiffness * (mu[spring.a] - mu[spring.b])
                let across = spring.stiffness * (ma[spring.a] - ma[spring.b])
                let a = unknown[spring.a]
                let b = unknown[spring.b]
                let firm = slack * spring.stiffness * half
                if a >= 0 {
                    r[a] += slack * up
                    r[a + 1] += slack * across
                    lay(&m, a, a, firm)
                    lay(&m, a + 1, a + 1, firm)
                }
                if b >= 0 {
                    r[b] -= slack * up
                    r[b + 1] -= slack * across
                    lay(&m, b, b, firm)
                    lay(&m, b + 1, b + 1, firm)
                }
                if a >= 0, b >= 0 {
                    lay(&m, a, b, -firm)
                    lay(&m, b, a, -firm)
                    lay(&m, a + 1, b + 1, -firm)
                    lay(&m, b + 1, a + 1, -firm)
                }
            }
            for bend in region.bends {
                let up =
                    2 * bend.weight
                    * (bend.ca * mu[bend.a] + bend.cb * mu[bend.b] + bend.cc * mu[bend.c])
                let across =
                    2 * bend.weight
                    * (bend.ca * ma[bend.a] + bend.cb * ma[bend.b]
                        + bend.cc * ma[bend.c])
                let at: InlineArray<3, Int> = [unknown[bend.a], unknown[bend.b], unknown[bend.c]]
                let by: InlineArray<3, Double> = [bend.ca, bend.cb, bend.cc]
                for i in 0..<3 where at[i] >= 0 {
                    r[at[i]] += slack * up * by[i]
                    r[at[i] + 1] += slack * across * by[i]
                    guard laying else { continue }
                    for j in 0..<3 where at[j] >= 0 {
                        let firm = slack * 2 * bend.weight * by[i] * by[j] * half
                        lay(&m, at[i], at[j], firm)
                        lay(&m, at[i] + 1, at[j] + 1, firm)
                    }
                }
            }
            if laying {
                Self.size(&assembled, m.count)
                var laid = assembled.mutableSpan
                for index in 0..<m.count { laid[index] = m[index] }
            }
            // WHY: where nothing touches, now or two steps before, nothing below adds anything.
            if !untouched {
                for index in 0..<total {
                    let at = unknown[index]
                    guard at >= 0 else { continue }
                    let vertex = vertices[index]
                    let fromUp = resting ? ups[index] : from.up[index]
                    let fromAcross = resting ? acrosses[index] : from.across[index]
                    // The board under the vertex.
                    var length = spacing
                    var level: Double?
                    var press: Press?
                    if vertex >= 0 {
                        if board != nil, top[vertex].isFinite { level = top[vertex] }
                    } else {
                        let pressing = presses[-1 - vertex]
                        press = pressing
                        length = fingers[pressing.finger].width.underlying * pressing.share
                        level = self.level(pressing.place)
                    }
                    if let board, let level {
                        let contact = board.contact
                        let now = level - ups[index]
                        let was = level - fromUp
                        if now > 0 || was > 0 {
                            touching = true
                            let mean = Self.mean(
                                now,
                                was,
                                { length * contact.energy(pressed: Space.Physical.metres($0)).underlying },
                                { length * contact.force(pressed: Space.Physical.metres($0)).underlying },
                                {
                                    $0 > 0
                                        ? contact.exponent * length
                                            * contact.force(pressed: Space.Physical.metres($0)).underlying / $0 : 0
                                }
                            )
                            r[at] -= slack * mean.value
                            add(&m, at, at, slack * mean.slope * 2 * half)
                        }
                        if lossy, was > 0 {
                            let push = length * contact.force(pressed: Space.Physical.metres(was)).underlying
                            let damping = board.damping.underlying * push / twice
                            r[at] += slack * damping * (ups[index] - fromUp)
                            add(&m, at, at, slack * damping)
                            if board.friction > .zero, push > 0, board.creep > .zero {
                                sites.append(
                                    Site(
                                        first: at + 1,
                                        second: at,
                                        along: 1,
                                        besides: 0,
                                        slid: acrosses[index] - fromAcross,
                                        most: board.friction.underlying * push,
                                        creep: twice * board.creep.underlying
                                    )
                                )
                            }
                        }
                    }
                    guard let press else { continue }
                    // The flesh on the node.
                    let finger = fingers[press.finger]
                    let radius = finger.radius.underlying
                    let contact = finger.contact
                    let share = press.share
                    let nowUp = ups[index] - finger.centre.up.underlying
                    let nowAcross = acrosses[index] - finger.centre.across.underlying
                    let wasUp = fromUp - finger.centre.up.underlying
                    let wasAcross = fromAcross - finger.centre.across.underlying
                    let now = (nowUp * nowUp + nowAcross * nowAcross).squareRoot()
                    let was = (wasUp * wasUp + wasAcross * wasAcross).squareRoot()
                    if now < radius || was < radius, now + was > 0 {
                        touching = true
                        let mean = Self.mean(
                            radius - now,
                            radius - was,
                            { share * contact.energy(pressed: Space.Physical.metres($0)).underlying },
                            { share * contact.force(pressed: Space.Physical.metres($0)).underlying },
                            {
                                $0 > 0
                                    ? contact.exponent * share
                                        * contact.force(pressed: Space.Physical.metres($0)).underlying / $0 : 0
                            }
                        )
                        // WHY: what the flesh stores falls as the node moves away from the tip's centre, by `mean` over
                        // the change of that distance; the change of the distance is the sum of the two places over the
                        // sum of the two distances, dotted with the move.
                        let sum = now + was
                        let outUp = (nowUp + wasUp) / sum
                        let outAcross = (nowAcross + wasAcross) / sum
                        r[at] -= slack * mean.value * outUp
                        r[at + 1] -= slack * mean.value * outAcross
                        let towardUp = now > 0 ? nowUp / now : 0
                        let towardAcross = now > 0 ? nowAcross / now : 0
                        let firm = slack * mean.slope * 2 * half
                        let soft = slack * mean.value * 2 * half / sum
                        add(&m, at, at, firm * outUp * towardUp - soft * (1 - outUp * towardUp))
                        add(&m, at, at + 1, firm * outUp * towardAcross + soft * outUp * towardAcross)
                        add(&m, at + 1, at, firm * outAcross * towardUp + soft * outAcross * towardUp)
                        add(&m, at + 1, at + 1, firm * outAcross * towardAcross - soft * (1 - outAcross * towardAcross))
                    }
                    if lossy, was < radius, was > 0, finger.damping > .zero || finger.friction > .zero {
                        let push = share * contact.force(pressed: Space.Physical.metres(radius - was)).underlying
                        let outUp = wasUp / was
                        let outAcross = wasAcross / was
                        let movedUp = ups[index] - fromUp - twice * finger.speed.up.underlying
                        let movedAcross = acrosses[index] - fromAcross - twice * finger.speed.across.underlying
                        let damping = finger.damping.underlying * push / twice
                        let normal = movedUp * outUp + movedAcross * outAcross
                        let slide = movedAcross * outUp - movedUp * outAcross
                        r[at] += slack * damping * normal * outUp
                        r[at + 1] += slack * damping * normal * outAcross
                        add(&m, at, at, slack * damping * outUp * outUp)
                        add(&m, at + 1, at + 1, slack * damping * outAcross * outAcross)
                        if finger.friction > .zero, push > 0, finger.creep > .zero {
                            sites.append(
                                Site(
                                    first: at + 1,
                                    second: at,
                                    along: outUp,
                                    besides: -outAcross,
                                    slid: slide,
                                    most: finger.friction.underlying * push,
                                    creep: twice * finger.creep.underlying
                                )
                            )
                        }
                        let both = slack * damping * outUp * outAcross
                        add(&m, at, at + 1, both)
                        add(&m, at + 1, at, both)
                    }
                }
            }
            var worst = 0.0
            for index in 0..<r.count { worst = Swift.max(worst, r[index].magnitude) }
            return (worst, touching)
        }

        /// Banded elimination without pivoting, the multipliers kept: the masses' and the springs' rule the matrix.
        ///
        /// WHY: only a pivot row's entries that aren't zero are taken off the rows below. That leaves every bit as it
        /// was: no entry is ever −0 (each starts at +0 and is only summed and differenced), so taking off a zero
        /// product changed nothing.
        func factor(_ matrix: inout [Double]) {
            var m = matrix.mutableSpan
            var nonzero = columns.mutableSpan
            for pivot in 0..<unknowns {
                // WHY: row `i`'s entry in column `j` is at `i × (row − 1) + band + j`.
                let pivots = pivot * (row - 1) + band
                let diagonal = m[pivots + pivot]
                let reach = Swift.min(unknowns - 1, pivot + band)
                guard pivot < reach else { continue }
                var count = 0
                for column in (pivot + 1)..<(reach + 1) where plain || m[pivots + column] != 0 {
                    nonzero[count] = pivots &+ column
                    count &+= 1
                }
                for lower in (pivot + 1)..<(reach + 1) {
                    let lowers = lower * (row - 1) + band
                    let entry = m[lowers + pivot]
                    guard entry != 0 else { continue }
                    let factor = entry / diagonal
                    m[lowers + pivot] = factor
                    let shift = lowers - pivots
                    for which in 0..<count {
                        let above = nonzero[which]
                        m[above &+ shift] -= factor * m[above]
                    }
                }
            }
        }
        /// The factored `matrix`'s answer to `right`, in place.
        func through(_ matrix: [Double], _ right: inout [Double]) {
            var r = right.mutableSpan
            through(matrix.span, &r, from: 0)
        }
        /// The same for the `unknowns` entries of `r` from `base` on.
        func through(_ m: Span<Double>, _ r: inout MutableSpan<Double>, from base: Int) {
            for pivot in 0..<unknowns {
                let reach = Swift.min(unknowns - 1, pivot + band)
                let value = r[base + pivot]
                guard pivot < reach, value != 0 else { continue }
                // WHY: row `lower`'s entry in column `pivot` is at `lower × (row − 1) + band + pivot`.
                var entry = (pivot + 1) * (row - 1) + band + pivot
                for lower in (base + pivot + 1)..<(base + reach + 1) {
                    r[lower] -= m[entry] * value
                    entry &+= row &- 1
                }
            }
            var pivot = unknowns - 1
            while pivot >= 0 {
                var sum = r[base + pivot]
                let reach = Swift.min(unknowns - 1, pivot + band)
                let pivots = pivot * (row - 1) + band
                if pivot < reach {
                    let shift = base - pivots
                    for entry in (pivots + pivot + 1)..<(pivots + reach + 1) {
                        sum -= m[entry] * r[entry &+ shift]
                    }
                }
                r[base + pivot] = sum / m[pivots + pivot]
                pivot -= 1
            }
        }
        /// Whether anything touches a vertex, now or two steps before.
        func touches() -> Bool {
            let ups = ups.span
            let acrosses = acrosses.span
            for index in 0..<total where unknown[index] >= 0 {
                let vertex = vertices[index]
                let fromUp = resting ? ups[index] : from.up[index]
                let fromAcross = resting ? acrosses[index] : from.across[index]
                var level: Double?
                if vertex >= 0 {
                    if board != nil, top[vertex].isFinite { level = top[vertex] }
                } else {
                    level = self.level(presses[-1 - vertex].place)
                }
                if let level, level > ups[index] || level > fromUp { return true }
                guard vertex < 0 else { continue }
                let finger = fingers[presses[-1 - vertex].finger]
                let radius = finger.radius.underlying
                let centre = (up: finger.centre.up.underlying, across: finger.centre.across.underlying)
                let rise = ups[index] - centre.up
                let side = acrosses[index] - centre.across
                if rise * rise + side * side < radius * radius { return true }
                let wasRise = fromUp - centre.up
                let wasSide = fromAcross - centre.across
                if wasRise * wasRise + wasSide * wasSide < radius * radius { return true }
            }
            return false
        }
        var wasLinear = false
        var untouched = false
        var lastSize = Double.infinity
        var rounds = 0
        var scale = 0x1p-30
        // WHY: plain Newton's steps. A friction that has just turned round is given its holding stiffness (`grip`),
        // which keeps the steps from turning it back and forth; a step cut short by the miss growing did worse.
        while rounds < 60 {
            rounds += 1
            // WHY: where nothing touches, the region's matrix is its springs' alone, the same step after step while the
            // tips stay where they are along the string; one step of it is the answer.
            untouched = !touches()
            if untouched, wasLinear { break }
            building = !(untouched && factored.count == matrix.count)
            let (worst, touching) = assemble(&matrix, &miss, &sites, &middleUp, &middleAcross)
            if worst == 0 { break }
            let linear = !touching && sites.isEmpty
            wasLinear = linear
            // WHY: first each friction is taken as holding (on the first round) or as it goes now, and Newton's step
            // made with it; if the step leaves every friction going as taken, that is the step. Most steps are so.
            if !sites.isEmpty {
                saved.replaceSubrange(saved.indices, with: matrix)
                savedMiss.replaceSubrange(savedMiss.indices, with: miss)
                var m = matrix.mutableSpan
                var r = miss.mutableSpan
                for site in sites {
                    if site.slid.magnitude <= site.creep || rounds == 1 {
                        let firm = slack * site.most / site.creep
                        r[site.first] += firm * site.slid * site.along
                        r[site.second] += firm * site.slid * site.besides
                        if building {
                            m[at(site.first, site.first)] += firm * site.along * site.along
                            m[at(site.first, site.second)] += firm * site.along * site.besides
                            m[at(site.second, site.first)] += firm * site.besides * site.along
                            m[at(site.second, site.second)] += firm * site.besides * site.besides
                        }
                    } else {
                        let push = slack * (site.slid > 0 ? site.most : -site.most)
                        r[site.first] += push * site.along
                        r[site.second] += push * site.besides
                    }
                }
            }
            // WHY: a kept factoring is solved with where it is kept; nothing reads the matrix after an untouched step.
            let reused = linear && factored.count == matrix.count
            if !reused {
                factor(&matrix)
                if linear { factored = matrix }
            }
            change.replaceSubrange(change.indices, with: miss)
            through(reused ? factored : matrix, &change)
            for index in change.indices { change[index] = -change[index] }
            var kept = true
            for site in sites {
                let slid = site.slid + site.along * change[site.first] + site.besides * change[site.second]
                let holding = site.slid.magnitude <= site.creep || rounds == 1
                if holding ? slid.magnitude > site.creep * (1 + 0x1p-30) : slid * site.slid <= site.creep * site.slid.magnitude {
                    kept = false
                    break
                }
            }
            if !kept {
                // WHY: the frictions are solved exactly against the rest, made straight: each one's push is what holds
                // it, or its most, given the others'. Newton's steps then never turn a friction back and forth between
                // holding and sliding.
                matrix.replaceSubrange(matrix.indices, with: saved)
                miss.replaceSubrange(miss.indices, with: savedMiss)
                factor(&matrix)
                change.replaceSubrange(change.indices, with: miss)
                through(matrix, &change)
                for index in change.indices { change[index] = -change[index] }
                let count = sites.count
                // WHY: each friction's reach, how the unknowns move for a unit of its push, one after another.
                Self.fill(&reaches, 0, count * unknowns)
                var free = [Double](repeating: 0, count: count)
                var weights = [Double](repeating: 0, count: count * count)
                do {
                    let m = matrix.span
                    var all = reaches.mutableSpan
                    for (k, site) in sites.enumerated() {
                        let base = k * unknowns
                        all[base + site.first] = slack * site.along
                        all[base + site.second] += slack * site.besides
                        through(m, &all, from: base)
                        free[k] = site.slid + site.along * change[site.first] + site.besides * change[site.second]
                    }
                }
                for (k, site) in sites.enumerated() {
                    for j in 0..<count {
                        let reach = j * unknowns
                        weights[k * count + j] =
                            site.along * reaches[reach + site.first] + site.besides * reaches[reach + site.second]
                    }
                }
                let pushes = Self.box(weights, free, sites)
                for k in 0..<count where pushes[k] != 0 {
                    for index in 0..<unknowns { change[index] -= reaches[k * unknowns + index] * pushes[k] }
                }
            }
            var size = 0.0
            do {
                var u = ups.mutableSpan
                var a = acrosses.mutableSpan
                for index in 0..<total {
                    scale = Swift.max(scale, u[index].magnitude, a[index].magnitude)
                    let at = unknown[index]
                    guard at >= 0 else { continue }
                    u[index] += change[at]
                    a[index] += change[at + 1]
                    size = Swift.max(size, change[at].magnitude, change[at + 1].magnitude)
                }
            }
            // WHY: done once a step moves nothing past the last bits, or once rounding stops it shrinking.
            let previous = lastSize
            lastSize = size
            if size <= 0x1p-48 * scale { break }
            if size <= 0x1p-40 * scale, size > previous / 8 { break }
            if rounds > 6, size >= previous { break }
        }
    }

    /// Sets `array` to `count` copies of `value`, keeping what it has room for.
    @usableFromInline
    static func fill<Element>(_ array: inout [Element], _ value: Element, _ count: Int) {
        array.removeAll(keepingCapacity: true)
        array.append(contentsOf: repeatElement(value, count: count))
    }

    /// Makes `array` `count` long, keeping what it holds where it can and adding zeros.
    @usableFromInline
    static func size<Element: Swift.Numeric>(_ array: inout [Element], _ count: Int) {
        if array.count > count {
            array.removeLast(array.count - count)
        } else if array.count < count {
            array.append(contentsOf: repeatElement(.zero, count: count - array.count))
        }
    }

    /// The mean slope of a store `energy` between being pressed `now` and `was`, and its slope in `now`.
    @usableFromInline
    static func mean(
        _ now: Double,
        _ was: Double,
        _ energy: (Double) -> Double,
        _ force: (Double) -> Double,
        _ firmness: (Double) -> Double
    ) -> (value: Double, slope: Double) {
        let change = now - was
        if change.magnitude < 1e-12 {
            let middle = (now + was) / 2
            return (force(middle), firmness(middle) / 2)
        }
        let value = (energy(now) - energy(was)) / change
        return (value, (force(now) - value) / change)
    }

    /// The frictions' pushes `f` that hold where they can: `slid = free − weights · f`, each push the holding spring's
    /// on what it slid, or its most where that is more.
    ///
    /// WHY: the pushes minimise a quadratic with each within its most, so the ones at their most are guessed, the rest
    /// solved together exactly, and the guess mended until every push agrees with its slide. With the holding springs
    /// in, the matrix is positive, so this ends; should it not soon, sweeps one push at a time finish it.
    @usableFromInline
    static func box(_ weights: [Double], _ free: [Double], _ sites: [Site]) -> [Double] {
        let count = sites.count
        var matrix = weights
        for k in 0..<count { matrix[k * count + k] += sites[k].creep / sites[k].most }
        // At a bound: +1 or −1; free: 0.
        var bound = [Int](repeating: 0, count: count)
        var pushes = [Double](repeating: 0, count: count)
        var settled = false
        var rounds = 0
        while rounds < 2 * count + 4 {
            rounds += 1
            // Solve the free pushes with the bound ones held at their most.
            let open = (0..<count).filter { bound[$0] == 0 }
            for k in 0..<count where bound[k] != 0 { pushes[k] = Double(bound[k]) * sites[k].most }
            if !open.isEmpty {
                let size = open.count
                var system = [Double](repeating: 0, count: size * size)
                var right = [Double](repeating: 0, count: size)
                for (i, k) in open.enumerated() {
                    right[i] = free[k]
                    for j in 0..<count where bound[j] != 0 { right[i] -= matrix[k * count + j] * pushes[j] }
                    for (l, j) in open.enumerated() { system[i * size + l] = matrix[k * count + j] }
                }
                // Cholesky, in place.
                var positive = true
                for i in 0..<size where positive {
                    for l in 0..<(i + 1) {
                        var sum = system[i * size + l]
                        for m in 0..<l { sum -= system[i * size + m] * system[l * size + m] }
                        if i == l {
                            if sum <= 0 { positive = false } else { system[i * size + i] = sum.squareRoot() }
                        } else {
                            system[i * size + l] = sum / system[l * size + l]
                        }
                    }
                }
                guard positive else { break }
                for i in 0..<size {
                    var sum = right[i]
                    for m in 0..<i { sum -= system[i * size + m] * right[m] }
                    right[i] = sum / system[i * size + i]
                }
                var i = size - 1
                while i >= 0 {
                    var sum = right[i]
                    for m in (i + 1)..<size { sum -= system[m * size + i] * right[m] }
                    right[i] = sum / system[i * size + i]
                    i -= 1
                }
                for (i, k) in open.enumerated() { pushes[k] = right[i] }
            }
            // Mend the guess: a free push past its most goes to it; a bound push whose slide has turned is freed.
            var changed = false
            for k in 0..<count {
                if bound[k] == 0 {
                    if pushes[k].magnitude > sites[k].most {
                        bound[k] = pushes[k] > 0 ? 1 : -1
                        changed = true
                    }
                } else {
                    var slid = free[k]
                    for j in 0..<count { slid -= matrix[k * count + j] * pushes[j] }
                    // The spring would push less than the most: it holds after all.
                    if slid * Double(bound[k]) < 0 {
                        bound[k] = 0
                        changed = true
                    }
                }
            }
            if !changed {
                settled = true
                break
            }
        }
        if settled { return pushes }
        for k in 0..<count { pushes[k] = Swift.min(sites[k].most, Swift.max(-sites[k].most, pushes[k])) }
        var sweeps = 0
        while sweeps < 400 {
            sweeps += 1
            var moved = 0.0
            for k in 0..<count {
                var slid = free[k]
                for j in 0..<count where j != k { slid -= matrix[k * count + j] * pushes[j] }
                let push = Swift.min(sites[k].most, Swift.max(-sites[k].most, slid / matrix[k * count + k]))
                moved = Swift.max(moved, (push - pushes[k]).magnitude / sites[k].most)
                pushes[k] = push
            }
            if moved < 0x1p-40 { break }
        }
        return pushes
    }

    /// A friction in a solve: it slides by `along` the unknown `first` and `besides` the unknown `second`, has slid
    /// `slid` so far, pushes with at most `most`, and holds like a spring below `creep`.
    @usableFromInline
    struct Site: Sendable {
        @usableFromInline var first: Int
        @usableFromInline var second: Int
        @usableFromInline var along: Double
        @usableFromInline var besides: Double
        @usableFromInline var slid: Double
        @usableFromInline var most: Double
        @usableFromInline var creep: Double

        @usableFromInline
        init(first: Int, second: Int, along: Double, besides: Double, slid: Double, most: Double, creep: Double) {
            self.first = first
            self.second = second
            self.along = along
            self.besides = besides
            self.slid = slid
            self.most = most
            self.creep = creep
        }
    }
}
