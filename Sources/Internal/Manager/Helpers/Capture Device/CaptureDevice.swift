//
//  CaptureDevice.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

protocol CaptureDevice: NSObject {
    // MARK: Getters
    var uniqueID: String { get }
    var exposureDuration: CMTime { get }
    var exposureTargetBias: Float { get }
    var iso: Float { get }
    var minAvailableVideoZoomFactor: CGFloat { get }
    var maxAvailableVideoZoomFactor: CGFloat { get }
    var minExposureDuration: CMTime { get }
    var maxExposureDuration: CMTime { get }
    var minISO: Float { get }
    var maxISO: Float { get }
    var minExposureTargetBias: Float { get }
    var maxExposureTargetBias: Float { get }
    var minFrameRate: Float64? { get }
    var maxFrameRate: Float64? { get }
    var hasFlash: Bool { get }
    var hasTorch: Bool { get }
    var isExposurePointOfInterestSupported: Bool { get }
    var isFocusPointOfInterestSupported: Bool { get }

    // MARK: Getters & Setters
    var videoZoomFactor: CGFloat { get set }
    var focusMode: AVCaptureDevice.FocusMode { get set }
    var focusPointOfInterest: CGPoint { get set }
    var exposurePointOfInterest: CGPoint { get set }
    var lightMode: CameraLightMode { get set }
    var activeVideoMinFrameDuration: CMTime { get set }
    var activeVideoMaxFrameDuration: CMTime { get set }
    var exposureMode: AVCaptureDevice.ExposureMode { get set }
    var hdrMode: CameraHDRMode { get set }

    // MARK: Methods
    func lockForConfiguration() throws
    func unlockForConfiguration()
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool
    func setExposureModeCustom(duration: CMTime, iso: Float, completionHandler: (@Sendable (CMTime) -> Void)?)
    func setExposureTargetBias(_ bias: Float, completionHandler handler: (@Sendable (CMTime) -> ())?)
    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float)
    func cancelVideoZoomRamp()
}


// MARK: - METHODS



// MARK: Set Zoom Factor
extension CaptureDevice {
    func clampedZoomFactor(for factor: CGFloat) -> CGFloat {
        min(max(factor, minAvailableVideoZoomFactor), min(maxAvailableVideoZoomFactor, maxZoom))
    }

    func setZoomFactor(_ factor: CGFloat) {
        let factor = clampedZoomFactor(for: factor)
        videoZoomFactor = factor
    }
    
    func rampZoom(to factor: CGFloat) {
        let factor = clampedZoomFactor(for: factor)
        cancelVideoZoomRamp()
        ramp(toVideoZoomFactor: factor, withRate: 5)
    }

    var isTripleCamera: Bool {
        guard let device: AVCaptureDevice = self as? AVCaptureDevice else { return false }
        
        return device.isTripleCamera
    }
    
    var maxZoom: CGFloat {
        if self.isTripleCamera {
            return 100
        } else {
            return 50
        }
    }

}

extension AVCaptureDevice {
    /// Determines if this device is a triple camera system
    /// Triple camera systems include wide, ultra-wide, and telephoto lenses
    var isTripleCamera: Bool {
        guard deviceType == .builtInTripleCamera else {
            return false
        }
        return true
    }
    
    /// More comprehensive check that verifies the device has all three lens types
    var hasTripleCameraSystem: Bool {
        // Check if it's the triple camera device type
        if deviceType == .builtInTripleCamera {
            return true
        }
        
        // Fallback: Check if device has all three constituent devices
        if #available(iOS 13.0, *) {
            if let multiCamDevice = self as? AVCaptureDevice,
               multiCamDevice.constituentDevices.count >= 3 {
                let types = multiCamDevice.constituentDevices.map { $0.deviceType }
                let hasWide = types.contains(.builtInWideAngleCamera)
                let hasUltraWide = types.contains(.builtInUltraWideCamera)
                let hasTelephoto = types.contains(.builtInTelephotoCamera)
                
                return hasWide && hasUltraWide && hasTelephoto
            }
        }
        
        return false
    }
}

// MARK: Set Focus Point Of Interest
extension CaptureDevice {
    func setFocusPointOfInterest(_ point: CGPoint) {
        guard isFocusPointOfInterestSupported else { return }

        focusPointOfInterest = point
        focusMode = .autoFocus
    }
}

// MARK: Set Exposure Point Of Interest
extension CaptureDevice {
    func setExposurePointOfInterest(_ point: CGPoint) {
        guard isExposurePointOfInterestSupported else { return }

        exposurePointOfInterest = point
        exposureMode = .autoExpose
    }
}

// MARK: Set Light Mode
extension CaptureDevice {
    func setLightMode(_ mode: CameraLightMode) {
        guard hasTorch else { return }
        lightMode = mode
    }
}

// MARK: Set Frame Rate
extension CaptureDevice {
    func setFrameRate(_ frameRate: Int32) {
        guard let minFrameRate, let maxFrameRate else { return }

        let frameRate = max(min(frameRate, Int32(maxFrameRate)), Int32(minFrameRate))

        activeVideoMinFrameDuration = CMTime(value: 1, timescale: frameRate)
        activeVideoMaxFrameDuration = CMTime(value: 1, timescale: frameRate)
    }
}

// MARK: Set Exposure Mode
extension CaptureDevice {
    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode, duration: CMTime, iso: Float) {
        guard isExposureModeSupported(mode) else { return }

        exposureMode = mode

        guard mode == .custom else { return }

        let duration = max(min(duration, maxExposureDuration), minExposureDuration)
        let iso = max(min(iso, maxISO), minISO)

        setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
    }
}

// MARK: Set Exposure Target Bias
extension CaptureDevice {
    func setExposureTargetBias(_ bias: Float) {
//        guard isExposureModeSupported(.custom) else { return }

        let bias = max(min(bias, maxExposureTargetBias), minExposureTargetBias)
        setExposureTargetBias(bias, completionHandler: nil)
    }
}
