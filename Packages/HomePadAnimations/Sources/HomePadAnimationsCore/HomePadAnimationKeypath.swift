/// Lottie keypaths for recoloring the bundled animations. Every stroke and fill in the animation
/// files is named after its role, so one wildcard keypath reaches all parts with that role.
public enum HomePadAnimationKeypath {
    /// Name of the strokes and fills that take the accent color.
    public static let tintName = "Tint"

    /// Name of the strokes and fills that draw the neutral outline. White in the files.
    public static let inkName = "Ink"

    /// Color of every part that takes the accent color.
    public static let tintColor = "**.Tint.Color"

    /// Color of every neutral outline part.
    public static let inkColor = "**.Ink.Color"
}
