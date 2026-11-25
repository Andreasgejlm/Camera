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
        isFocusExposureLockPending = false
        cameraMetalView.showFocusIndicator(at: touchPoint, state: .focused, showsExposureControl: attributes.isFocusExposureControlsEnabled)
    }
}

// MARK: Focus & Exposure Lock
extension CameraManager {
    /// AE/AF Lock, as a long press in the Camera app, in two parts. Holding
    /// the preview first focuses and exposes at the point while the square
    /// throbs; holding on commits the lock, and letting go earlier leaves an
    /// ordinary tap to focus. `.autoFocus` and `.autoExpose` adjust once and
    /// then hold, and with subject-area monitoring off nothing hands control
    /// back to continuous autofocus until the next tap.
    func beginFocusExposureLock(at touchPoint: CGPoint) throws {
        guard attributes.isFocusExposureControlsEnabled, let device = getCameraInput()?.device, !isChanging else { return }

        let focusPoint = convertTouchPointToFocusPoint(touchPoint)
        exposureBiasOffset = 0
        try device.lockForConfiguration()
        device.setFocusPointOfInterest(focusPoint)
        device.setExposurePointOfInterest(focusPoint)
        // Off already while held, so a change of scene can't pull focus away.
        device.isSubjectAreaChangeMonitoringEnabled = false
        applyExposureTargetBias(to: device)
        device.unlockForConfiguration()

        // A new hold replaces an earlier lock.
        if attributes.isFocusExposureLocked { attributes.isFocusExposureLocked = false }
        isFocusExposureLockPending = true
        cameraMetalView.showFocusIndicator(at: touchPoint, state: .pendingLock, showsExposureControl: true)
    }
    func commitFocusExposureLock() {
        guard isFocusExposureLockPending else { return }

        isFocusExposureLockPending = false
        attributes.isFocusExposureLocked = true
        cameraMetalView.commitFocusLock()
    }
    /// Let go before the lock took: what is left is a tap to focus.
    func cancelPendingFocusExposureLock() {
        guard isFocusExposureLockPending else { return }

        isFocusExposureLockPending = false
        if let device = getCameraInput()?.device, (try? device.lockForConfiguration()) != nil {
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
        cameraMetalView.cancelPendingFocusLock()
    }
    func lockFocusAndExposure(at touchPoint: CGPoint) throws {
        try beginFocusExposureLock(at: touchPoint)
        commitFocusExposureLock()
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
        if !isEnabled { cancelPendingFocusExposureLock(); releaseFocusExposureLock() }
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
    func convertTouchPointToFocusPoint(_ touchPoint: CGPoint) -> CGPoint {
        Self.focusPoint(for: touchPoint, viewSize: cameraView.frame.size, frameSize: cameraMetalView.currentFrame?.extent.size)
    }
    /// The preview fills its view from the centre and cuts off what doesn't
    /// fit, more so when the host gives it a 1:1 or 16:9 frame. The touch is
    /// placed on the whole camera frame before it becomes a device point
    /// (0 to 1, in the sensor's landscape orientation). Without a frame yet,
    /// the view is taken to show all of it.
    nonisolated static func focusPoint(for touchPoint: CGPoint, viewSize: CGSize, frameSize: CGSize?) -> CGPoint {
        var displayedSize = viewSize
        var origin = CGPoint.zero
        if let frameSize, frameSize.width > 0, frameSize.height > 0 {
            let scale = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
            displayedSize = .init(width: frameSize.width * scale, height: frameSize.height * scale)
            origin = .init(x: (viewSize.width - displayedSize.width) / 2, y: (viewSize.height - displayedSize.height) / 2)
        }

        let x = (touchPoint.x - origin.x) / displayedSize.width
        let y = (touchPoint.y - origin.y) / displayedSize.height
        return .init(x: y, y: 1 - x)
    }
}
