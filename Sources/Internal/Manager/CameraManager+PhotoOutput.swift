//
//  CameraManager+PhotoOutput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

@MainActor class CameraManagerPhotoOutput: NSObject {
    private(set) var parent: CameraManager!
    private(set) var output: AVCapturePhotoOutput = .init()
    private var pendingPhotoCaptures: [Int64: PendingPhotoCapture] = [:]

    private struct PendingPhotoCapture {
        var image: UIImage?
        var metadata: [String: Any]?
        var isLivePhotoRequested: Bool
        var livePhotoMovieURL: URL?
    }
}

// MARK: Setup
extension CameraManagerPhotoOutput {
    func setup(parent: CameraManager) throws(MCameraError) {
        self.parent = parent
        try self.parent.captureSession.add(output: output)

        output.isLivePhotoCaptureEnabled = output.isLivePhotoCaptureSupported
        self.parent.attributes.isLivePhotoCaptureSupported = output.isLivePhotoCaptureSupported
    }
}


// MARK: - CAPTURE PHOTO



// MARK: Capture
extension CameraManagerPhotoOutput {
    func capture() {
        #if targetEnvironment(simulator)
        // Create a mock photo for DEBUG/simulator mode
        captureMockPhoto()
        #else
        let settings = getPhotoOutputSettings()
        setupPendingCapture(for: settings)

        configureOutput()
        output.capturePhoto(with: settings, delegate: self)
        #endif
        parent.cameraMetalView.performImageCaptureAnimation()
    }
    
    #if targetEnvironment(simulator)
    private func captureMockPhoto() {
        // Create a simple placeholder image
        let size = CGSize(width: 1920, height: 1080)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        // Draw a gradient background
        let context = UIGraphicsGetCurrentContext()
        let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
        context?.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        
        // Draw text
        let text = "📷 DEBUG PHOTO\n\(Date().formatted())"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 60, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else { return }
        
        // Create MCameraMedia with the mock image
        let capturedMedia = MCameraMedia(image: image, metadata: nil as [String: Any]?)
        parent.setCapturedMedia(capturedMedia)
    }
    #endif
}
private extension CameraManagerPhotoOutput {
    func getPhotoOutputSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = parent.attributes.flashMode.toDeviceFlashMode()

        if shouldCaptureLivePhoto(), let livePhotoMovieURL = FileManager.prepareURLForLivePhotoMovieOutput() {
            settings.livePhotoMovieFileURL = livePhotoMovieURL
        }
        return settings
    }
    func setupPendingCapture(for settings: AVCapturePhotoSettings) {
        let isLivePhotoRequested = settings.livePhotoMovieFileURL != nil
        guard isLivePhotoRequested else {
            pendingPhotoCaptures.removeValue(forKey: settings.uniqueID)
            return
        }

        pendingPhotoCaptures[settings.uniqueID] = .init(
            image: nil,
            metadata: nil,
            isLivePhotoRequested: true,
            livePhotoMovieURL: settings.livePhotoMovieFileURL
        )
    }
    func shouldCaptureLivePhoto() -> Bool {
        parent.attributes.isLivePhotoCaptureSupported = output.isLivePhotoCaptureSupported

        return parent.attributes.photoCaptureMode == .livePhoto
            && parent.attributes.isLivePhotoCaptureSupported
    }
    func configureOutput() {
        guard let connection = output.connection(with: .video), connection.isVideoMirroringSupported else { return }

        connection.isVideoMirrored = parent.attributes.mirrorOutput ? parent.attributes.cameraPosition != .front : parent.attributes.cameraPosition == .front
        connection.videoOrientation = parent.attributes.deviceOrientation
    }
}

// MARK: Receive Data
extension CameraManagerPhotoOutput: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let uniqueID = photo.resolvedSettings.uniqueID
        let capturedUIImage: UIImage? = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        let metadata = photo.metadata as? [String: Any]

        if var pendingCapture = pendingPhotoCaptures[uniqueID] {
            pendingCapture.image = capturedUIImage
            pendingCapture.metadata = metadata
            pendingPhotoCaptures[uniqueID] = pendingCapture
            return
        }

        guard error == nil, capturedUIImage != nil else { return }

        let capturedMedia = MCameraMedia(image: capturedUIImage, metadata: metadata)
        parent.setCapturedMedia(capturedMedia)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime,
                     photoDisplayTime: CMTime,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        let uniqueID = resolvedSettings.uniqueID
        guard var pendingCapture = pendingPhotoCaptures[uniqueID] else { return }

        if error != nil {
            FileManager.clearFileIfExists(pendingCapture.livePhotoMovieURL)
            pendingCapture.livePhotoMovieURL = nil
        } else {
            pendingCapture.livePhotoMovieURL = outputFileURL
        }

        pendingPhotoCaptures[uniqueID] = pendingCapture
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        let uniqueID = resolvedSettings.uniqueID
        guard let pendingCapture = pendingPhotoCaptures.removeValue(forKey: uniqueID) else { return }

        guard let capturedImage = pendingCapture.image else {
            FileManager.clearFileIfExists(pendingCapture.livePhotoMovieURL)
            return
        }

        if error == nil,
           pendingCapture.isLivePhotoRequested,
           let livePhotoMovieURL = pendingCapture.livePhotoMovieURL {
            let capturedMedia = MCameraMedia(
                image: capturedImage,
                metadata: pendingCapture.metadata,
                livePhotoMovieURL: livePhotoMovieURL
            )
            parent.setCapturedMedia(capturedMedia)
            return
        }

        FileManager.clearFileIfExists(pendingCapture.livePhotoMovieURL)
        let capturedMedia = MCameraMedia(image: capturedImage, metadata: pendingCapture.metadata)
        parent.setCapturedMedia(capturedMedia)
    }
}

private extension CameraManagerPhotoOutput {
    func prepareCIImage(_ ciImage: CIImage, _ filters: [CIFilter]) -> CIImage {
        ciImage.applyingFilters(filters)
    }
    func prepareCGImage(_ ciImage: CIImage) -> CGImage? {
        CIContext().createCGImage(ciImage, from: ciImage.extent)
    }
    func prepareUIImage(_ cgImage: CGImage?) -> UIImage? {
        guard let cgImage else { return nil }

        let frameOrientation = getFixedFrameOrientation()
        let orientation = UIImage.Orientation(frameOrientation)
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        return uiImage
    }
}
private extension CameraManagerPhotoOutput {
    func getFixedFrameOrientation() -> CGImagePropertyOrientation {
        guard UIDevice.current.orientation != parent.attributes.deviceOrientation.toDeviceOrientation() else { return parent.attributes.frameOrientation }

        return switch (parent.attributes.deviceOrientation, parent.attributes.cameraPosition) {
            case (.portrait, .front): .left
            case (.portrait, .back): .right
            case (.landscapeLeft, .back): .down
            case (.landscapeRight, .back): .up
            case (.landscapeLeft, .front) where parent.attributes.mirrorOutput: .up
            case (.landscapeLeft, .front): .upMirrored
            case (.landscapeRight, .front) where parent.attributes.mirrorOutput: .down
            case (.landscapeRight, .front): .downMirrored
            default: .right
        }
    }
}
