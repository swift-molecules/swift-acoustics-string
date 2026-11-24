# swift-acoustics-string

Use this package when a sound comes from a stiff string stepped a sample at a time: plucked or stopped by fingers, rattling on a fingerboard, pulling on a body. Start from `Acoustics.String`.

## Laws

- A string is a line of points stepped by finite differences: tension, density and bending stiffness, with the grid's own lowering of its high partials taken out, so a stiff string's partials sound within a cent of the law to 2.3 kHz.
- Without loss a string keeps its energy: released, rattling on a fingerboard, or held by a still fingertip; with loss, friction and a damping fingertip its energy only falls.
- A decay set by two ring times makes the lowest partial fall 60 dB in its time.
- Fingers and the fingerboard press through `Contact` of swift-contact.
- Every stored value, parameter and result is a quantity: lengths and places are lengths of `Space.Physical`, the tension a `Force`, the density a `Density.Linear`, the bending stiffness a `Rigidity.Flexural`, the steady decay a `Decay` and the rising one a `Viscosity.Kinematic` (it damps a partial by itself times its wavenumber squared). `Offset<Kind>` is an amount of one kind in the plane across the string: a place, a speed or a force. The fingertip's and the board's `damping`, in s/m, is a scalar, since no atom holds its kind yet.
- The board's `contact` is its push on one metre of string.
