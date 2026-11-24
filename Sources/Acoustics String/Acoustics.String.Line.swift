extension Acoustics.String {
    @usableFromInline
    struct Line: Sendable {
        @usableFromInline var now: [Double]
        @usableFromInline var before: [Double]
        @usableFromInline var ahead: [Double]
        @usableFromInline var bend: [Double]
        @usableFromInline var bent: [Double]

        @usableFromInline
        init(_ points: Int) {
            now = [Double](repeating: 0, count: points)
            before = now
            ahead = now
            bend = now
            bent = now
        }
    }
}

extension Acoustics.String.Line {
    /// Where every point would be one step on with nothing touching it.
    @usableFromInline
    mutating func coast(wave: Double, stiff: Double, rise: Double, steady: Double, steep: Double) {
        let last = now.endIndex - 1
        var index = 1
        while index < last {
            bend[index] = now[index + 1] - 2 * now[index] + now[index - 1]
            index += 1
        }
        index = 1
        while index < last {
            let curve = bend[index]
            let sharp = bend[index - 1] - 2 * curve + bend[index + 1]
            ahead[index] =
                (2 * now[index] - (1 - steady) * before[index] + wave * curve - stiff * sharp
                    + rise * (curve - bent[index])) / (1 + steady)
            index += 1
        }
        guard steep != 0 else { return }
        // WHY: the loss on bending, taken over the last step like `rise`, so the step stays explicit.
        index = 1
        while index < last {
            let sharp = bend[index - 1] - 2 * bend[index] + bend[index + 1]
            let sharpened = bent[index - 1] - 2 * bent[index] + bent[index + 1]
            ahead[index] -= steep * (sharp - sharpened) / (1 + steady)
            index += 1
        }
    }

    @usableFromInline
    mutating func turn(end: Double) {
        ahead[ahead.endIndex - 1] = end
        swap(&before, &now)
        swap(&now, &ahead)
        swap(&bent, &bend)
    }
}
