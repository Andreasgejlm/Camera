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
        setupLongPressGesture(context)
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
    func setupLongPressGesture(_ context: Context) {
        // A long press that is recognised makes the tap fail, so the two
        // never both fire for one touch.
        let longPressRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onLongPressGesture))
        longPressRecognizer.minimumPressDuration = 0.5
        inputView.addGestureRecognizer(longPressRecognizer)
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
    @MainActor @objc func onLongPressGesture(_ longPress: UILongPressGestureRecognizer) {
        guard longPress.state == .began else { return }

        let touchPoint = longPress.location(in: parent.inputView)
        try? parent.cameraManager.lockFocusAndExposure(at: touchPoint)
    }
}

// MARK: On Pan
extension CameraBridgeView.Coordinator: UIGestureRecognizerDelegate {
    /// Drags the exposure sun. Only a vertical drag while the focus square is
    /// on screen starts it, so sideways swipes and other drags in the host
    /// still reach their own gestures.
    @MainActor @objc func onPanGesture(_ pan: UIPanGestureRecognizer) {
        let cameraManager = parent.cameraManager
        switch pan.state {
            case .began: cameraManager.beginExposureAdjustment()
            case .changed: cameraManager.updateExposureAdjustment(translation: pan.translation(in: parent.inputView).y)
            case .ended, .cancelled, .failed: cameraManager.endExposureAdjustment()
            default: break
        }
    }
    @MainActor func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let velocity = pan.velocity(in: parent.inputView)
        return abs(velocity.y) > abs(velocity.x) && parent.cameraManager.canAdjustExposureWithSun
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
