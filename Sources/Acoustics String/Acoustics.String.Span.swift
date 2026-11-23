extension Acoustics.String {
    @usableFromInline
    struct Span: Sendable {
        @usableFromInline var low: Int
        @usableFromInline var high: Int
        @usableFromInline var whole: Double
    }
}
