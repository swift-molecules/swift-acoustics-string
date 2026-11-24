internal import Numeric

extension Acoustics.String {
    /// The losses the grid steps with: a decay every partial shares, one that grows with the wavenumber squared and
    /// one that grows with its fourth power. A partial of wavenumber β decays at `steady + rising β² + steep β⁴`.
    ///
    /// None may be negative: a negative loss feeds the grid's highest partials, and the string blows up.
    @usableFromInline
    struct Damping: Sendable {
        @usableFromInline let steady: Decay::Decay.Value<Double>
        @usableFromInline let rising: Viscosity.Kinematic.Value<Double>
        /// In m⁴/s. No atom holds this kind, so it is a scalar.
        @usableFromInline let steep: Double

        @usableFromInline
        init(steady: Decay::Decay.Value<Double>, rising: Viscosity.Kinematic.Value<Double>, steep: Double) {
            precondition(
                steady >= .zero && rising >= .zero && steep >= 0,
                "A string's losses can't be negative: a negative loss feeds energy in and the grid blows up."
            )
            self.steady = steady
            self.rising = rising
            self.steep = steep
        }

        /// The decay of a partial of wavenumber `beta` on a grid of this spacing, in 1/s: the grid's second difference
        /// sees β² as (2/h · sin(βh/2))².
        @usableFromInline
        func decay(_ beta: Double, spacing: Double) -> Double {
            let square = Self.felt(beta, spacing)
            return steady.underlying + rising.underlying * square + steep * square * square
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
    /// The grid's closest match to a law that gives each partial its own decay.
    ///
    /// The partials are those of the stiff string up to `top`, as a grid of `spacing` holds them (zero for the
    /// continuous string). Each one's decay is matched in proportion to itself, and each octave counts alike, by least
    /// squares with no coefficient below zero.
    init(
        matching decay: (_ frequency: Double) -> Double,
        length: Double,
        speed: Double,
        bending: Double,
        top: Double,
        spacing: Double = 0
    ) {
        var rows: [(x: Double, target: Double, weight: Double)] = []
        var partial = 1.0
        while true {
            let beta = partial * Double.pi / length
            let frequency = (speed * beta * beta + bending * beta * beta * beta * beta).squareRoot() / (2 * Double.pi)
            guard (frequency <= top && beta * spacing < Double.pi) || rows.isEmpty else { break }
            let target = decay(frequency)
            if target > 0 { rows.append((Self.felt(beta, spacing).squareRoot(), target, 1 / (partial * target * target))) }
            partial += 1
            if partial > 100_000 { break }
        }
        guard let reach = rows.last?.x, reach > 0 else {
            self.init(steady: .zero, rising: .zero, steep: 0)
            return
        }
        // WHY: β⁴ spans twelve orders across the band; the columns are taken in β / reach so the normal equations stay
        // well conditioned.
        func column(_ which: Int, _ x: Double) -> Double {
            let scaled = (x / reach) * (x / reach)
            return which == 0 ? 1 : which == 1 ? scaled : scaled * scaled
        }
        var best: (residual: Double, coefficients: [Double])?
        for mask in 1..<8 {
            let free = (0..<3).filter { mask & (1 << $0) != 0 }
            var matrix = [[Double]](repeating: [Double](repeating: 0, count: free.count + 1), count: free.count)
            for row in rows {
                for (i, a) in free.enumerated() {
                    let left = column(a, row.x)
                    for (j, b) in free.enumerated() { matrix[i][j] += row.weight * left * column(b, row.x) }
                    matrix[i][free.count] += row.weight * left * row.target
                }
            }
            guard let solved = Self.solve(matrix), solved.allSatisfy({ $0 >= 0 }) else { continue }
            var coefficients = [0.0, 0, 0]
            for (i, a) in free.enumerated() { coefficients[a] = solved[i] }
            var residual = 0.0
            for row in rows {
                let model = (0..<3).reduce(0) { $0 + coefficients[$1] * column($1, row.x) }
                residual += row.weight * (model - row.target) * (model - row.target)
            }
            if best.map({ residual < $0.residual }) ?? true { best = (residual, coefficients) }
        }
        let found = best?.coefficients ?? [0, 0, 0]
        let square = reach * reach
        self.init(
            steady: Decay::Decay.amount(found[0]),
            rising: Viscosity.Kinematic.amount(found[1] / square),
            steep: found[2] / (square * square)
        )
    }

    /// Solves a small augmented system by elimination with partial pivoting; nil when it is singular.
    static func solve(_ system: [[Double]]) -> [Double]? {
        var matrix = system
        let size = matrix.count
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
