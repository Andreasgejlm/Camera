//
//  CameraView+Bridge.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

struct CameraBridgeView: UIViewRepresentable {
    let cameraManager: CameraManager
    let inputView: UIView = .init()
}
extension CameraBridgeView {
    func makeUIView(context: Context) -> some UIView {
        cameraManager.initialize(in: inputView)
        setupTapGesture(context)
        setupLongPressGestures(context)
        setupPanGesture(context)
        setupPinchGesture(context)
        return inputView
    }
    func updateUIView(_ uiView: UIViewType, context: Context) {}
    /// Called when the camera view leaves the hierarchy for good, unlike
    /// `onDisappear`, which also fires while it is merely covered by a pushed
    /// screen. This is the point where the capture pipeline is released.
    static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {
        coordinator.parent.cameraManager.cancel()
    }
    func makeCoordinator() -> Coordinator { .init(self) }
}
private extension CameraBridgeView {
    func setupTapGesture(_ context: Context) {
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onTapGesture))
        inputView.addGestureRecognizer(tapRecognizer)
    }
    /// Two long presses on the same touch: the first starts the pending
    /// lock (the throbbing square), the second commits it. Lifting or moving
    /// the finger before the second fires leaves a tap to focus. A long press
    /// that is recognised makes the tap fail, so both never fire for one touch.
    func setupLongPressGestures(_ context: Context) {
        let holdRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onHoldGesture))
        holdRecognizer.minimumPressDuration = 0.2
        holdRecognizer.delegate = context.coordinator
        inputView.addGestureRecognizer(holdRecognizer)

        let lockRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onLockGesture))
        lockRecognizer.minimumPressDuration = 0.8
        lockRecognizer.delegate = context.coordinator
        inputView.addGestureRecognizer(lockRecognizer)
    }
    func setupPanGesture(_ context: Context) {
        let panRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onPanGesture))
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.delegate = context.coordinator
        inputView.addGestureRecognizer(panRecognizer)
    }
    func setupPinchGesture(_ context: Context) {
        let pinchRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onPinchGesture))
        inputView.addGestureRecognizer(pinchRecognizer)
    }
}

// MARK: Equatable
extension CameraBridgeView: Equatable {
    nonisolated static func ==(lhs: Self, rhs: Self) -> Bool { true }
}


// MARK: - GESTURES
extension CameraBridgeView { class Coordinator: NSObject { init(_ parent: CameraBridgeView) { self.parent = parent }
    let parent: CameraBridgeView
}}

// MARK: On Tap
extension CameraBridgeView.Coordinator {
    @MainActor @objc func onTapGesture(_ tap: UITapGestureRecognizer) {
        do {
            let touchPoint = tap.location(in: parent.inputView)
            try parent.cameraManager.setCameraFocus(at: touchPoint)
        } catch {}
    }
}

// MARK: On Long Press
extension CameraBridgeView.Coordinator {
    @MainActor @objc func onHoldGesture(_ hold: UILongPressGestureRecognizer) {
        switch hold.state {
            case .began: try? parent.cameraManager.beginFocusExposureLock(at: hold.location(in: parent.inputView))
            case .ended, .cancelled, .failed: parent.cameraManager.cancelPendingFocusExposureLock()
            default: break
        }
    }
    @MainActor @objc func onLockGesture(_ lock: UILongPressGestureRecognizer) {
        guard lock.state == .began else { return }
        parent.cameraManager.commitFocusExposureLock()
    }
}

// MARK: On Pan
extension CameraBridgeView.Coordinator: UIGestureRecognizerDelegate {
    /// Drags the exposure sun. Only a vertical drag that starts on or near
    /// the focus square and its sun starts it, so sideways swipes and drags
    /// elsewhere on the preview still reach the host's own gestures. Once
    /// begun, the drag may leave that area.
    @MainActor @objc func onPanGesture(_ pan: UIPanGestureRecognizer) {
        let cameraManager = parent.cameraManager
        switch pan.state {
            case .began:
                // A finger that rested before dragging started a pending lock;
                // the drag wins, and the square stays where the finger rested.
                cameraManager.cancelPendingFocusExposureLock()
                cameraManager.beginExposureAdjustment()
            case .changed: cameraManager.updateExposureAdjustment(translation: pan.translation(in: parent.inputView).y)
            case .ended, .cancelled, .failed: cameraManager.endExposureAdjustment()
            default: break
        }
    }
    @MainActor func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Off, the long presses stay out of the way so a slow tap still focuses.
        if gestureRecognizer is UILongPressGestureRecognizer { return parent.cameraManager.attributes.isFocusExposureControlsEnabled }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let velocity = pan.velocity(in: parent.inputView)
        // Where the finger went down, not where it is once the drag is recognised.
        let location = pan.location(in: parent.inputView), translation = pan.translation(in: parent.inputView)
        let startPoint = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        return abs(velocity.y) > abs(velocity.x) && parent.cameraManager.canAdjustExposureWithSun(from: startPoint)
    }
    /// The hold and lock presses track the same touch, and the exposure drag
    /// may start after a finger rested long enough to begin a hold. Only this
    /// view's own recognisers are paired; the host's are left alone.
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === parent.inputView, otherGestureRecognizer.view === parent.inputView else { return false }

        let isHoldOrDrag = { (recognizer: UIGestureRecognizer) in recognizer is UILongPressGestureRecognizer || recognizer is UIPanGestureRecognizer }
        guard isHoldOrDrag(gestureRecognizer), isHoldOrDrag(otherGestureRecognizer) else { return false }
        // Two drags never pair; the pinch is neither.
        return gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer
    }
}

extension CameraBridgeView.Coordinator {
    @MainActor @objc func onPinchGesture(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .changed {
            do {
                let currentZoom = parent.cameraManager.attributes.zoomFactor
                
                // Scale sensitivity based on current zoom level
                // The more zoomed in, the faster it responds
                let zoomSensitivity = currentZoom * 0.35
                
                // Calculate zoom delta proportional to both velocity and current zoom
                let zoomDelta = atan2(pinch.velocity, 33) * zoomSensitivity
                
                let desiredZoomFactor = currentZoom + zoomDelta
                try parent.cameraManager.setCameraZoomFactor(desiredZoomFactor)
            } catch {}
        }
    }
}
