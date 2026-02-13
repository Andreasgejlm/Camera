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
    private let macroOnDebounceNanoseconds: UInt64 = 700_000_000
    private weak var observedDevice: AVCaptureDevice?

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
        self.observedDevice = device

        // Keep startup state deterministic; allow macro=true only after explicit confirmation.
        lastIsMacroLike = false
        onChange(false)

        // Use only .new (not .initial) so the KVO callbacks are only triggered by real
        // device changes, not by the observer registration itself.
        obsActive = device.observe(\.activePrimaryConstituent, options: [.new]) { _, _ in
            Task { @MainActor in
                self.scheduleEmit()
            }
        }

        obsZoom = device.observe(\.videoZoomFactor, options: [.new]) { _, _ in
            Task { @MainActor in
                self.scheduleEmit()
            }
        }

        // Trigger an initial reconciliation pass once observers are installed.
        scheduleEmit()
    }

    /// Debounces macro=true so startup/lens-switch transients do not flash in UI.
    private func scheduleEmit() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            let candidate = self.recomputeIsMacroLike()
            if candidate {
                try? await Task.sleep(nanoseconds: macroOnDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            // Confirm using a fresh read to avoid emitting stale values.
            let confirmed = self.recomputeIsMacroLike()
            emitIfChanged(confirmed)
        }
    }
    private func recomputeIsMacroLike() -> Bool {
        guard let device = observedDevice else { return false }
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
        return activeCamera.uniqueID == ultraWideCamera.uniqueID
            && device.videoZoomFactor >= (zoomThreshold - tolerance)
    }
    private func emitIfChanged(_ value: Bool) {
        guard value != lastIsMacroLike else { return }
        lastIsMacroLike = value
        onChange?(value)
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
        observedDevice = nil
        lastIsMacroLike = nil
    }
}
