//
//  CameraManager+VideoOutput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


@preconcurrency import AVKit
import SwiftUI
import MijickTimer

/// `CaptureDeviceInput` isn't Sendable; the boxed value is created on the main actor
/// and handed exclusively to the session-mutation task that attaches it.
private struct UncheckedSendableBox<Value>: @unchecked Sendable { let value: Value }

@MainActor class CameraManagerVideoOutput: NSObject {
    private(set) var parent: CameraManager!
    private(set) var output: AVCaptureMovieFileOutput = .init()
    private(set) var timer: MTimer = .init(.camera)
    private(set) var recordingTime: MTime = .zero
    private(set) var firstRecordedFrame: UIImage?
    private var isPreparingToRecord: Bool = false
    private var stopRequestedWhilePreparing: Bool = false
}

// MARK: Setup
extension CameraManagerVideoOutput {
    func setup(parent: CameraManager) throws(MCameraError) {
        self.parent = parent
        try parent.captureSession.add(output: output)
    }
}

// MARK: Reset
extension CameraManagerVideoOutput {
    func reset() {
        timer.reset()
    }
}


// MARK: - CAPTURE VIDEO



// MARK: Toggle
extension CameraManagerVideoOutput {
    func toggleRecording() { switch output.isRecording {
        case true: stopRecording()
        case false: startRecording()
    }}
}

// MARK: Start Recording
extension CameraManagerVideoOutput {
    func startRecording() {
        guard !isRecording, !isPreparingToRecord else { return }

        #if targetEnvironment(simulator)
        // Mock recording for DEBUG/simulator mode
        startMockRecording()
        #else
        guard let url = prepareUrlForVideoRecording() else { return }

        // The mic input is added only at recording time so the camera doesn't pause
        // background audio while idle. Committing that change to the running session
        // activates the audio session — a blocking call that stalls the main thread
        // long enough to hitch UI animations and starve the preview (sample buffers
        // are delivered on the main queue, so a stalled main thread blanks the
        // viewfinder). Attach the input off the main thread, then start the actual
        // recording back on the main actor.
        isPreparingToRecord = true
        stopRequestedWhilePreparing = false
        let session = parent.captureSession
        let audioInput = UncheckedSendableBox(value: parent.claimAudioInputForRecording())
        let recorder = self

        Task.detached(priority: .userInitiated) {
            if let input = audioInput.value { try? session.add(input: input) }
            await recorder.beginRecording(to: url)
        }
        #endif
    }

    /// Second half of `startRecording()`, run on the main actor once the mic input
    /// has been attached. Skips starting if a stop was requested in the meantime.
    private func beginRecording(to url: URL) {
        isPreparingToRecord = false
        guard !stopRequestedWhilePreparing else {
            stopRequestedWhilePreparing = false
            parent.removeAudioInput()
            return
        }
        guard !isRecording else { return }

        configureOutput()
        output.startRecording(to: url, recordingDelegate: self)
        startRecordingTimer()
        parent.objectWillChange.send()
    }
    
    #if targetEnvironment(simulator)
    private func startMockRecording() {
        print("📹 DEBUG MODE: Mock recording started")
        startRecordingTimer()
        parent.objectWillChange.send()
    }
    #endif
}
private extension CameraManagerVideoOutput {
    var isRecording: Bool { output.isRecording }
    
    func prepareUrlForVideoRecording() -> URL? {
        FileManager.prepareURLForVideoOutput()
    }
    func configureOutput() {
        guard let connection = output.connection(with: .video), connection.isVideoMirroringSupported else { return }

        connection.isVideoMirrored = parent.attributes.mirrorOutput ? parent.attributes.cameraPosition != .front : parent.attributes.cameraPosition == .front
        connection.videoOrientation = parent.attributes.deviceOrientation
    }
    func storeLastFrame() {
        guard let texture = parent.cameraMetalView.currentDrawable?.texture,
              let ciImage = CIImage(mtlTexture: texture, options: nil),
              let cgImage = parent.cameraMetalView.ciContext.createCGImage(ciImage, from: ciImage.extent)
        else { return }

        firstRecordedFrame = UIImage(cgImage: cgImage, scale: 1.0, orientation: parent.attributes.deviceOrientation.toImageOrientation())
    }
    func startRecordingTimer() { try? timer
        .publish(every: 1) { [self] in
            recordingTime = $0
            parent.objectWillChange.send()
        }
        .start()
    }
}

// MARK: Stop Recording
extension CameraManagerVideoOutput {
    func stopRecording() {
        #if targetEnvironment(simulator)
        stopMockRecording()
        #else
        if isPreparingToRecord { stopRequestedWhilePreparing = true }
        output.stopRecording()
        #endif
        timer.reset()
    }
    
    #if targetEnvironment(simulator)
    private func stopMockRecording() {
        print("📹 DEBUG MODE: Mock recording stopped")
        // Create a mock video URL
        Task {
            await Task.sleep(seconds: 0.5)
            if let mockVideoURL = createMockVideo() {
                let capturedVideo = MCameraMedia(data: mockVideoURL)
                parent.setCapturedMedia(capturedVideo)
            }
        }
    }
    
    private func createMockVideo() -> URL? {
        // For now, just return nil - you could generate a real video file here if needed
        print("📹 DEBUG MODE: Mock video created")
        return nil
    }
    #endif
}

// MARK: Receive Data
extension CameraManagerVideoOutput: @preconcurrency AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        Task {
            // Check for recording errors first
            if let nsError = error as NSError? {
                let finished = (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
                if !finished {
                    print("Recording failed: \(nsError)")
                    return
                }
            }
            
            // Remove audio input so the mic is released and background audio can resume
            parent.removeAudioInput()

            do {
                let videoURL = try await prepareVideo(
                    outputFileURL: outputFileURL,
                    cameraFilters: parent.attributes.cameraFilters
                )
                let capturedVideo = MCameraMedia(data: videoURL)
                
                await Task.sleep(seconds: Animation.duration)
                parent.setCapturedMedia(capturedVideo)
                
                // Clean up temporary file if different
                if videoURL != outputFileURL {
                    try? FileManager.default.removeItem(at: outputFileURL)
                }
            } catch {
                print("Video processing failed: \(error)")
            }
        }
    }
}
private extension CameraManagerVideoOutput {
    func prepareVideo(outputFileURL: URL, cameraFilters: [CIFilter]) async throws -> URL? {
        if cameraFilters.isEmpty { return outputFileURL }
        
        let asset = AVAsset(url: outputFileURL)
        let videoComposition = try await AVVideoComposition.applyFilters(to: asset) {
            self.applyFiltersToVideo($0, cameraFilters)
        }
        
        // Create NEW output URL
        let fileUrl = FileManager.prepareURLForVideoOutput() // Use unique filename!
        let exportSession = prepareAssetExportSession(asset, fileUrl, videoComposition)
        
        try await exportVideo(exportSession, fileUrl)
        return fileUrl
    }
}
private extension CameraManagerVideoOutput {
    nonisolated func applyFiltersToVideo(_ request: AVAsynchronousCIImageFilteringRequest, _ filters: [CIFilter]) {
        let videoFrame = prepareVideoFrame(request, filters)
        request.finish(with: videoFrame, context: nil)
    }
    nonisolated func exportVideo(_ exportSession: AVAssetExportSession?, _ fileUrl: URL?) async throws {
        guard let exportSession, let fileUrl else {
            throw MCameraError.invalidVideoExportSession
        }
        
        if #available(iOS 18, *) {
            try await exportSession.export(to: fileUrl, as: .mp4)
        } else {
            await exportSession.export()
            
            // Check status on iOS 17 and earlier
            switch exportSession.status {
            case .completed:
                break
            case .failed:
                throw exportSession.error ?? MCameraError.videoExportFailed
            case .cancelled:
                throw MCameraError.videoExportCancelled
            default:
                throw MCameraError.videoExportUnexpectedFail
            }
        }
    }
}
private extension CameraManagerVideoOutput {
    nonisolated func prepareVideoFrame(_ request: AVAsynchronousCIImageFilteringRequest, _ filters: [CIFilter]) -> CIImage { request
        .sourceImage
        .clampedToExtent()
        .applyingFilters(filters)
    }
    nonisolated func prepareAssetExportSession(_ asset: AVAsset, _ fileUrl: URL?, _ composition: AVVideoComposition?) -> AVAssetExportSession? {
        let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080)
        export?.outputFileType = .mp4
        export?.outputURL = fileUrl
        export?.videoComposition = composition
        return export
    }
}


// MARK: - HELPERS
fileprivate extension MTimerID {
    static let camera: MTimerID = .init(rawValue: "mijick-camera")
}
