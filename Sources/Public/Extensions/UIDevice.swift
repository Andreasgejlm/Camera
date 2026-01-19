//
//  UIDevice.swift
//  Split
//
//  Created by Andreas Gejl on 29/12/2025.
//


import UIKit

extension UIDevice {
    
    /// Returns the internal iPhone generation number (e.g. 15 for iPhone15,3)
    /// This is monotonic but NOT the marketing model number.
    static var iPhoneGeneration: Int? {
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        
        guard
            identifier.hasPrefix("iPhone"),
            let major = identifier
                .replacingOccurrences(of: "iPhone", with: "")
                .split(separator: ",")
                .first,
            let generation = Int(major)
        else {
            return nil
        }
        
        return generation
    }
    
    static var additionalZoomLabels: [String]? {
        guard let iPhoneGeneration else { return [] }
        switch iPhoneGeneration - 1 {
        case 14:
            return ["2"]
        case 15:
            return ["2"]
        case 16:
            return ["2"]
        case 17:
            return ["2", "8"]
        default:
            return []
        }
    }
    
}
