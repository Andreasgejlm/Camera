//
//  SimulatorCamera.swift of MijickCamera
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVFoundation

/// The simulator has no camera, so MijickCamera runs on mock devices there.
/// When a virtual camera is present instead (such as one Viewfinder installs),
/// the simulator takes the same path as a device.
enum SimulatorCamera {
    /// True only in a simulator that has no camera at all.
    static let usesMock: Bool = {
        #if targetEnvironment(simulator)
        return AVCaptureDevice.default(for: .video) == nil
        #else
        return false
        #endif
    }()
}
