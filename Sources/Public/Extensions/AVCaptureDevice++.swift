//
//  AVCaptureDevice.swift
//  Split
//
//  Created by Andreas Gejl on 21/09/2025.
//

import AVKit

extension AVCaptureDevice {
    
    public var availableZoomLabels: [String] {
        if self.isVirtualDevice {
            let zoomFactors: [CGFloat] = [1.0] + self.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.floatValue) }
            //print("Available zoom factors: \(self.virtualDeviceSwitchOverVideoZoomFactors)")
            var zoomLabels = zoomFactors.map({ $0 * self.displayVideoZoomFactorMultiplier }).map({ value in
                value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            })
            let additionalZoomLabels = UIDevice.additionalZoomLabels ?? []
            zoomLabels.append(contentsOf: additionalZoomLabels)
            zoomLabels.sort(by: <)
            return zoomLabels
        }
        else {
            return [String(format: "%.1f", self.displayVideoZoomFactorMultiplier)]
        }
    }
    
    public func zoomLabelToValue(_ zoomLabel: String) -> CGFloat {
        return CGFloat(Float(zoomLabel) ?? 1.0) / self.displayVideoZoomFactorMultiplier
    }
    
    public func zoomValueToLabel(_ zoomValue: CGFloat) -> String {
        return String(format: "%.1f", zoomValue * self.displayVideoZoomFactorMultiplier)
    }
}

// MARK: - Macro helpers (from StackOverflow answer, CC BY-SA 4.0)
extension AVCaptureDevice {
    var isVirtualDeviceWithUltraWideCamera: Bool {
        switch deviceType {
        case .builtInTripleCamera, .builtInDualWideCamera, .builtInUltraWideCamera:
            return true
        default:
            return false
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var backBuiltInUltraWideCamera: AVCaptureDevice? {
        devices.first(where: { $0.position == .back && $0.deviceType == .builtInUltraWideCamera })
    }
}
