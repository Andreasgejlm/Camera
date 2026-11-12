//
//  CameraManager+PermissionsManager.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

@MainActor class CameraManagerPermissionsManager {}

// MARK: Request Access
extension CameraManagerPermissionsManager {
    /// Asks for the camera. The microphone is not part of this: a camera opened
    /// to take photos has no reason to ask for it, and a refusal must not keep
    /// the camera from opening. It is asked for on request, with
    /// `requestMicrophoneAccess()`.
    func requestAccess(parent: CameraManager) async throws(MCameraError) {
        #if targetEnvironment(simulator)
        // Skip permissions in DEBUG/simulator mode - using mock devices
        print("📷 DEBUG MODE: Skipping camera permissions (using mock devices)")
        return
        #else
        do {
            try await getAuthorizationStatus(for: .video)
        }
        catch {
            parent.attributes.error = error
            throw error
        }
        #endif
    }
}

// MARK: Microphone
extension CameraManagerPermissionsManager {
    /// Whether a mic input may be attached to the session. One is attached only
    /// once access has been granted, so the session never reaches for the
    /// microphone before the person has said yes.
    var isMicrophoneAuthorized: Bool {
        #if targetEnvironment(simulator)
        // Mock devices, as in `requestAccess(parent:)`.
        true
        #else
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }

    /// Shows the system prompt if the person has not answered yet. Returns
    /// whether the microphone may be used.
    func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}
private extension CameraManagerPermissionsManager {
    func getAuthorizationStatus(for mediaType: AVMediaType) async throws(MCameraError) { switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .denied, .restricted: throw getPermissionsError(mediaType)
        case .notDetermined: try await requestAccess(for: mediaType)
        default: return
    }}
}
private extension CameraManagerPermissionsManager {
    func requestAccess(for mediaType: AVMediaType) async throws(MCameraError) {
        let isGranted = await AVCaptureDevice.requestAccess(for: mediaType)
        if !isGranted { throw getPermissionsError(mediaType) }
    }
    func getPermissionsError(_ mediaType: AVMediaType) -> MCameraError { switch mediaType {
        case .audio: .microphonePermissionsNotGranted
        case .video: .cameraPermissionsNotGranted
        default: fatalError()
    }}
}
