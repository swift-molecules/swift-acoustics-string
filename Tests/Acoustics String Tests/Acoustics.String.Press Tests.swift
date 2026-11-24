import Testing
@testable import Acoustics_String

extension `Acoustics Tests` {
    @Suite struct Press {}
}

extension `Acoustics Tests`.Press {
    /// Two tips stopping the string side by side, so they share a region, and a third drawn across and lifted; the
    /// first held, then slid half a spacing and more, then held again.
    static func played(plain: Bool, steps: Int) -> [[UInt64]] {
        let interval = `Acoustics Tests`.interval
        var string = `Acoustics Tests`.string(
            losses: .gut(diameter: `Acoustics Tests`.metres(0.0009)),
            board: `Acoustics Tests`.board(friction: 0.3, damping: 20)
        )
        string.plain = plain
        let flesh = `Acoustics Tests`.flesh
        let pressed = -(0.0008 + 0.006 * 0.30 / 0.86) + 0.007 - 0.0008
        let stopping = { (place: Double, width: Double) -> Acoustics.String.Finger in
            .init(
                place: `Acoustics Tests`.metres(place),
                width: `Acoustics Tests`.metres(width),
                radius: 0.007,
                centre: .init(up: 0.008),
                contact: flesh,
                friction: 0.8,
                damping: 40
            )
        }
        string.fingers = [
            stopping(0.30, 0.014),
            stopping(0.318, 0.012),
            .init(
                place: 0.86,
                width: 0.014,
                radius: 0.007,
                centre: .init(up: 0.004, across: -0.0085),
                contact: flesh,
                friction: 0.8,
                damping: 10
            ),
        ]
        var shapes: [[UInt64]] = []
        for step in 0..<steps {
            let down = min(Double(step) / 300, 1)
            for finger in 0..<2 {
                string.fingers[finger].centre.up = `Acoustics Tests`.metres(0.008 + (pressed - 0.008) * down)
                string.fingers[finger].speed.up = Velocity.amount(down < 1 ? (pressed - 0.008) / (300 * interval) : 0)
            }
            if step >= 300, step < 600 {
                string.fingers[2].speed.across = 1
                string.fingers[2].centre.across += `Acoustics Tests`.metres(interval)
            } else if step >= 600 {
                string.fingers[2].speed.across = 0
                string.fingers[2].centre.up = 0.05
            }
            if step >= 700, step < 1_000 {
                string.fingers[0].place += `Acoustics Tests`.metres(2 * interval)
            }
            string.advance()
            if step % 50 == 49 {
                shapes.append(string.shape.flatMap { [$0.up.underlying.bitPattern, $0.across.underlying.bitPattern] })
                shapes.append([string.energy.underlying.bitPattern, string.pull.across.underlying.bitPattern])
            }
        }
        return shapes
    }

    /// The presses and regions kept while the tips stay put, each region's matrix laid once, and only the entries
    /// that aren't zero eliminated: the string moves to the same bits as when all of it is done afresh every step.
    @Test func `Kept layouts and matrices and a sparse elimination leave every bit as the plain step's`() {
        let fast = Self.played(plain: false, steps: 1_200)
        let plain = Self.played(plain: true, steps: 1_200)
        #expect(fast.count == plain.count)
        for (index, (one, other)) in zip(fast, plain).enumerated() {
            let same = one == other
            #expect(same, "differs at sample \(index)")
        }
    }
}
