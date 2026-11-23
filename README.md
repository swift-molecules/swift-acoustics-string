# swift-acoustics-string

Use this package when a sound comes from a stiff string stepped a sample at a time: plucked or stopped by fingers, rattling on a fingerboard, pulling on a body. Start from `Acoustics.String`.

## Laws

- A string is a line of points stepped by finite differences: tension, density and bending stiffness, with the grid's own lowering of its high partials taken out, so a stiff string's partials sound within a cent of the law to 2.3 kHz.
- Without loss a string keeps its energy: released, rattling on a fingerboard, or held by a still fingertip; with loss, friction and a damping fingertip its energy only falls.
- A decay set by two ring times makes the lowest partial fall 60 dB in its time.
- Fingers and the fingerboard press through `Contact` of swift-contact.
