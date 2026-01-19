//
//  CameraManager+macro.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVFoundation

@MainActor final class MacroStateObserver {
    private(set) weak var parent: CameraManager?
    private var obsActive: NSKeyValueObservation?
    private var obsZoom: NSKeyValueObservation?

    private var lastIsMacroLike: Bool = false
    private var initialObservationsReceived: Int = 0

    func setup(parent: CameraManager, device: AVCaptureDevice) {
        self.parent = parent
        self.initialObservationsReceived = 0
        self.lastIsMacroLike = false
        
//        print("🔍 [MacroObserver] Setting up observer for device: \(device.localizedName)")
        
        start(device: device) { [weak parent] isMacroLike in
//            print("🔍 [MacroObserver] onChange callback: isMacroMode = \(isMacroLike)")
            parent?.attributes.isMacroMode = isMacroLike
        }
    }

    func start(device: AVCaptureDevice,
               onChange: @escaping (_ isMacroLike: Bool) -> Void) {

        func recomputeAndEmit() {
            guard device.isVirtualDevice else {
//                print("🔍 [MacroObserver] Not a virtual device, skipping macro detection")
                return
            }

            // Skip initial observations to avoid false positives at startup
            // We expect 2 initial observations (activePrimaryConstituentDevice + videoZoomFactor)
            if initialObservationsReceived < 2 {
                initialObservationsReceived += 1
//                print("🔍 [MacroObserver] Skipping initial observation \(initialObservationsReceived)/2")
                return
            }

            let activeDevice = device.activePrimaryConstituent
            let activeType = activeDevice?.deviceType
            let isUltraWideActive = (activeType == .builtInUltraWideCamera)
            
            let z = CGFloat(device.videoZoomFactor)
            let lensPos = CGFloat(device.lensPosition)

            // Simplified detection: just check if ultra-wide is active and zoom is low
            // Macro mode typically activates when zooming in close with the ultra-wide lens
            let isMacroLike = isUltraWideActive && z < 1.5

//            print("🔍 [MacroObserver] Device: \(device.localizedName)")
//            print("🔍 [MacroObserver]   - Active constituent: \(activeDevice?.localizedName ?? "nil") (type: \(activeType?.rawValue ?? "nil"))")
//            print("🔍 [MacroObserver]   - isUltraWide: \(isUltraWideActive)")
//            print("🔍 [MacroObserver]   - Zoom: \(z)")
//            print("🔍 [MacroObserver]   - Lens position: \(lensPos)")
//            print("🔍 [MacroObserver]   - Constituent devices: \(device.constituentDevices.map { $0.deviceType.rawValue }.joined(separator: ", "))")
//            print("🔍 [MacroObserver]   - SwitchOver factors: \(device.virtualDeviceSwitchOverVideoZoomFactors)")
//            print("🔍 [MacroObserver]   -> isMacro: \(isMacroLike)")

            if isMacroLike != lastIsMacroLike {
//                print("🔍 [MacroObserver] ⚡️ Macro mode CHANGED: \(lastIsMacroLike) -> \(isMacroLike)")
                lastIsMacroLike = isMacroLike
                onChange(isMacroLike)
            } else {
//                print("🔍 [MacroObserver] No change (current state: \(lastIsMacroLike))")
            }
        }

//        print("🔍 [MacroObserver] Setting up KVO observers...")
        
        obsActive = device.observe(\.activePrimaryConstituent, options: [.initial, .new]) { device, change in
//            print("🔍 [MacroObserver] 📹 activePrimaryConstituentDevice changed to: \(device.activePrimaryConstituent?.localizedName ?? "nil")")
            Task { @MainActor in
                recomputeAndEmit()
            }
        }

        obsZoom = device.observe(\.videoZoomFactor, options: [.initial, .new]) { device, change in
//            print("🔍 [MacroObserver] 🔍 videoZoomFactor changed to: \(device.videoZoomFactor)")
            Task { @MainActor in
                recomputeAndEmit()
            }
        }
        
//        print("🔍 [MacroObserver] Observers set up successfully")
    }

    func stop() {
//        print("🔍 [MacroObserver] Stopping observers")
        obsActive?.invalidate()
        obsZoom?.invalidate()
        obsActive = nil
        obsZoom = nil
        initialObservationsReceived = 0
        lastIsMacroLike = false
    }
}
