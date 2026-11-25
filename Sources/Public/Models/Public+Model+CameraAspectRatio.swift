//
//  Public+Model+CameraAspectRatio.swift of MijickCamera
//


import CoreGraphics

/// The shape photos are cropped to, as the Format option in the Camera app.
///
/// Ratios are long side to short side, so `.sixteenByNine` is 16:9 in landscape
/// and 9:16 in portrait. Photos are cropped from the centre. Videos are never
/// cropped.
public enum CameraAspectRatio: CaseIterable, Sendable {
    case fourByThree
    case sixteenByNine
    case square

    /// Long side divided by short side.
    public var longToShortRatio: CGFloat { switch self {
        case .fourByThree: 4 / 3
        case .sixteenByNine: 16 / 9
        case .square: 1
    }}
}
