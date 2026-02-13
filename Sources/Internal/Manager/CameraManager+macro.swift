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

    private var lastIsMacroLike: Bool?
    private var onChange: ((_ isMacroLike: Bool) -> Void)?
    private var debounceTask: Task<Void, Never>?

    func setup(parent: CameraManager, device: AVCaptureDevice) {
        stop()
        self.parent = parent
        self.lastIsMacroLike = nil
        // Prevent stale UI state while observers are being attached/reconciled.
        parent.attributes.isMacroMode = false
        configureVirtualSwitchingIfSupported(device)

        start(device: device) { [weak parent] isMacroLike in
            parent?.attributes.isMacroMode = isMacroLike
        }
    }

    func start(device: AVCaptureDevice,
               onChange: @escaping (_ isMacroLike: Bool) -> Void) {
        self.onChange = onChange

        func recompute() -> Bool {
            guard device.isVirtualDeviceWithUltraWideCamera else { return false }

            guard let activeCamera = device.activePrimaryConstituent,
                  let ultraWideCamera = macroVideoDeviceDiscoverySession.backBuiltInUltraWideCamera else {
                return false
            }

            let switchOverThreshold = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 2.0
            let zoomThreshold = max(2.0, switchOverThreshold)
            let tolerance: CGFloat = 0.05

            // Best-effort macro detection: virtual device has switched to ultra-wide
            // while virtual zoom remains at/above the wide-camera switch-over point.
            // We intentionally avoid checking ultra-wide's own videoZoomFactor because
            // its value is in a different zoom domain than the virtual camera's.
            return activeCamera.uniqueID == ultraWideCamera.uniqueID
                && device.videoZoomFactor >= (zoomThreshold - tolerance)
        }

        // Compute and apply the initial state immediately (without relying on .initial KVO,
        // which can fire before the session has fully stabilised and cause a spurious flash).
        let initialValue = recompute()
        lastIsMacroLike = initialValue
        onChange(initialValue)

        // Use only .new (not .initial) so the KVO callbacks are only triggered by real
        // device changes, not by the observer registration itself.
        obsActive = device.observe(\.activePrimaryConstituent, options: [.new]) { device, _ in
            Task { @MainActor in
                self.scheduleEmit(recompute())
            }
        }

        obsZoom = device.observe(\.videoZoomFactor, options: [.new]) { device, _ in
            Task { @MainActor in
                self.scheduleEmit(recompute())
            }
        }
    }

    /// Debounces macro-state changes by 500 ms.
    ///
    /// `activePrimaryConstituent` and `videoZoomFactor` are updated independently by
    /// AVFoundation, so a single lens-switch produces two rapid KVO events.  Without
    /// debouncing the observer can emit a spurious intermediate state (e.g. briefly
    /// marking macro=true while the zoom is still settling after a wide→ultra-wide
    /// switch).  The same transient behaviour occurs on startup and during
    /// photo↔video mode changes that trigger a session reconfiguration.
    private func scheduleEmit(_ newValue: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms
            guard !Task.isCancelled else { return }
            guard newValue != lastIsMacroLike else { return }
            lastIsMacroLike = newValue
            onChange?(newValue)
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
        debounceTask?.cancel()
        debounceTask = nil
        obsActive?.invalidate()
        obsZoom?.invalidate()
        obsActive = nil
        obsZoom = nil
        onChange = nil
        lastIsMacroLike = nil
    }
}
