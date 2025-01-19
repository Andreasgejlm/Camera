//
//  CaptureDeviceInput+AVCaptureDeviceInput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

extension AVCaptureDeviceInput: CaptureDeviceInput {
    static func get(mediaType: AVMediaType, position: AVCaptureDevice.Position?, deviceType: AVCaptureDevice.DeviceType? = nil) -> Self? {
        if let deviceType {
            guard let device = AVCaptureDevice.default(deviceType, for: mediaType, position: .back) else { return nil }
            guard let deviceInput = try? Self(device: device) else { return nil }
            return deviceInput
        }
        let device = { switch mediaType {
            case .audio: AVCaptureDevice.default(for: .audio)
            case .video where position == .front: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            case .video where position == .back: getBackCamera()
            default: fatalError()
        }}()
        
        //setAutoExposureAndWhiteBalance([backCamera, frontCamera])

        guard let device, let deviceInput = try? Self(device: device) else { return nil }
        return deviceInput
    }
    
    static func getBackCamera() -> AVCaptureDevice? {
        if let tripleCamera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return tripleCamera
        } else if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return dualCamera
        } else if let dualCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualCamera
        } else {
            return AVCaptureDevice.default(for: .video)
        }
    }
}
