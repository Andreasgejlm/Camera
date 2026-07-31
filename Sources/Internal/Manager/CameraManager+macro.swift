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
    private let macroZoomTolerance: CGFloat = 0.05
    /// Time given to focus and exposure to settle before restoring the requested
    /// zoom when nudging the device out of an already-active macro hand-over.
    private let macroEscapeSettleNanoseconds: UInt64 = 120_000_000
    private weak var observedDevice: AVCaptureDevice?
    private(set) var isAutoMacroModeEnabled: Bool = true

    func setup(parent: CameraManager, device: AVCaptureDevice) {
        stop()
        self.parent = parent
        self.lastIsMacroLike = nil
        self.isAutoMacroModeEnabled = parent.attributes.isAutoMacroModeEnabled
        // Prevent stale UI state while observers are being attached/reconciled.
        parent.attributes.isMacroMode = false
        configureVirtualSwitchingIfSupported(device)

        start(device: device) { [weak parent] isMacroLike in
            parent?.attributes.isMacroMode = isMacroLike
        }
    }

    /// Enables or disables the device's automatic hand-over to the ultra-wide lens
    /// for close-up subjects. Observation stays attached either way, so the state
    /// is reconciled immediately when auto macro is turned back on.
    func setAutoMacroModeEnabled(_ isEnabled: Bool) {
        guard isEnabled != isAutoMacroModeEnabled else { return }
        isAutoMacroModeEnabled = isEnabled

        if let observedDevice { configureVirtualSwitchingIfSupported(observedDevice) }
        scheduleEmit()
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
        guard isAutoMacroModeEnabled else { return false }
        guard let device = observedDevice else { return false }
        return isDeviceInMacroState(device)
    }

    /// Best-effort macro detection: the virtual device has handed over to the
    /// ultra-wide lens while the requested zoom still sits at or above the wide
    /// camera's switch-over point.
    private func isDeviceInMacroState(_ device: AVCaptureDevice) -> Bool {
        guard device.isVirtualDeviceWithUltraWideCamera else { return false }

        guard let activeCamera = device.activePrimaryConstituent,
              let ultraWideCamera = macroVideoDeviceDiscoverySession.backBuiltInUltraWideCamera else {
            return false
        }

        return activeCamera.uniqueID == ultraWideCamera.uniqueID
            && device.videoZoomFactor >= (macroZoomThreshold(for: device) - macroZoomTolerance)
    }

    private func macroZoomThreshold(for device: AVCaptureDevice) -> CGFloat {
        let switchOverThreshold = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 2.0
        return max(2.0, switchOverThreshold)
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

            guard isAutoMacroModeEnabled else {
                // The conditions list names the triggers that are still ALLOWED to pick a
                // fallback constituent, so an empty set is what disables the close-up
                // hand-over to the ultra-wide lens. Passing [.focusModeChanged] here would
                // permit precisely the switch we are trying to suppress, since the app sets
                // focusMode on every tap to focus.
                //
                // Zoom does not need listing: switches required to satisfy the requested
                // video zoom factor stay unrestricted under .restricted, so ordinary lens
                // selection keeps working. Exposure driven low light fallback is given up
                // deliberately — when triggered, fallback selection also weighs focus, which
                // lets a close subject pull the device back into macro.
                device.setPrimaryConstituentDeviceSwitchingBehavior(.restricted, restrictedSwitchingBehaviorConditions: [])
                escapeMacroIfActive(device)
                return
            }

            device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
        } catch {
            // Best effort; macro detection still works via device observation.
        }
    }

    /// Restricting only governs future hand-overs, so a device already sitting on
    /// the ultra-wide lens stays there. The one documented lever back is recrossing
    /// a switch-over zoom factor: dropping below it makes ultra-wide the legitimate
    /// choice for the requested zoom, and returning above it makes the wide camera
    /// eligible again — which it now wins, because fallback selection is restricted.
    /// Best effort: the device only re-selects once focus and exposure settle.
    ///
    /// Must be called with `device` already locked for configuration.
    private func escapeMacroIfActive(_ device: AVCaptureDevice) {
        guard isDeviceInMacroState(device) else { return }

        let restoreZoomFactor = device.videoZoomFactor
        let belowSwitchOver = max(device.minAvailableVideoZoomFactor, macroZoomThreshold(for: device) - 0.1)
        guard belowSwitchOver < restoreZoomFactor else { return }

        device.videoZoomFactor = belowSwitchOver

        let settleDelay = macroEscapeSettleNanoseconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: settleDelay)
            // Bail if the device was swapped out or auto macro was turned back on
            // while we were waiting — either way this nudge is no longer wanted.
            guard let self, self.observedDevice === device, !self.isAutoMacroModeEnabled else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = min(restoreZoomFactor, device.maxAvailableVideoZoomFactor)
            } catch {
                // Best effort; the zoom stays at the nudged value.
            }
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
