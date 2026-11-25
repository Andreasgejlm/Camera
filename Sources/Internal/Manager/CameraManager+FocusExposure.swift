//
//  CameraManager+FocusExposure.swift of MijickCamera
//
//  Tap to focus, focus & exposure lock (AE/AF Lock), and the exposure bias,
//  including the temporary change made by dragging the exposure sun.


import AVKit

// MARK: Tap To Focus
extension CameraManager {
    /// Focuses and exposes once at the tapped point. A later change of scene
    /// hands control back to continuous autofocus (see
    /// `resetCameraFocusToContinuousAutoFocus()`). Ends a focus & exposure lock.
    func setCameraFocus(at touchPoint: CGPoint) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        let focusPoint = convertTouchPointToFocusPoint(touchPoint)
        exposureBiasOffset = 0
        try device.lockForConfiguration()
        device.setFocusPointOfInterest(focusPoint)
        device.setExposurePointOfInterest(focusPoint)
        device.isSubjectAreaChangeMonitoringEnabled = true
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()

        if attributes.isFocusExposureLocked { attributes.isFocusExposureLocked = false }
        cameraMetalView.showFocusIndicator(at: touchPoint, isLocked: false, showsExposureControl: attributes.isFocusExposureControlsEnabled)
    }
}

// MARK: Focus & Exposure Lock
extension CameraManager {
    /// AE/AF Lock, as a long press in the Camera app. `.autoFocus` and
    /// `.autoExpose` adjust once at the point and then hold, and with
    /// subject-area monitoring off nothing hands control back to continuous
    /// autofocus until the next tap.
    func lockFocusAndExposure(at touchPoint: CGPoint) throws {
        guard attributes.isFocusExposureControlsEnabled, let device = getCameraInput()?.device, !isChanging else { return }

        let focusPoint = convertTouchPointToFocusPoint(touchPoint)
        exposureBiasOffset = 0
        try device.lockForConfiguration()
        device.setFocusPointOfInterest(focusPoint)
        device.setExposurePointOfInterest(focusPoint)
        device.isSubjectAreaChangeMonitoringEnabled = false
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()

        attributes.isFocusExposureLocked = true
        cameraMetalView.showFocusIndicator(at: touchPoint, isLocked: true, showsExposureControl: true)
    }
    /// Ends a focus & exposure lock and returns to continuous autofocus and
    /// autoexposure, dropping any exposure change made with the sun.
    func releaseFocusExposureLock() {
        guard attributes.isFocusExposureLocked else { return }

        attributes.isFocusExposureLocked = false
        exposureBiasOffset = 0
        cameraMetalView.hideFocusIndicator()
        guard let device = getCameraInput()?.device, (try? device.lockForConfiguration()) != nil else { return }
        device.resetFocusToContinuousAutoFocus()
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()
    }
    func setFocusExposureControlsEnabled(_ isEnabled: Bool) {
        guard isEnabled != attributes.isFocusExposureControlsEnabled else { return }

        attributes.isFocusExposureControlsEnabled = isEnabled
        if !isEnabled { releaseFocusExposureLock() }
    }
}

// MARK: Reset Camera Focus
extension CameraManager {
    /// Called when the scene changes after a tap to focus. Does nothing while
    /// focus and exposure are locked, since monitoring is off then.
    func resetCameraFocusToContinuousAutoFocus() {
        guard let device = getCameraInput()?.device, device.isSubjectAreaChangeMonitoringEnabled else { return }
        // The user is dragging the exposure sun; the scene change is theirs.
        guard !cameraMetalView.isAdjustingExposure else { return }

        exposureBiasOffset = 0
        try? device.lockForConfiguration()
        device.resetFocusToContinuousAutoFocus()
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()
    }
}

// MARK: Exposure Target Bias
extension CameraManager {
    /// Sets the lasting exposure bias. The sun's temporary change, if any, is
    /// kept on top of it.
    func setExposureTargetBias(_ exposureTargetBias: Float) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        let bias = device.clampedExposureTargetBias(exposureTargetBias)
        guard bias != attributes.cameraExposure.targetBias else { return }

        try device.lockForConfiguration()
        attributes.cameraExposure.targetBias = bias
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()
    }
    /// Writes the lasting bias plus the sun's change to the device. The
    /// caller holds the device's configuration lock.
    func applyExposureTargetBias(to device: any CaptureDevice) {
        device.setExposureTargetBias(attributes.cameraExposure.targetBias + exposureBiasOffset)
    }
}

// MARK: Exposure Sun
extension CameraManager {
    /// How far the sun can move the exposure either way, in EV.
    static let maxExposureBiasOffset: Float = 2
    /// Vertical drag distance that changes the exposure by one EV.
    static let exposureDragPointsPerEV: CGFloat = 120

    /// The sun can be dragged while the focus square is on screen.
    var canAdjustExposureWithSun: Bool {
        attributes.isFocusExposureControlsEnabled && cameraMetalView.isFocusIndicatorVisible && !isChanging
    }
    func beginExposureAdjustment() {
        exposureBiasOffsetAtDragStart = exposureBiasOffset
        cameraMetalView.beginExposureAdjustment()
    }
    /// - Parameter translation: Vertical drag distance since the drag began, in points; upwards is negative and brightens.
    func updateExposureAdjustment(translation: CGFloat) {
        let change = Float(-translation / Self.exposureDragPointsPerEV)
        let offset = max(-Self.maxExposureBiasOffset, min(Self.maxExposureBiasOffset, exposureBiasOffsetAtDragStart + change))
        setExposureBiasOffset(offset)
    }
    func endExposureAdjustment() {
        cameraMetalView.endExposureAdjustment()
    }
}
private extension CameraManager {
    func setExposureBiasOffset(_ offset: Float) {
        guard offset != exposureBiasOffset, let device = getCameraInput()?.device, (try? device.lockForConfiguration()) != nil else { return }

        exposureBiasOffset = offset
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()
        cameraMetalView.setExposureIndicatorFraction(CGFloat(offset / Self.maxExposureBiasOffset))
    }
}

// MARK: Touch Point Conversion
extension CameraManager {
    func convertTouchPointToFocusPoint(_ touchPoint: CGPoint) -> CGPoint { .init(
        x: touchPoint.y / cameraView.frame.height,
        y: 1 - touchPoint.x / cameraView.frame.width
    )}
}
