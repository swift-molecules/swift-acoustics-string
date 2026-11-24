extension Acoustics.String {
    @usableFromInline
    struct Line: Sendable {
        @usableFromInline var now: [Double]
        @usableFromInline var before: [Double]
        @usableFromInline var ahead: [Double]
        @usableFromInline var bend: [Double]
        @usableFromInline var bent: [Double]
        /// The string's memory: for each part, the copy of the line it keeps.
        @usableFromInline var kept: [[Double]]

        @usableFromInline
        init(_ points: Int, memory parts: Int = 0) {
            now = [Double](repeating: 0, count: points)
            before = now
            ahead = now
            bend = now
            bent = now
            kept = [[Double]](repeating: now, count: parts)
        }
    }
}

extension Acoustics.String.Line {
    /// Where every point would be one step on with nothing touching it.
    @usableFromInline
    mutating func coast(
        wave: Double,
        stiff: Double,
        rise: Double,
        steady: Double,
        steep: Double,
        pulls: [Double] = []
    ) {
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
        // WHY: each part of the memory pulls the line toward the copy it keeps, as tension pulls it straight.
        for part in kept.indices {
            let pull = pulls[part]
            index = 1
            while index < last {
                let curve = bend[index]
                let remembered = kept[part][index + 1] - 2 * kept[part][index] + kept[part][index - 1]
                ahead[index] += pull * (curve - remembered) / (1 + steady)
                index += 1
            }
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
    mutating func turn(end: Double, follows: [Double] = []) {
        ahead[ahead.endIndex - 1] = end
        swap(&before, &now)
        swap(&now, &ahead)
        swap(&bent, &bend)
        for part in kept.indices {
            let follow = follows[part]
            for index in now.indices { kept[part][index] += follow * (now[index] - kept[part][index]) }
        }
    }
}
