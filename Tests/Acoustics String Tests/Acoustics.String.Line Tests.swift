import Testing
@testable import Acoustics_String

extension `Acoustics Tests` {
    @Suite struct Line {}
}

extension `Acoustics Tests`.Line {
    /// The step as plain separate passes over the points: the line before it was taken in spans.
    static func plain(
        _ line: Acoustics.String.Line,
        wave: Double,
        stiff: Double,
        rise: Double,
        steady: Double,
        steep: Double,
        pulls: [Double]
    ) -> [Double] {
        let last = line.now.endIndex - 1
        var bend = line.bend
        var ahead = line.ahead
        for index in 1..<last { bend[index] = line.now[index + 1] - 2 * line.now[index] + line.now[index - 1] }
        for index in 1..<last {
            let curve = bend[index]
            let sharp = bend[index - 1] - 2 * curve + bend[index + 1]
            ahead[index] =
                (2 * line.now[index] - (1 - steady) * line.before[index] + wave * curve - stiff * sharp
                    + rise * (curve - line.bent[index])) / (1 + steady)
        }
        for part in pulls.indices {
            let base = part * line.now.count
            for index in 1..<last {
                let remembered = line.kept[base + index + 1] - 2 * line.kept[base + index] + line.kept[base + index - 1]
                ahead[index] += pulls[part] * (bend[index] - remembered) / (1 + steady)
            }
        }
        for index in 1..<last {
            let sharp = bend[index - 1] - 2 * bend[index] + bend[index + 1]
            let sharpened = line.bent[index - 1] - 2 * line.bent[index] + line.bent[index + 1]
            ahead[index] -= steep * (sharp - sharpened) / (1 + steady)
        }
        return ahead
    }

    @Test func `A line steps every point to the same bits as plain passes over its points`() {
        var generator = SystemRandomNumberGenerator()
        let points = 237
        let pulls = [0.013, 0.0021, 0.00047]
        var line = Acoustics.String.Line(points, memory: pulls.count)
        func draw() -> Double { Double.random(in: -1e-3...1e-3, using: &generator) }
        for index in 1..<(points - 1) {
            line.now[index] = draw()
            line.before[index] = draw()
            line.bent[index] = draw()
        }
        for index in line.kept.indices { line.kept[index] = draw() }
        let wanted = Self.plain(line, wave: 0.82, stiff: 0.031, rise: 0.0007, steady: 3e-6, steep: 2e-5, pulls: pulls)
        line.coast(wave: 0.82, stiff: 0.031, rise: 0.0007, steady: 3e-6, steep: 2e-5, pulls: pulls)
        #expect(line.ahead == wanted)
    }
}
