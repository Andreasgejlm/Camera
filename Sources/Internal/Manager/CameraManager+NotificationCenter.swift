//
//  CameraManager+NotificationCenter.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit
import Foundation

@MainActor class CameraManagerNotificationCenter {
    private(set) var parent: CameraManager!
}

// MARK: Setup
extension CameraManagerNotificationCenter {
    func setup(parent: CameraManager) {
        self.parent = parent
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: parent.captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
}
private extension CameraManagerNotificationCenter {
    @objc func handleSessionWasInterrupted() {
        parent.attributes.lightMode = .off
        parent.videoOutput.reset()
    }
    @objc func handleSubjectAreaDidChange() {
        parent.resetCameraFocusToContinuousAutoFocus()
    }
}

// MARK: Reset
extension CameraManagerNotificationCenter {
    func reset() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: parent?.captureSession)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
}
