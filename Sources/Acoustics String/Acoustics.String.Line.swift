extension Acoustics.String {
    @usableFromInline
    struct Line: Sendable {
        @usableFromInline var now: [Double]
        @usableFromInline var before: [Double]
        @usableFromInline var ahead: [Double]
        @usableFromInline var bend: [Double]
        @usableFromInline var bent: [Double]
        /// The string's memory: for each part in turn, the copy of the line it keeps.
        @usableFromInline var kept: [Double]

        @usableFromInline
        init(_ points: Int, memory parts: Int = 0) {
            now = [Double](repeating: 0, count: points)
            before = now
            ahead = now
            bend = now
            bent = now
            kept = [Double](repeating: 0, count: parts * points)
        }
    }
}

extension Acoustics.String.Line {
    /// Where every point would be one step on with nothing touching it.
    ///
    /// WHY: one pass over spans, each point taking every term in the same order the terms were once added in separate
    /// passes, so the optimizer can step several points at a time and every bit stays as it was.
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
        let points = now.count
        // WHY: the array written is taken out of the line while it is written, so reading the others doesn't overlap.
        var bending: [Double] = []
        swap(&bending, &self.bend)
        do {
            let now = self.now.span
            var bend = bending.mutableSpan
            var index = 1
            while index < last {
                bend[index] = now[index + 1] - 2 * now[index] + now[index - 1]
                index += 1
            }
        }
        swap(&bending, &self.bend)
        var going: [Double] = []
        swap(&going, &self.ahead)
        defer { swap(&going, &self.ahead) }
        let now = self.now.span
        let before = self.before.span
        let bend = self.bend.span
        let bent = self.bent.span
        let kept = self.kept.span
        let pulls = pulls.span
        var ahead = going.mutableSpan
        let parts = pulls.count
        let shared = 1 + steady
        let kept0 = 1 - steady
        var index = 1
        while index < last {
            let curve = bend[index]
            let sharp = bend[index - 1] - 2 * curve + bend[index + 1]
            ahead[index] =
                (2 * now[index] - kept0 * before[index] + wave * curve - stiff * sharp + rise * (curve - bent[index]))
                / shared
            index += 1
        }
        // WHY: each part of the memory pulls the line toward the copy it keeps, as tension pulls it straight.
        var part = 0
        while part < parts {
            let pull = pulls[part]
            let base = part * points
            index = 1
            while index < last {
                let remembered = kept[base + index + 1] - 2 * kept[base + index] + kept[base + index - 1]
                ahead[index] += pull * (bend[index] - remembered) / shared
                index += 1
            }
            part += 1
        }
        guard steep != 0 else { return }
        // WHY: the loss on bending, taken over the last step like `rise`, so the step stays explicit.
        index = 1
        while index < last {
            let sharp = bend[index - 1] - 2 * bend[index] + bend[index + 1]
            let sharpened = bent[index - 1] - 2 * bent[index] + bent[index + 1]
            ahead[index] -= steep * (sharp - sharpened) / shared
            index += 1
        }
    }

    @usableFromInline
    mutating func turn(end: Double, follows: [Double] = []) {
        ahead[ahead.endIndex - 1] = end
        swap(&before, &now)
        swap(&now, &ahead)
        swap(&bent, &bend)
        guard !follows.isEmpty else { return }
        let points = now.count
        var keeping: [Double] = []
        swap(&keeping, &kept)
        defer { swap(&keeping, &kept) }
        let now = self.now.span
        var kept = keeping.mutableSpan
        var part = 0
        while part < follows.count {
            let follow = follows[part]
            let base = part * points
            var index = 0
            while index < points {
                kept[base + index] += follow * (now[index] - kept[base + index])
                index += 1
            }
            part += 1
        }
    }
}
