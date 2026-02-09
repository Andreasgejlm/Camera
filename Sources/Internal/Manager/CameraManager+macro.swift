//
//  CameraManager+macro.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVFoundation

@MainActor final class MacroStateObserver {
    private(set) weak var parent: CameraManager?
    private var obsActive: NSKeyValueObservation?
    private var obsZoom: NSKeyValueObservation?
    private let macroVideoDeviceDiscoverySession: AVCaptureDevice.DiscoverySession = {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInUltraWideCamera
        ]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
    }()

    private var lastIsMacroLike: Bool = false

    func setup(parent: CameraManager, device: AVCaptureDevice) {
        stop()
        self.parent = parent
        self.lastIsMacroLike = false
        configureVirtualSwitchingIfSupported(device)

        start(device: device) { [weak parent] isMacroLike in
            parent?.attributes.isMacroMode = isMacroLike
        }
    }

    func start(device: AVCaptureDevice,
               onChange: @escaping (_ isMacroLike: Bool) -> Void) {

        func recomputeAndEmit() {
            guard device.isVirtualDeviceWithUltraWideCamera else {
                emitIfChanged(false)
                return
            }

            guard let activeCamera = device.activePrimaryConstituent,
                  let ultraWideCamera = macroVideoDeviceDiscoverySession.backBuiltInUltraWideCamera else {
                emitIfChanged(false)
                return
            }

            let switchOverThreshold = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 2.0
            let zoomThreshold = max(2.0, switchOverThreshold)
            let tolerance: CGFloat = 0.05

            // Best-effort macro detection: virtual device has switched to ultra-wide
            // while virtual zoom remains at/above the wide-camera switch-over point.
            // We intentionally avoid checking ultra-wide's own videoZoomFactor because
            // its value is in a different zoom domain than the virtual camera's.
            let isMacroLike = activeCamera.uniqueID == ultraWideCamera.uniqueID
            && device.videoZoomFactor >= (zoomThreshold - tolerance)

            emitIfChanged(isMacroLike)
        }

        func emitIfChanged(_ newValue: Bool) {
            guard newValue != lastIsMacroLike else { return }
            lastIsMacroLike = newValue
            onChange(newValue)
        }

        obsActive = device.observe(\.activePrimaryConstituent, options: [.initial, .new]) { device, change in
            Task { @MainActor in
                recomputeAndEmit()
            }
        }

        obsZoom = device.observe(\.videoZoomFactor, options: [.initial, .new]) { device, change in
            Task { @MainActor in
                recomputeAndEmit()
            }
        }
    }
    
    private func configureVirtualSwitchingIfSupported(_ device: AVCaptureDevice) {
        guard device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else { return }
        
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
        } catch {
            // Best effort; macro detection still works via device observation.
        }
    }

    func stop() {
        obsActive?.invalidate()
        obsZoom?.invalidate()
        obsActive = nil
        obsZoom = nil
        lastIsMacroLike = false
    }
}
