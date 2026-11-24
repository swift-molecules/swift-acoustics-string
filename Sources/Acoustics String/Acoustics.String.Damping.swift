internal import Numeric

extension Acoustics.String {
    /// The losses the grid steps with: a decay every partial shares, one that grows with the wavenumber squared, one
    /// that grows with its fourth power, and the string's memory. A partial of wavenumber β and angular frequency ω
    /// decays at `steady + rising β² + steep β⁴ + Σ g β² τ / (2 (1 + ω² τ²))`.
    ///
    /// None may be negative: a negative loss feeds the grid's highest partials, and the string blows up.
    @usableFromInline
    struct Damping: Sendable {
        @usableFromInline let steady: Decay::Decay.Value<Double>
        @usableFromInline let rising: Viscosity.Kinematic.Value<Double>
        /// In m⁴/s. No atom holds this kind, so it is a scalar.
        @usableFromInline let steep: Double
        /// The string's memory, a standard linear solid in its tension: each part keeps a copy ψ of the string that
        /// follows it with lag `time` (ψ′ = (u − ψ) / τ), and pulls the string toward it with `strength` g, in m²/s²
        /// (a tension per mass per length). No atom holds that kind, so it is a scalar.
        ///
        /// WHY: a + b β² + c β⁴ can't follow air's √f and heat's f. Each part's decay rises as f² below 1/τ and is
        /// flat above it, so parts with lags spread over the band, none of them negative, follow any rising law closely,
        /// and the string stays passive.
        @usableFromInline let memory: [(strength: Double, time: Double)]
        /// The step the memory is followed with; zero for a memory followed continuously.
        @usableFromInline let interval: Double

        @usableFromInline
        init(
            steady: Decay::Decay.Value<Double>,
            rising: Viscosity.Kinematic.Value<Double>,
            steep: Double,
            memory: [(strength: Double, time: Double)] = [],
            every interval: Double = 0
        ) {
            precondition(
                steady >= .zero && rising >= .zero && steep >= 0 && memory.allSatisfy { $0.strength >= 0 && $0.time > 0 },
                "A string's losses can't be negative: a negative loss feeds energy in and the grid blows up."
            )
            self.steady = steady
            self.rising = rising
            self.steep = steep
            self.memory = memory
            self.interval = interval
        }

        /// The pull of all the memory's parts together when the string moves too fast for any of them to follow.
        @usableFromInline
        var strength: Double { memory.reduce(0) { $0 + $1.strength } }

        /// The decay of a partial of wavenumber `beta` and angular frequency `angular` on a grid of this spacing, in
        /// 1/s: the grid's second difference sees β² as (2/h · sin(βh/2))².
        @usableFromInline
        func decay(_ beta: Double, angular: Double, spacing: Double) -> Double {
            let square = Self.felt(beta, spacing)
            var total = steady.underlying + rising.underlying * square + steep * square * square
            for part in memory { total += part.strength * square * Self.lagging(angular, part.time, interval) }
            return total
        }

        /// How much of a part's pull lags the string, as a decay per pull and squared wavenumber: τ / (2 (1 + ω² τ²))
        /// when followed continuously.
        ///
        /// WHY: the shortest lags are a sample or two, where stepping changes the lag. Stepped every k, followed by
        /// α = 1 − e^(−k/τ) a step and pulling on the step before, a partial at θ = ω k decays by
        /// k α (1 − α) / (2 ((cos θ − 1 + α)² + sin² θ)) per pull and squared wavenumber.
        @usableFromInline
        static func lagging(_ angular: Double, _ time: Double, _ interval: Double) -> Double {
            guard interval > 0 else { return time / (2 * (1 + angular * angular * time * time)) }
            let follow = 1 - Double.math.exp(-interval / time)
            let turn = angular * interval
            let real = Double.math.cos(turn) - 1 + follow
            let imaginary = Double.math.sin(turn)
            return interval * follow * (1 - follow) / (2 * (real * real + imaginary * imaginary))
        }

        /// The square of the wavenumber the grid's second difference sees.
        @usableFromInline
        static func felt(_ beta: Double, _ spacing: Double) -> Double {
            guard spacing > 0 else { return beta * beta }
            let half = Double.math.sin(beta * spacing / 2) * 2 / spacing
            return half * half
        }
    }
}

extension Acoustics.String.Damping {
    /// The lags the memory may use: corners a third of a decade apart, from 16 kHz down to half of `lowest`.
    ///
    /// WHY: a part that lags longer than the lowest partial's period damps nothing heard and only creeps.
    static func lags(down lowest: Double) -> [Double] {
        var lags: [Double] = []
        var corner = 16_000.0
        while corner >= lowest / 2 {
            lags.append(1 / (2 * Double.pi * corner))
            corner /= Double.math.pow(10, 1.0 / 3)
        }
        return lags
    }

    /// The grid's closest match to a law that gives each partial its own decay.
    ///
    /// The partials are those of the stiff string up to `top`, as a grid of `spacing` holds them (zero for the
    /// continuous string). Each one's decay is matched in proportion to itself, and each octave counts alike, by least
    /// squares with no coefficient below zero (Lawson and Hanson's active set). With `remembering`, the string's
    /// memory joins the match.
    init(
        matching decay: (_ frequency: Double) -> Double,
        length: Double,
        speed: Double,
        bending: Double,
        top: Double,
        spacing: Double = 0,
        every interval: Double = 0,
        remembering: Bool = false
    ) {
        var rows: [(x: Double, angular: Double, target: Double, weight: Double)] = []
        var partial = 1.0
        while true {
            let beta = partial * Double.pi / length
            let frequency = (speed * beta * beta + bending * beta * beta * beta * beta).squareRoot() / (2 * Double.pi)
            guard (frequency <= top && beta * spacing < Double.pi) || rows.isEmpty else { break }
            let target = decay(frequency)
            if target > 0 {
                rows.append(
                    (
                        Self.felt(beta, spacing).squareRoot(), 2 * Double.pi * frequency, target,
                        1 / (partial * target * target)
                    )
                )
            }
            partial += 1
            if partial > 100_000 { break }
        }
        guard let reach = rows.last?.x, reach > 0 else {
            self.init(steady: .zero, rising: .zero, steep: 0)
            return
        }
        let lags = remembering ? Self.lags(down: rows[0].angular / (2 * Double.pi)) : []
        // WHY: β⁴ spans twelve orders across the band; the columns are taken in β / reach, and each memory part in the
        // decay it gives the top partial, so the normal equations stay well conditioned.
        let top = rows[rows.endIndex - 1]
        func column(_ which: Int, _ row: (x: Double, angular: Double, target: Double, weight: Double)) -> Double {
            let scaled = (row.x / reach) * (row.x / reach)
            switch which {
            case 0: return 1

            case 1: return scaled

            case 2: return scaled * scaled

            default:
                let time = lags[which - 3]
                return scaled * Self.lagging(row.angular, time, interval) / Self.lagging(top.angular, time, interval)
            }
        }
        let columns = 3 + lags.count
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: columns), count: columns)
        var vector = [Double](repeating: 0, count: columns)
        for row in rows {
            for i in 0..<columns {
                let left = column(i, row)
                for j in 0..<columns { matrix[i][j] += row.weight * left * column(j, row) }
                vector[i] += row.weight * left * row.target
            }
        }
        let found = Self.nonnegative(matrix, vector)
        let square = reach * reach
        var memory: [(strength: Double, time: Double)] = []
        for (index, time) in lags.enumerated() where found[3 + index] > 0 {
            memory.append((found[3 + index] / (square * Self.lagging(top.angular, time, interval)), time))
        }
        self.init(
            steady: Decay::Decay.amount(found[0]),
            rising: Viscosity.Kinematic.amount(found[1] / square),
            steep: found[2] / (square * square),
            memory: memory,
            every: interval
        )
    }

    /// Least squares with no coefficient below zero, from its normal equations: Lawson and Hanson's active set.
    static func nonnegative(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        let size = vector.count
        var solution = [Double](repeating: 0, count: size)
        var free = [Bool](repeating: false, count: size)
        func gradient(_ x: [Double]) -> [Double] {
            (0..<size).map { i in vector[i] - (0..<size).reduce(0) { $0 + matrix[i][$1] * x[$1] } }
        }
        func solved(_ set: [Bool]) -> [Double]? {
            let chosen = (0..<size).filter { set[$0] }
            let system = chosen.map { i in chosen.map { matrix[i][$0] } + [vector[i]] }
            guard let part = solve(system) else { return nil }
            var full = [Double](repeating: 0, count: size)
            for (index, which) in chosen.enumerated() { full[which] = part[index] }
            return full
        }
        let scale = (0..<size).reduce(0.0) { Swift.max($0, matrix[$1][$1]) }
        for _ in 0..<(3 * size) {
            let slope = gradient(solution)
            guard
                let entering = (0..<size).filter({ !free[$0] && slope[$0] > 1e-12 * scale * (1 + slope[$0].magnitude) })
                    .max(by: { slope[$0] < slope[$1] })
            else { break }
            free[entering] = true
            var inner = 0
            while inner < 3 * size {
                inner += 1
                guard let trial = solved(free) else {
                    free[entering] = false
                    return solution
                }
                if (0..<size).allSatisfy({ !free[$0] || trial[$0] > 0 }) {
                    solution = trial
                    break
                }
                var step = 1.0
                for i in 0..<size where free[i] && trial[i] <= 0 {
                    step = Swift.min(step, solution[i] / (solution[i] - trial[i]))
                }
                for i in 0..<size { solution[i] += step * (trial[i] - solution[i]) }
                for i in 0..<size where free[i] && solution[i] <= 1e-300 {
                    free[i] = false
                    solution[i] = 0
                }
            }
        }
        return solution.map { Swift.max($0, 0) }
    }

    /// Solves a small augmented system by elimination with partial pivoting; nil when it is singular.
    static func solve(_ system: [[Double]]) -> [Double]? {
        var matrix = system
        let size = matrix.count
        guard size > 0 else { return [] }
        for column in 0..<size {
            guard
                let pivot = (column..<size).max(by: { matrix[$0][column].magnitude < matrix[$1][column].magnitude }),
                matrix[pivot][column].magnitude > 1e-300
            else { return nil }
            matrix.swapAt(column, pivot)
            for row in (column + 1)..<size {
                let factor = matrix[row][column] / matrix[column][column]
                for index in column...size { matrix[row][index] -= factor * matrix[column][index] }
            }
        }
        var solution = [Double](repeating: 0, count: size)
        for row in (0..<size).reversed() {
            var sum = matrix[row][size]
            for index in (row + 1)..<size { sum -= matrix[row][index] * solution[index] }
            solution[row] = sum / matrix[row][row]
        }
        return solution
    }
}
