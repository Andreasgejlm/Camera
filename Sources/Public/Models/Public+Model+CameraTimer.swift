//
//  Public+Model+CameraTimer.swift of MijickCamera
//


/// The self-timer, as the Timer option in the Camera app: the shutter counts
/// down before it takes the photo or starts the recording.
public enum CameraTimer: CaseIterable, Sendable {
    case off
    case threeSeconds
    case fiveSeconds
    case tenSeconds

    public var seconds: Int { switch self {
        case .off: 0
        case .threeSeconds: 3
        case .fiveSeconds: 5
        case .tenSeconds: 10
    }}
}
