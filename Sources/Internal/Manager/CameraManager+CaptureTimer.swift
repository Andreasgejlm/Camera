//
//  CameraManager+CaptureTimer.swift of MijickCamera
//
//  The self-timer. Only the shutter (captureOutput) counts down: a photo, or
//  the start of a recording in video mode. startRecording(), which the host
//  uses for a long-press video, starts at once, as in the Camera app.


import Foundation

extension CameraManager {
    func setCaptureTimer(_ timer: CameraTimer) {
        guard timer != attributes.captureTimer else { return }

        attributes.captureTimer = timer
        cancelCaptureCountdown()
    }
    var isCaptureCountdownRunning: Bool { captureCountdownTask != nil }

    /// Publishes the seconds left in `attributes.captureCountdown`, from the
    /// timer's length down to 1, then clears it and runs the action.
    func startCaptureCountdown(then action: @escaping @MainActor () -> ()) {
        let seconds = attributes.captureTimer.seconds
        guard seconds > 0 else { return action() }

        cancelCaptureCountdown()
        attributes.captureCountdown = seconds
        let tick = captureCountdownTickInterval
        captureCountdownTask = Task { @MainActor [weak self] in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(tick))
                guard !Task.isCancelled, let self else { return }
                if remaining > 0 { self.attributes.captureCountdown = remaining }
            }
            guard let self else { return }
            self.captureCountdownTask = nil
            self.attributes.captureCountdown = nil
            action()
        }
    }
    /// Stops a countdown without capturing. Does nothing when none is running.
    func cancelCaptureCountdown() {
        captureCountdownTask?.cancel()
        captureCountdownTask = nil
        if attributes.captureCountdown != nil { attributes.captureCountdown = nil }
    }
}
