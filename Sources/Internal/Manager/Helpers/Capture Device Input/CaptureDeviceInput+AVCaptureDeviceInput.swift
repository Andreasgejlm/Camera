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
    static func get(mediaType: AVMediaType, position: AVCaptureDevice.Position?) -> Self? {
        let device: AVCaptureDevice? = { switch mediaType {
        case .audio:
            return AVCaptureDevice.default(for: .audio)
        case .video:
            // Handle specific camera positions
            switch position {
            case .some(.front):
                return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                
            case .some(.back):
                // Prefer: triple > dual-wide > dual > wide
                let preferredTypes: [AVCaptureDevice.DeviceType] = [
                    .builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInWideAngleCamera
                ]
                
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: preferredTypes,
                    mediaType: .video,
                    position: .back
                )
                
                // Pick by priority explicitly (don’t assume devices[] order)
                for t in preferredTypes {
                    if let d = discovery.devices.first(where: { $0.deviceType == t }) {
                        print("📸 chosen device: \(d.localizedName ?? "unknown")")
                        return d
                    }
                }
                return discovery.devices.first // last-resort fallback
                
            default:
                return AVCaptureDevice.default(for: .video)
            }
        default:
            fatalError()
        }}()

        guard let device, let deviceInput = try? Self(device: device) else { return nil }
        return deviceInput
    }
}
