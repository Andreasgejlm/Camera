//
//  Tests+CameraManager.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import Testing
import SwiftUI
import AVKit
@testable import MijickCamera

@MainActor @Suite("Camera Manager Tests") struct CameraManagerTests {
    var cameraManager: CameraManager = .init(
        captureSession: MockCaptureSession(),
        captureDeviceInputType: MockDeviceInput.self
    )
}

// MARK: Setup
extension CameraManagerTests {
    @Test("Setup: Waits For The Camera View") func setupWaitsForCameraView() async throws {
        // `onAppear` can start setup before SwiftUI has made the camera view.
        let setup = Task { try await cameraManager.setup() }
        await Task.sleep(seconds: 0.3)
        #expect(cameraManager.captureSession.outputs.isEmpty)

        cameraManager.initialize(in: UIView(frame: .init(origin: .zero, size: .init(width: 1000, height: 1000))))
        try await setup.value
        #expect(cameraManager.captureSession.outputs.isEmpty == false)
        #expect(cameraManager.cameraGridView.parent != nil)
    }
    @Test("Setup: Cancel Releases A Setup Waiting For The View") func cancelReleasesWaitingSetup() async throws {
        let setup = Task { try await cameraManager.setup() }
        await Task.sleep(seconds: 0.3)

        cameraManager.cancel()
        try await setup.value
        #expect(cameraManager.captureSession.outputs.isEmpty)
    }
    @Test("Setup: Default Attributes") func setupWithDefaultAttributes() async throws {
        try await setupCamera()

        #expect(cameraManager.captureSession.isRunning == true)
        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(cameraManager.photoOutput.parent != nil)
        #expect(cameraManager.videoOutput.parent != nil)
        #expect(cameraManager.captureSession.outputs.count == 3)
        #expect(cameraManager.cameraView != nil)
        #expect(cameraManager.cameraLayer.isHidden == true)
        #expect(cameraManager.cameraMetalView.parent != nil)
        #expect(cameraManager.cameraGridView.parent != nil)
        #expect(cameraManager.motionManager.manager.accelerometerUpdateInterval > 0)
        #expect(cameraManager.notificationCenterManager.parent != nil)
        #expect(cameraManager.attributes.photoCaptureMode == .still)
    }
    @Test("Setup: Custom Attributes") func setupWithCustomAttributes() async throws {
        cameraManager.attributes.cameraPosition = .front
        cameraManager.attributes.zoomFactor = 2137
        cameraManager.attributes.lightMode = .on
        cameraManager.attributes.resolution = .hd1280x720
        cameraManager.attributes.frameRate = 666
        cameraManager.attributes.cameraExposure.duration = .init(value: 1, timescale: 10)
        cameraManager.attributes.cameraExposure.targetBias = 0.66
        cameraManager.attributes.cameraExposure.iso = 2000
        cameraManager.attributes.cameraExposure.mode = .custom
        cameraManager.attributes.hdrMode = .off
        cameraManager.attributes.isGridVisible = false

        try await setupCamera()

        #expect(currentDevice.uniqueID == cameraManager.frontCameraInput?.device.uniqueID)
        #expect(currentDevice.videoZoomFactor == currentDevice.maxAvailableVideoZoomFactor)
        #expect(currentDevice.lightMode == .on)
        #expect(cameraManager.captureSession.sessionPreset == .hd1280x720)
        #expect(currentDevice.activeVideoMinFrameDuration == .init(value: 1, timescale: Int32(currentDevice.maxFrameRate!)))
        #expect(currentDevice.activeVideoMaxFrameDuration == .init(value: 1, timescale: Int32(currentDevice.maxFrameRate!)))
        #expect(currentDevice.exposureDuration == .init(value: 1, timescale: 10))
        #expect(currentDevice.exposureTargetBias == 0.66)
        #expect(currentDevice.iso == currentDevice.maxISO)
        #expect(currentDevice.exposureMode == .custom)
        #expect(currentDevice.hdrMode == .off)
        #expect(cameraManager.cameraGridView.alpha == 0)

        #expect(cameraManager.attributes.zoomFactor == currentDevice.maxAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.frameRate == Int32(currentDevice.maxFrameRate!))
        #expect(cameraManager.attributes.cameraExposure.iso == currentDevice.maxISO)
    }
    @Test("Setup: Audio Source Unavailable") func setupWithAudioSourceUnavailable() async throws {
        cameraManager.attributes.isAudioSourceAvailable = false
        try await setupCamera()

        #expect(cameraManager.captureSession.deviceInputs.count == 1)
    }
}

// MARK: Cancel
extension CameraManagerTests {
    @Test("Cancel Camera Session") func cancelCameraSession() async throws {
        try await setupCamera()
        cameraManager.cancel()

        #expect(cameraManager.captureSession.isRunning == false)
        #expect(cameraManager.captureSession.deviceInputs.count == 0)
        #expect(cameraManager.captureSession.outputs.count == 0)
    }

    @Test("Cancel Camera Session Clears Live Photo Temp File") func cancelCameraSessionClearsLivePhotoTempFile() async throws {
        let livePhotoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mijick-camera-test-live-photo-\(UUID().uuidString).mov")

        FileManager.default.createFile(atPath: livePhotoURL.path, contents: .init("temp".utf8))
        #expect(FileManager.default.fileExists(atPath: livePhotoURL.path))

        cameraManager.attributes.capturedMedia = MCameraMedia(
            image: UIImage(),
            metadata: nil as Data?,
            livePhotoMovieURL: livePhotoURL
        )

        cameraManager.cancel()
        #expect(FileManager.default.fileExists(atPath: livePhotoURL.path) == false)
    }
}

// MARK: Pause / Resume
extension CameraManagerTests {
    @Test("Pause: Stops Session And Keeps Pipeline") func pauseKeepsPipeline() async throws {
        try await setupCamera()
        let session = cameraManager.captureSession as? MockCaptureSession
        let outputCount = cameraManager.captureSession.outputs.count

        cameraManager.pause(.screenHidden)
        await waitForSessionQueue()

        #expect(cameraManager.captureSession.isRunning == false)
        #expect(cameraManager.cameraView.viewWithTag(.pauseCoverTag) != nil)
        #expect(cameraManager.captureSession as? MockCaptureSession === session)
        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(cameraManager.captureSession.outputs.count == outputCount)
    }
    @Test("Resume: Restarts Session Without Rebuilding") func resumeRestartsSession() async throws {
        try await setupCamera()
        let outputCount = cameraManager.captureSession.outputs.count

        cameraManager.pause(.screenHidden)
        cameraManager.resume(.screenHidden)
        // No frames arrive in the simulator, so the cover lifts on its timeout.
        await Task.sleep(seconds: 2)

        #expect(cameraManager.captureSession.isRunning == true)
        #expect(cameraManager.cameraView.viewWithTag(.pauseCoverTag) == nil)
        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(cameraManager.captureSession.outputs.count == outputCount)
    }
    @Test("Resume: Stays Stopped Until Every Pause Reason Is Lifted") func resumeNeedsEveryReasonLifted() async throws {
        try await setupCamera()

        cameraManager.pause(.screenHidden)
        cameraManager.pauseSession()
        cameraManager.resumeSession()
        await waitForSessionQueue()
        #expect(cameraManager.captureSession.isRunning == false)

        cameraManager.resume(.screenHidden)
        await waitForSessionQueue()
        #expect(cameraManager.captureSession.isRunning == true)
    }
    @Test("Setup: Second Call Does Not Rebuild") func setupTwiceDoesNotRebuild() async throws {
        try await setupCamera()
        let outputCount = cameraManager.captureSession.outputs.count
        let subviewCount = cameraManager.cameraView.subviews.count
        try await cameraManager.setup()

        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(cameraManager.captureSession.outputs.count == outputCount)
        #expect(cameraManager.cameraView.subviews.count == subviewCount)
    }
    @Test("Pause Before Setup: Session Starts Stopped") func pauseBeforeSetup() async throws {
        cameraManager.pauseSession()
        try await setupCamera()

        #expect(cameraManager.captureSession.isRunning == false)
    }
}

// MARK: Set Camera Output
extension CameraManagerTests {
    @Test("Set Camera Output") func setCameraOutput() async throws {
        try await setupCamera()

        cameraManager.setOutputType(.photo)
        #expect(cameraManager.attributes.outputType == .photo)

        cameraManager.setOutputType(.video)
        #expect(cameraManager.attributes.outputType == .video)
    }

    @Test("Set Photo Capture Mode") func setPhotoCaptureMode() async throws {
        try await setupCamera()

        cameraManager.setPhotoCaptureMode(.livePhoto)
        #expect(cameraManager.attributes.photoCaptureMode == .livePhoto)

        cameraManager.setPhotoCaptureMode(.still)
        #expect(cameraManager.attributes.photoCaptureMode == .still)
    }
}

// MARK: Set Camera Position
extension CameraManagerTests {
    @Test("Set Camera Position") func setCameraPosition() async throws {
        try await setupCamera()

        try await cameraManager.setCameraPosition(.front)
        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(currentDevice.uniqueID == cameraManager.frontCameraInput?.device.uniqueID)
        #expect(cameraManager.attributes.cameraPosition == .front)

        await Task.sleep(seconds: 0.5)

        try await cameraManager.setCameraPosition(.back)
        #expect(cameraManager.captureSession.deviceInputs.count == 2)
        #expect(currentDevice.uniqueID == cameraManager.backCameraInput?.device.uniqueID)
        #expect(cameraManager.attributes.cameraPosition == .back)

        await Task.sleep(seconds: 0.5)

        try cameraManager.setCameraZoomFactor(3.2)
        try await cameraManager.setCameraPosition(.front)
        #expect(currentDevice.videoZoomFactor == 1)
        #expect(cameraManager.attributes.zoomFactor == 1)
    }
}

// MARK: Set Camera Zoom
extension CameraManagerTests {
    @Test("Set Camera Zoom") func setCameraZoom() async throws {
        try await setupCamera()

        try cameraManager.setCameraZoomFactor(2.137)
        #expect(currentDevice.videoZoomFactor == 2.137)
        #expect(cameraManager.attributes.zoomFactor == 2.137)

        try cameraManager.setCameraZoomFactor(0.2137)
        #expect(currentDevice.videoZoomFactor == currentDevice.minAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.zoomFactor == currentDevice.minAvailableVideoZoomFactor)

        try cameraManager.setCameraZoomFactor(213.7)
        #expect(currentDevice.videoZoomFactor == currentDevice.maxAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.zoomFactor == currentDevice.maxAvailableVideoZoomFactor)
    }

    @Test("Ramp Zoom Clamps To Bounds") func rampZoomClampsToBounds() async throws {
        try await setupCamera()

        try cameraManager.rampZoom(to: 213.7)
        #expect(currentDevice.videoZoomFactor == currentDevice.maxAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.zoomFactor == currentDevice.maxAvailableVideoZoomFactor)

        try cameraManager.rampZoom(to: 0.2)
        #expect(currentDevice.videoZoomFactor == currentDevice.minAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.zoomFactor == currentDevice.minAvailableVideoZoomFactor)
    }

    @Test("Ramp Zoom Publishes Clamped Target") func rampZoomPublishesClampedTarget() async throws {
        try await setupCamera()

        try cameraManager.rampZoom(to: 50)
        #expect(cameraManager.attributes.zoomFactor == currentDevice.maxAvailableVideoZoomFactor)
        #expect(cameraManager.attributes.zoomFactor != 50)
    }
}

// MARK: Set Camera Focus
extension CameraManagerTests {
    @Test("Set Camera Focus") func setCameraFocus() async throws {
        try await setupCamera()

        let point = CGPoint(x: 213.7, y: 21.37)
        let expectedPoint = CGPoint(x: point.y / cameraManager.cameraView.frame.height, y: 1 - point.x / cameraManager.cameraView.frame.width)

        try cameraManager.setCameraFocus(at: point)
        #expect(currentDevice.focusPointOfInterest == expectedPoint)
        #expect(currentDevice.exposurePointOfInterest == expectedPoint)
        #expect(currentDevice.focusMode == .autoFocus)
        #expect(currentDevice.exposureMode == .autoExpose)
        #expect(cameraManager.cameraView.subviews.filter { $0.tag == .focusIndicatorTag }.count == 1)
    }
}

// MARK: Focus & Exposure Lock
extension CameraManagerTests {
    @Test("Lock Focus And Exposure") func lockFocusAndExposure() async throws {
        try await setupCamera()

        let point = CGPoint(x: 400, y: 300)
        try cameraManager.lockFocusAndExposure(at: point)
        #expect(cameraManager.attributes.isFocusExposureLocked == true)
        #expect(currentDevice.focusPointOfInterest == cameraManager.convertTouchPointToFocusPoint(point))
        #expect(currentDevice.exposurePointOfInterest == cameraManager.convertTouchPointToFocusPoint(point))
        #expect(currentDevice.focusMode == .autoFocus)
        #expect(currentDevice.exposureMode == .autoExpose)
        #expect(currentDevice.isSubjectAreaChangeMonitoringEnabled == false)
        #expect(cameraManager.cameraMetalView.focusIndicatorView?.isLocked == true)

        // A change of scene does not undo the lock.
        cameraManager.resetCameraFocusToContinuousAutoFocus()
        #expect(currentDevice.focusMode == .autoFocus)
        #expect(cameraManager.attributes.isFocusExposureLocked == true)
    }
    @Test("Letting Go Before The Lock Takes Leaves A Tap To Focus") func holdReleasedEarly() async throws {
        try await setupCamera()

        try cameraManager.beginFocusExposureLock(at: .init(x: 400, y: 300))
        #expect(cameraManager.isFocusExposureLockPending == true)
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
        #expect(currentDevice.isSubjectAreaChangeMonitoringEnabled == false)
        #expect(cameraManager.cameraMetalView.focusIndicatorView?.state == .pendingLock)

        cameraManager.cancelPendingFocusExposureLock()
        #expect(cameraManager.isFocusExposureLockPending == false)
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
        #expect(currentDevice.isSubjectAreaChangeMonitoringEnabled == true)
        #expect(cameraManager.cameraMetalView.focusIndicatorView?.state == .focused)

        // A commit after letting go does nothing.
        cameraManager.commitFocusExposureLock()
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
    }
    @Test("Tap Ends Focus And Exposure Lock") func tapEndsLock() async throws {
        try await setupCamera()

        try cameraManager.lockFocusAndExposure(at: .init(x: 400, y: 300))
        try cameraManager.setCameraFocus(at: .init(x: 100, y: 100))
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
        #expect(currentDevice.isSubjectAreaChangeMonitoringEnabled == true)
        #expect(cameraManager.cameraMetalView.focusIndicatorView?.isLocked == false)
        #expect(cameraManager.cameraView.subviews.filter { $0.tag == .focusIndicatorTag }.count == 1)
    }
    @Test("Release Focus And Exposure Lock") func releaseLock() async throws {
        try await setupCamera()

        try cameraManager.lockFocusAndExposure(at: .init(x: 400, y: 300))
        cameraManager.releaseFocusExposureLock()
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
        #expect(currentDevice.focusMode == .continuousAutoFocus)
        #expect(currentDevice.exposureMode == .continuousAutoExposure)
        #expect(cameraManager.cameraMetalView.isFocusIndicatorVisible == false)
    }
    @Test("Focus And Exposure Lock Respects Disabled Controls") func lockDisabled() async throws {
        try await setupCamera()

        try cameraManager.lockFocusAndExposure(at: .init(x: 400, y: 300))
        cameraManager.setFocusExposureControlsEnabled(false)
        #expect(cameraManager.attributes.isFocusExposureLocked == false)

        try cameraManager.lockFocusAndExposure(at: .init(x: 400, y: 300))
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
    }
    @Test("Camera Flip Ends Focus And Exposure Lock") func flipEndsLock() async throws {
        try await setupCamera()

        try cameraManager.setExposureTargetBias(0.5)
        try cameraManager.lockFocusAndExposure(at: .init(x: 400, y: 300))
        cameraManager.beginExposureAdjustment()
        cameraManager.updateExposureAdjustment(translation: -CameraManager.exposureDragPointsPerEV)
        cameraManager.endExposureAdjustment()
        let backDevice = currentDevice

        try await cameraManager.setCameraPosition(.front)
        #expect(cameraManager.attributes.isFocusExposureLocked == false)
        #expect(cameraManager.cameraMetalView.isFocusIndicatorVisible == false)
        // The back camera is left unlocked, at the host's own bias.
        #expect(backDevice.focusMode == .continuousAutoFocus)
        #expect(backDevice.isSubjectAreaChangeMonitoringEnabled == false)
        #expect(backDevice.exposureTargetBias == 0.5)

        // The flip animation blocks another flip until it has finished.
        await Task.sleep(seconds: 0.6)
        try await cameraManager.setCameraPosition(.back)
        #expect(cameraManager.attributes.cameraPosition == .back)
        #expect(cameraManager.attributes.cameraExposure.targetBias == 0.5)
    }
}

// MARK: Exposure Sun
extension CameraManagerTests {
    @Test("Exposure Sun Adds To The Exposure Bias") func exposureSunAddsToBias() async throws {
        try await setupCamera()
        try cameraManager.setExposureTargetBias(0.5)

        #expect(cameraManager.canAdjustExposureWithSun == false)
        try cameraManager.setCameraFocus(at: .init(x: 400, y: 300))
        #expect(cameraManager.canAdjustExposureWithSun == true)

        // Dragging up brightens; the host's own bias is left as it was.
        cameraManager.beginExposureAdjustment()
        #expect(cameraManager.cameraMetalView.isAdjustingExposure == true)
        cameraManager.updateExposureAdjustment(translation: -CameraManager.exposureDragPointsPerEV)
        #expect(currentDevice.exposureTargetBias == 1.5)
        #expect(cameraManager.attributes.cameraExposure.targetBias == 0.5)
        cameraManager.endExposureAdjustment()
        #expect(cameraManager.cameraMetalView.isAdjustingExposure == false)

        // The change is capped, and a second drag continues from the first.
        cameraManager.beginExposureAdjustment()
        cameraManager.updateExposureAdjustment(translation: -10 * CameraManager.exposureDragPointsPerEV)
        cameraManager.endExposureAdjustment()
        #expect(currentDevice.exposureTargetBias == 0.5 + CameraManager.maxExposureBiasOffset)
        #expect(cameraManager.cameraMetalView.focusIndicatorView?.exposureFraction == 1)

        // Changing the host's bias keeps the sun's change on top.
        try cameraManager.setExposureTargetBias(1)
        #expect(currentDevice.exposureTargetBias == 1 + CameraManager.maxExposureBiasOffset)

        // A new tap starts over from the host's bias.
        try cameraManager.setCameraFocus(at: .init(x: 100, y: 100))
        #expect(currentDevice.exposureTargetBias == 1)
    }
    @Test("Exposure Sun Unavailable When Controls Disabled") func exposureSunDisabled() async throws {
        try await setupCamera()
        cameraManager.setFocusExposureControlsEnabled(false)

        try cameraManager.setCameraFocus(at: .init(x: 400, y: 300))
        #expect(cameraManager.canAdjustExposureWithSun == false)
    }
}

// MARK: Photo Aspect Ratio
extension CameraManagerTests {
    @Test("Photo Aspect Ratio: Crop Rect") func photoAspectRatioCropRect() {
        // Portrait 3:4 stills.
        #expect(PhotoAspectRatioCrop.cropRect(width: 3024, height: 4032, longToShortRatio: CameraAspectRatio.square.longToShortRatio) == .init(x: 0, y: 504, width: 3024, height: 3024))
        #expect(PhotoAspectRatioCrop.cropRect(width: 3024, height: 4032, longToShortRatio: CameraAspectRatio.sixteenByNine.longToShortRatio) == .init(x: 378, y: 0, width: 2268, height: 4032))
        #expect(PhotoAspectRatioCrop.cropRect(width: 3024, height: 4032, longToShortRatio: CameraAspectRatio.fourByThree.longToShortRatio) == nil)
        // Landscape sensor pixels.
        #expect(PhotoAspectRatioCrop.cropRect(width: 4032, height: 3024, longToShortRatio: CameraAspectRatio.sixteenByNine.longToShortRatio) == .init(x: 0, y: 378, width: 4032, height: 2268))
        // A 16:9 still asked for 4:3 loses width instead.
        #expect(PhotoAspectRatioCrop.cropRect(width: 1920, height: 1080, longToShortRatio: CameraAspectRatio.fourByThree.longToShortRatio) == .init(x: 240, y: 0, width: 1440, height: 1080))
    }
    @Test("Photo Aspect Ratio: Image And Metadata") func photoAspectRatioImageAndMetadata() throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 400, height: 300), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in }
        let rotated = UIImage(cgImage: try #require(image.cgImage), scale: 1, orientation: .right)
        let metadata: [String: Any] = [
            kCGImagePropertyPixelWidth as String: 400,
            kCGImagePropertyPixelHeight as String: 300,
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifPixelXDimension as String: 400, kCGImagePropertyExifPixelYDimension as String: 300]
        ]

        let (cropped, croppedMetadata) = PhotoAspectRatioCrop.apply(.square, to: rotated, metadata: metadata)
        #expect(cropped?.cgImage?.width == 300)
        #expect(cropped?.cgImage?.height == 300)
        #expect(cropped?.imageOrientation == .right)
        #expect(croppedMetadata?[kCGImagePropertyPixelWidth as String] as? Int == 300)
        let exif = croppedMetadata?[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int == 300)

        let untouched = PhotoAspectRatioCrop.apply(nil, to: rotated, metadata: metadata)
        #expect(untouched.image === rotated)
    }
    @Test("Photo Aspect Ratio: Captured Photo Is Cropped") func photoAspectRatioCapture() async throws {
        try await setupCamera()

        cameraManager.setPhotoAspectRatio(.square)
        #expect(cameraManager.attributes.photoAspectRatio == .square)
        cameraManager.captureOutput()
        let image = try #require(cameraManager.attributes.capturedMedia?.image)
        #expect(image.size.width == image.size.height)
    }
    @Test("Focus Point Accounts For The Cropped Preview") func focusPointInCroppedPreview() {
        // A portrait 3:4 frame shown in a square view loses its top and bottom.
        let viewSize = CGSize(width: 300, height: 300)
        let frameSize = CGSize(width: 3024, height: 4032)
        let centre = CameraManager.focusPoint(for: .init(x: 150, y: 150), viewSize: viewSize, frameSize: frameSize)
        #expect(centre == .init(x: 0.5, y: 0.5))
        let top = CameraManager.focusPoint(for: .init(x: 150, y: 0), viewSize: viewSize, frameSize: frameSize)
        #expect(abs(top.x - 0.125) < 0.0001)
        // Without a frame, the view is taken to show all of it.
        #expect(CameraManager.focusPoint(for: .init(x: 150, y: 0), viewSize: viewSize, frameSize: nil) == .init(x: 0, y: 0.5))
    }
}

// MARK: Capture Timer
extension CameraManagerTests {
    @Test("Capture Timer Counts Down Then Captures") func captureTimerCountsDown() async throws {
        try await setupCamera()
        cameraManager.captureCountdownTickInterval = 0.2
        cameraManager.setCaptureTimer(.threeSeconds)

        cameraManager.captureOutput()
        #expect(cameraManager.attributes.captureCountdown == 3)
        #expect(cameraManager.attributes.capturedMedia == nil)

        await Task.sleep(seconds: 0.3)
        #expect(cameraManager.attributes.captureCountdown == 2)

        await Task.sleep(seconds: 0.6)
        #expect(cameraManager.attributes.captureCountdown == nil)
        #expect(cameraManager.attributes.capturedMedia != nil)
    }
    @Test("Capture Timer: Shutter Again Cancels") func captureTimerCancels() async throws {
        try await setupCamera()
        cameraManager.captureCountdownTickInterval = 0.2
        cameraManager.setCaptureTimer(.threeSeconds)

        cameraManager.captureOutput()
        cameraManager.captureOutput()
        #expect(cameraManager.attributes.captureCountdown == nil)

        await Task.sleep(seconds: 0.8)
        #expect(cameraManager.attributes.capturedMedia == nil)

        // Pausing the camera cancels one as well.
        cameraManager.captureOutput()
        cameraManager.pause(.host)
        #expect(cameraManager.isCaptureCountdownRunning == false)
        #expect(cameraManager.attributes.captureCountdown == nil)
    }
    @Test("Capture Timer: Start Recording Cancels The Countdown") func captureTimerStartRecording() async throws {
        try await setupCamera()
        cameraManager.captureCountdownTickInterval = 0.2
        cameraManager.setCaptureTimer(.threeSeconds)

        cameraManager.captureOutput()
        cameraManager.startRecording()
        #expect(cameraManager.isCaptureCountdownRunning == false)
        #expect(cameraManager.attributes.captureCountdown == nil)

        // Setting the same output type again leaves a countdown running.
        cameraManager.stopRecording()
        cameraManager.captureOutput()
        cameraManager.setOutputType(cameraManager.attributes.outputType)
        #expect(cameraManager.isCaptureCountdownRunning == true)
        cameraManager.cancelCaptureCountdown()
    }
    @Test("Capture Timer: Off Captures At Once") func captureTimerOff() async throws {
        try await setupCamera()

        cameraManager.captureOutput()
        #expect(cameraManager.attributes.captureCountdown == nil)
        #expect(cameraManager.attributes.capturedMedia != nil)
    }
}

// MARK: Set Flash Mode
extension CameraManagerTests {
    @Test("Set Flash Mode") func setFlashMode() async throws {
        try await setupCamera()

        cameraManager.setFlashMode(.on)
        #expect(cameraManager.attributes.flashMode == .on)

        cameraManager.setFlashMode(.auto)
        #expect(cameraManager.attributes.flashMode == .auto)

        cameraManager.setFlashMode(.off)
        #expect(cameraManager.attributes.flashMode == .off)
    }
}

// MARK: Set Light Mode
extension CameraManagerTests {
    @Test("Set Light Mode") func setLightMode() async throws {
        try await setupCamera()

        try cameraManager.setLightMode(.on)
        #expect(currentDevice.lightMode == .on)
        #expect(cameraManager.attributes.lightMode == .on)

        try cameraManager.setLightMode(.off)
        #expect(currentDevice.lightMode == .off)
        #expect(cameraManager.attributes.lightMode == .off)
    }
}

// MARK: Set Mirror Output
extension CameraManagerTests {
    @Test("Set Mirror Output") func setMirrorOutput() async throws {
        try await setupCamera()

        cameraManager.setMirrorOutput(true)
        #expect(cameraManager.attributes.mirrorOutput == true)

        cameraManager.setMirrorOutput(false)
        #expect(cameraManager.attributes.mirrorOutput == false)
    }
}

// MARK: Set Grid Visibility
extension CameraManagerTests {
    @Test("Set Grid Visibility") func setGridVisibility() async throws {
        try await setupCamera()

        cameraManager.setGridVisibility(true)
        #expect(cameraManager.cameraGridView.alpha == 1)
        #expect(cameraManager.attributes.isGridVisible == true)

        cameraManager.setGridVisibility(false)
        #expect(cameraManager.cameraGridView.alpha == 0)
        #expect(cameraManager.attributes.isGridVisible == false)
    }
}

// MARK: Set Auto Macro Mode
extension CameraManagerTests {
    @Test("Set Auto Macro Mode") func setAutoMacroMode() async throws {
        try await setupCamera()
        #expect(cameraManager.attributes.isAutoMacroModeEnabled == true)

        cameraManager.setAutoMacroMode(false)
        #expect(cameraManager.attributes.isAutoMacroModeEnabled == false)
        #expect(cameraManager.macroStateObserver.isAutoMacroModeEnabled == false)
        #expect(cameraManager.attributes.isMacroMode == false)

        cameraManager.setAutoMacroMode(true)
        #expect(cameraManager.attributes.isAutoMacroModeEnabled == true)
        #expect(cameraManager.macroStateObserver.isAutoMacroModeEnabled == true)
    }
}

// MARK: Set Camera Filters
extension CameraManagerTests {
    @Test("Set Camera Filters") func setCameraFilters() async throws {
        try await setupCamera()

        cameraManager.setCameraFilters([.init(name: "CISepiaTone")!])
        #expect(cameraManager.attributes.cameraFilters.count == 1)
    }
}

// MARK: Set Exposure Mode
extension CameraManagerTests {
    @Test("Set Exposure Mode") func setExposureMode() async throws {
        try await setupCamera()

        try cameraManager.setExposureMode(.continuousAutoExposure)
        #expect(currentDevice.exposureMode == .continuousAutoExposure)
        #expect(cameraManager.attributes.cameraExposure.mode == .continuousAutoExposure)

        try cameraManager.setExposureMode(.autoExpose)
        #expect(currentDevice.exposureMode == .autoExpose)
        #expect(cameraManager.attributes.cameraExposure.mode == .autoExpose)

        try cameraManager.setExposureMode(.custom)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.mode == .custom)
    }
}

// MARK: Set Exposure Duration
extension CameraManagerTests {
    @Test("Set Exposure Duration") func setExposureDuration() async throws {
        try await setupCamera()

        try cameraManager.setExposureDuration(.init(value: 1, timescale: 33))
        #expect(currentDevice.exposureDuration == .init(value: 1, timescale: 33))
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.duration == .init(value: 1, timescale: 33))

        try cameraManager.setExposureDuration(.init(value: 1, timescale: 100000))
        #expect(currentDevice.exposureDuration == currentDevice.minExposureDuration)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.duration == currentDevice.minExposureDuration)

        try cameraManager.setExposureDuration(.init(value: 1, timescale: 2))
        #expect(currentDevice.exposureDuration == currentDevice.maxExposureDuration)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.duration == currentDevice.maxExposureDuration)
    }
}

// MARK: Set ISO
extension CameraManagerTests {
    @Test("Set ISO") func setISO() async throws {
        try await setupCamera()

        try cameraManager.setISO(1)
        #expect(currentDevice.iso == 1)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.iso == 1)

        try cameraManager.setISO(-2137)
        #expect(currentDevice.iso == currentDevice.minISO)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.iso == currentDevice.minISO)

        try cameraManager.setISO(2137)
        #expect(currentDevice.iso == currentDevice.maxISO)
        #expect(currentDevice.exposureMode == .custom)
        #expect(cameraManager.attributes.cameraExposure.iso == currentDevice.maxISO)
    }
}

// MARK: Set Exposure Target Bias
extension CameraManagerTests {
    @Test("Set Exposure Target Bias") func setExposureTargetBias() async throws {
        try await setupCamera()

        try cameraManager.setExposureTargetBias(1)
        #expect(currentDevice.exposureTargetBias == 1)
        #expect(cameraManager.attributes.cameraExposure.targetBias == 1)

        try cameraManager.setExposureTargetBias(-2137)
        #expect(currentDevice.exposureTargetBias == currentDevice.minExposureTargetBias)
        #expect(cameraManager.attributes.cameraExposure.targetBias == currentDevice.minExposureTargetBias)

        try cameraManager.setExposureTargetBias(2137)
        #expect(currentDevice.exposureTargetBias == currentDevice.maxExposureTargetBias)
        #expect(cameraManager.attributes.cameraExposure.targetBias == currentDevice.maxExposureTargetBias)
    }
}

// MARK: Set HDR Mode
extension CameraManagerTests {
    @Test("Set HDR Mode") func setHDRMode() async throws {
        try await setupCamera()

        try cameraManager.setHDRMode(.on)
        #expect(currentDevice.hdrMode == .on)
        #expect(cameraManager.attributes.hdrMode == .on)

        try cameraManager.setHDRMode(.off)
        #expect(currentDevice.hdrMode == .off)
        #expect(cameraManager.attributes.hdrMode == .off)

        try cameraManager.setHDRMode(.auto)
        #expect(currentDevice.hdrMode == .auto)
        #expect(cameraManager.attributes.hdrMode == .auto)
    }
}

// MARK: Set Resolution
extension CameraManagerTests {
    @Test("Set Resolution") func setResolution() async throws {
        try await setupCamera()

        try await cameraManager.setResolution(.hd1280x720)
        #expect(cameraManager.captureSession.sessionPreset == .hd1280x720)
        #expect(cameraManager.attributes.resolution == .hd1280x720)

        try await cameraManager.setResolution(.hd1920x1080)
        #expect(cameraManager.captureSession.sessionPreset == .hd1920x1080)
        #expect(cameraManager.attributes.resolution == .hd1920x1080)

        try await cameraManager.setResolution(.cif352x288)
        #expect(cameraManager.captureSession.sessionPreset == .cif352x288)
        #expect(cameraManager.attributes.resolution == .cif352x288)
    }
}

// MARK: Audio Session Before Pipeline Rebuilds
extension CameraManagerTests {
    @Test("Format Change: Audio Session Readied Before The Preset Changes") func formatChangeReadiesAudioFirst() async throws {
        try await setupCamera()
        let activations = recordAudioSessionActivations { $0.sessionPreset.rawValue }

        try await cameraManager.setResolution(.hd1280x720)

        #expect(activations.values == [AVCaptureSession.Preset.hd1920x1080.rawValue])
        #expect(cameraManager.captureSession.sessionPreset == .hd1280x720)
    }
    @Test("Format Change: Unchanged Preset Leaves The Audio Session Alone") func unchangedPresetSkipsAudio() async throws {
        try await setupCamera()
        let activations = recordAudioSessionActivations { $0.sessionPreset.rawValue }

        try await cameraManager.setResolution(cameraManager.attributes.resolution)

        #expect(activations.values.isEmpty)
    }
    @Test("Camera Flip: Audio Session Readied Before The Input Swap") func flipReadiesAudioFirst() async throws {
        try await setupCamera()
        let backCameraID = try #require(cameraManager.backCameraInput?.device.uniqueID)
        let frontCameraID = try #require(cameraManager.frontCameraInput?.device.uniqueID)
        let activations = recordAudioSessionActivations { $0.deviceInputs.map { $0.device.uniqueID }.joined(separator: ",") }

        try await cameraManager.setCameraPosition(.front)

        #expect(activations.values.count == 1)
        #expect(activations.values.first?.contains(backCameraID) == true)
        #expect(activations.values.first?.contains(frontCameraID) == false)
        #expect(currentDevice.uniqueID == frontCameraID)
    }
    @Test("Pipeline Rebuild: No Mic Leaves The Audio Session Alone") func rebuildWithoutMicSkipsAudio() async throws {
        cameraManager.attributes.isAudioSourceAvailable = false
        try await setupCamera()
        let activations = recordAudioSessionActivations { $0.sessionPreset.rawValue }

        try await cameraManager.setResolution(.hd1280x720)
        try await cameraManager.setCameraPosition(.front)

        #expect(activations.values.isEmpty)
    }
    @Test("Pipeline Rebuild: Stopped Session Leaves The Audio Session Alone") func rebuildWhilePausedSkipsAudio() async throws {
        try await setupCamera()
        cameraManager.pause(.screenHidden)
        await waitForSessionQueue()
        let activations = recordAudioSessionActivations { $0.sessionPreset.rawValue }

        try await cameraManager.setResolution(.hd1280x720)

        #expect(activations.values.isEmpty)
        #expect(cameraManager.captureSession.sessionPreset == .hd1280x720)
    }
}

// MARK: Set Frame Rate
extension CameraManagerTests {
    @Test("Set Frame Rate") func setFrameRate() async throws {
        try await setupCamera()

        try cameraManager.setFrameRate(45)
        #expect(currentDevice.activeVideoMinFrameDuration == .init(value: 1, timescale: 45))
        #expect(currentDevice.activeVideoMaxFrameDuration == .init(value: 1, timescale: 45))
        #expect(cameraManager.attributes.frameRate == 45)

        try cameraManager.setFrameRate(10)
        #expect(currentDevice.activeVideoMinFrameDuration.timescale == Int32(currentDevice.minFrameRate!))
        #expect(currentDevice.activeVideoMaxFrameDuration.timescale == Int32(currentDevice.minFrameRate!))
        #expect(cameraManager.attributes.frameRate == Int32(currentDevice.minFrameRate!))

        try cameraManager.setFrameRate(100)
        #expect(currentDevice.activeVideoMinFrameDuration.timescale == Int32(currentDevice.maxFrameRate!))
        #expect(currentDevice.activeVideoMaxFrameDuration.timescale == Int32(currentDevice.maxFrameRate!))
        #expect(cameraManager.attributes.frameRate == Int32(currentDevice.maxFrameRate!))
    }
}


// MARK: Helpers
private extension CameraManagerTests {
    func setupCamera() async throws {
        let cameraView = UIView(frame: .init(origin: .zero, size: .init(width: 1000, height: 1000)))

        cameraManager.initialize(in: cameraView)
        try await cameraManager.setup()
        await Task.sleep(seconds: 10)
    }
}
private extension CameraManagerTests {
    /// Session starts and stops are queued; give them time to land.
    func waitForSessionQueue() async {
        await Task.sleep(seconds: 1)
    }
}
private extension CameraManagerTests {
    var currentDevice: any CaptureDevice { cameraManager.getCameraInput()!.device }
}
private extension CameraManagerTests {
    /// Replaces the audio session activation with a recorder that notes
    /// `snapshot` of the capture session at the moment it runs.
    func recordAudioSessionActivations(_ snapshot: @escaping @Sendable (any CaptureSession) -> String) -> AudioSessionActivations {
        let activations = AudioSessionActivations()
        let session = cameraManager.captureSession
        cameraManager.activateAudioSession = { activations.append(snapshot(session)) }
        return activations
    }
}
/// Filled on the session queue, read on the main actor.
private final class AudioSessionActivations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }
    func append(_ value: String) { lock.withLock { storage.append(value) } }
}
