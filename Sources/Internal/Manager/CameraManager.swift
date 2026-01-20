//
//  CameraManager.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import AVKit

@MainActor public class CameraManager: NSObject, ObservableObject {
    @Published var attributes: CameraManagerAttributes = .init()

    // MARK: Input
    private(set) var captureSession: any CaptureSession
    private(set) var frontCameraInput: (any CaptureDeviceInput)?
    private(set) var backCameraInput: (any CaptureDeviceInput)?
    private(set) var audioInput: (any CaptureDeviceInput)?

    // MARK: Output
    private(set) var photoOutput: CameraManagerPhotoOutput = .init()
    private(set) var videoOutput: CameraManagerVideoOutput = .init()

    // MARK: UI Elements
    private(set) var cameraView: UIView!
    private(set) var cameraLayer: AVCaptureVideoPreviewLayer = .init()
    private(set) var cameraMetalView: CameraMetalView = .init()
    private(set) var cameraGridView: CameraGridView = .init()
    
    // MARK: Format Transition Elements
    private var transitionOverlayView: UIImageView?
    private var isPerformingFormatTransition: Bool = false

    // MARK: Others
    private(set) var permissionsManager: CameraManagerPermissionsManager = .init()
    private(set) var motionManager: CameraManagerMotionManager = .init()
    private(set) var notificationCenterManager: CameraManagerNotificationCenter = .init()
    private(set) var macroStateObserver: MacroStateObserver = .init()
    
//    //MARK: Macro
//    private var zoomFactorObserver: NSKeyValueObservation?
//    private var activeConstituentObserver: NSKeyValueObservation?
//    private let macroVideoDeviceDiscoverySession: AVCaptureDevice.DiscoverySession = {
//        let types: [AVCaptureDevice.DeviceType] = [
//            .builtInWideAngleCamera,
//            .builtInDualCamera,
//            .builtInDualWideCamera,
//            .builtInTripleCamera,
//            .builtInTrueDepthCamera,
//            .builtInUltraWideCamera
//        ]
//        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
//    }()
//    


    // MARK: Initializer
    init<CS: CaptureSession, CDI: CaptureDeviceInput>(captureSession: CS, captureDeviceInputType: CDI.Type) {
        self.captureSession = captureSession
        self.frontCameraInput = CDI.get(mediaType: .video, position: .front)
        self.backCameraInput = CDI.get(mediaType: .video, position: .back)
    }
}

// MARK: Initialize
extension CameraManager {
    func initialize(in view: UIView) {
        cameraView = view
    }
}

// MARK: Setup
extension CameraManager {
    func setup() async throws(MCameraError) {
        try await permissionsManager.requestAccess(parent: self)

        setupCameraLayer()
        try setupDeviceInputs()
        try setupDeviceOutput()
        try setupFrameRecorder()
        notificationCenterManager.setup(parent: self)
        motionManager.setup(parent: self)
        try cameraMetalView.setup(parent: self)
        cameraGridView.setup(parent: self)
        try configureAudioSession()
                        
        startSession()
    }
}
private extension CameraManager {
    func dumpVideoAndPhotoRes(position: AVCaptureDevice.Position = .back,
                              deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera]) {
                                                                               let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                                                                                                mediaType: .video,
                                                                                                                                position: position)
                                                                               
                                                                               for device in discovery.devices {
                                                                                   print("\n=== \(device.localizedName) (\(position)) — \(device.formats.count) formats ===")
                                                                                   // Sort biggest photo first, then biggest video, then max FPS
                                                                                   let formats = device.formats.sorted { a, b in
                                                                                       let pa = a.highResolutionStillImageDimensions; let pb = b.highResolutionStillImageDimensions
                                                                                       let va = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                                                                                       let vb = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                                                                                       if pa.width * pa.height != pb.width * pb.height { return pa.width * pa.height > pb.width * pb.height }
                                                                                       if va.width * va.height != vb.width * vb.height { return va.width * va.height > vb.width * vb.height }
                                                                                       let fa = a.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                                                                                       let fb = b.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                                                                                       return fa > fb
                                                                                   }
                                                                                   
                                                                                   for (i, f) in formats.enumerated() {
                                                                                       let v = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                                                                                       let p = f.highResolutionStillImageDimensions
                                                                                       let fpsMax = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                                                                                       let hdr = f.isVideoHDRSupported ? "HDR" : "-"
                                                                                       let binned = f.isVideoBinned ? "BIN" : "-"
                                                                                       print(String(format: "[%02d] VIDEO %dx%d up to %.0f fps | PHOTO %dx%d | %@ %@ | FOV %.1f°",
                                                                                                    i, v.width, v.height, fpsMax, p.width, p.height, hdr, binned, f.videoFieldOfView))
                                                                                   }
                                                                               }
                                                                           }
    private func dims(_ f: AVCaptureDevice.Format) -> (Int, Int) {
        let desc = f.formatDescription
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        return (Int(dims.width), Int(dims.height))
    }
    
    private func maxFPS(_ f: AVCaptureDevice.Format) -> Double {
        f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    }
    
    private func fourCCString(_ f: AVCaptureDevice.Format) -> String {
        let desc = f.formatDescription
        let code = CMFormatDescriptionGetMediaSubType(desc)
        let bytes: [CChar] = [
            CChar((code >> 24) & 0xff),
            CChar((code >> 16) & 0xff),
            CChar((code >> 8) & 0xff),
            CChar(code & 0xff),
            0
        ]
        return String(cString: bytes)
    }
    
    private func colorSpaces(_ f: AVCaptureDevice.Format) -> [String] {
        f.supportedColorSpaces.map {
            switch $0 {
            case .sRGB: return "sRGB"
            case .P3_D65: return "P3"
            case .HLG_BT2020: return "HLG"
            @unknown default: return "?"
            }
        }
    }
    func dumpFormats(position: AVCaptureDevice.Position = .back,
                     deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera) {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [deviceType],
                                                         mediaType: .video,
                                                         position: position)
        guard let device = discovery.devices.first else {
            print("No camera found for \(position) / \(deviceType)")
            return
        }
        
        // Sort: highest resolution, then highest max FPS
        let formats = device.formats.sorted { a, b in
            let (wa, ha) = dims(a)
            let (wb, hb) = dims(b)
            if wa*ha != wb*hb { return wa*ha > wb*hb }
            return maxFPS(a) > maxFPS(b)
        }
        
        
        print("=== \(device.localizedName) (\(position)) — \(formats.count) formats ===")
        for (i, f) in formats.enumerated() {
            let (w, h) = dims(f)
            let fps = maxFPS(f)
            let fourCC = fourCCString(f)
            let hdr = f.isVideoHDRSupported ? "HDR" : "-"
            let binned = f.isVideoBinned ? "BIN" : "-"
            let cs = colorSpaces(f).joined(separator: "/")
            let fov = String(format: "%.1f°", f.videoFieldOfView)
            print(String(format: "[%02d] %dx%d @ up to %.0f fps | %@ | %@ %@ | CS:%@ | FOV:%@",
                         i, w, h, fps, fourCC, hdr, binned, cs, fov))
        }
    }
    
    func setupCameraLayer() {
        captureSession.sessionPreset = attributes.resolution
        
        #if !DEBUG && !targetEnvironment(simulator)
        dumpFormats(position: .back, deviceType: .builtInTripleCamera)
        dumpVideoAndPhotoRes(position: .back, deviceTypes: [.builtInTripleCamera])
        #endif

        // Guard against nil cameraView
        guard let cameraView = cameraView else {
            print("⚠️ cameraView not initialized yet in setupCameraLayer")
            return
        }

        cameraLayer.session = captureSession as? AVCaptureSession
        cameraLayer.videoGravity = .resizeAspectFill
        cameraLayer.isHidden = true
        cameraView.layer.addSublayer(cameraLayer)
        
        #if targetEnvironment(simulator)
        // Add a placeholder view for DEBUG/simulator mode
        setupDebugPlaceholder()
        #endif
    }
    
    #if targetEnvironment(simulator)
    func setupDebugPlaceholder() {
        guard let cameraView = cameraView else {
            print("📷 DEBUG MODE: cameraView not initialized yet, skipping debug placeholder")
            return
        }
        
        let placeholderView = UIView(frame: cameraView.bounds)
        placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        placeholderView.backgroundColor = .darkGray
        
        let label = UILabel()
        label.text = "📷 DEBUG MODE\nCamera Preview"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        placeholderView.addSubview(label)
        cameraView.addSubview(placeholderView)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor)
        ])
    }
    #endif
    func setupDeviceInputs() throws(MCameraError) {
        try captureSession.add(input: getCameraInput())
        // Add audio input at startup to avoid session interruption during recording
        do {
            try addAudioInput()
        } catch {
            print("⚠️ Could not add audio input during setup: \(error)")
            // Non-fatal error - camera can still work without audio
        }
    }
    func setupDeviceOutput() throws(MCameraError) {
        try photoOutput.setup(parent: self)
        try videoOutput.setup(parent: self)
    }
    func setupFrameRecorder() throws(MCameraError) {
        #if targetEnvironment(simulator)
        // Skip frame recorder in DEBUG/simulator mode - no real camera frames
        print("📷 DEBUG MODE: Skipping frame recorder setup")
        #else
        let captureVideoOutput = AVCaptureVideoDataOutput()
        captureVideoOutput.setSampleBufferDelegate(cameraMetalView, queue: .main)

        try captureSession.add(output: captureVideoOutput)
        #endif
    }
    func startSession() { Task {
        #if targetEnvironment(simulator)
        // Simplified session start for DEBUG/simulator mode
        print("📷 DEBUG MODE: Starting mock session")
        try? await startCaptureSession()
        
        // Only animate if cameraView is set
        if cameraView != nil {
            cameraMetalView.performCameraEntranceAnimation()
        } else {
            print("📷 DEBUG MODE: cameraView not initialized, skipping entrance animation")
        }
        #else
        guard let device = getCameraInput()?.device else { return }

        try await startCaptureSession()
        try setupDevice(device)
        resetAttributes(device: device)
        
        // Setup macro observer for back camera with AVCaptureDevice
        if attributes.cameraPosition == .back, let avDevice = device as? AVCaptureDevice {
            macroStateObserver.setup(parent: self, device: avDevice)
        }
        
        cameraMetalView.performCameraEntranceAnimation()
        #endif
    }}
}
private extension CameraManager {
    private func getAudioInput() -> (any CaptureDeviceInput)? {
        guard let deviceInput = frontCameraInput ?? backCameraInput else { return nil }
        
        let captureDeviceInputType = type(of: deviceInput)
        let audioInput = captureDeviceInputType.get(mediaType: .audio, position: .unspecified)
        return audioInput
    }
    nonisolated func startCaptureSession() async throws {
        await captureSession.startRunning()
    }
    func setupDevice(_ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(attributes.cameraExposure.mode, duration: attributes.cameraExposure.duration, iso: attributes.cameraExposure.iso)
        device.setExposureTargetBias(attributes.cameraExposure.targetBias)
        device.setFrameRate(attributes.frameRate)
        let defaultZoomFactor: CGFloat = getDefaultZoomFactor(of: device)
        try? setCameraZoomFactor(defaultZoomFactor)
        device.setLightMode(attributes.lightMode)
        device.hdrMode = attributes.hdrMode
        device.unlockForConfiguration()
        
    }
    

}

// MARK: Audio management
extension CameraManager {

    private func configureAudioSession() throws(MCameraError) {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audio.setCategory(.playAndRecord, options: [.mixWithOthers])

            try audio.setActive(true)
        } catch {
            print("Audio session setup error: \(error)")
            throw MCameraError.failedToSetupAudioInput
        }
    }

    private func deactivateAudioSession() {
        do {
            let audio = AVAudioSession.sharedInstance()
            // Deactivate with notifyOthersOnDeactivation to allow background audio to resume
            try audio.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    func addAudioInput() throws(MCameraError) {
        guard attributes.isAudioSourceAvailable else { return }
        guard audioInput == nil else { return } // Already added

        // Configure audio session for recording

        // Get and add audio input
        guard let input = getAudioInput() else {
            throw MCameraError.failedToSetupAudioInput
        }

        try captureSession.add(input: input)
        self.audioInput = input
    }

    func removeAudioInput() {
        guard let input = audioInput else { return }

        captureSession.remove(input: input)
        self.audioInput = nil
    }
}

// MARK: Default zoom factor
extension CameraManager {
    func getDefaultZoomFactor(of device: any CaptureDevice) -> CGFloat {
        if attributes.cameraPosition == .front {
            return 1.0
        }
        if let captureDevice = device as? AVCaptureDevice {
            if !captureDevice.isVirtualDevice {
                return 1.0
            }
            let zoomLabels = captureDevice.availableZoomLabels
            guard let defaultZoomIndex = zoomLabels.map { abs(CGFloat(Float($0) ?? 1.0) - 1.0) }.argmin() else { return 1.0 }
            let defaultZoom = zoomLabels[defaultZoomIndex]
            let defaultZoomValue = captureDevice.zoomLabelToValue(defaultZoom)
            return defaultZoomValue
        }
        return 1.0
    }
}

// MARK: Cancel
extension CameraManager {
    func cancel() {
        removeAudioInput()
        deactivateAudioSession()
        captureSession = captureSession.stopRunningAndReturnNewInstance()
        motionManager.reset()
        videoOutput.reset()
        notificationCenterManager.reset()
        macroStateObserver.stop()
        attributes.isMacroMode = false
    }
}

// MARK: Macro detection
//private extension CameraManager {
//    func setupMacroObserversIfNeeded(for device: AVCaptureDevice) {
//        teardownMacroObservers()
//        
//        // Only meaningful for devices that can involve ultra-wide constituent switching.
//        guard device.isVirtualDeviceWithUltraWideCamera else {
//            updateMacroMode()
//            return
//        }
//        
//        // Zoom changes can correlate with macro handoff, so keep this as a cheap trigger.
//        zoomFactorObserver = device.observe(\.videoZoomFactor, options: [.initial, .new]) { [weak self] _, _ in
//            Task { @MainActor [weak self] in
//                self?.updateMacroMode()
//            }
//        }
//        
//        // Active constituent change is the canonical signal on virtual devices.
//        if device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
//            do {
//                try device.lockForConfiguration()
//                device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
//                device.unlockForConfiguration()
//            } catch {
//                // Best effort; macro detection can still update via zoom changes.
//            }
//            
//            activeConstituentObserver = device.observe(\.activePrimaryConstituent, options: [.initial, .new]) { [weak self] _, _ in
//                Task { @MainActor [weak self] in
//                    self?.updateMacroMode()
//                }
//            }
//        }
//    }
//    
//    func teardownMacroObservers() {
//        zoomFactorObserver?.invalidate()
//        zoomFactorObserver = nil
//        activeConstituentObserver?.invalidate()
//        activeConstituentObserver = nil
//    }
//    
//    func updateMacroMode() {
//        guard let device = getCameraInput()?.device as? AVCaptureDevice else {
//            attributes.isMacroMode = false
//            return
//        }
//        attributes.isMacroMode = computeIsInMacroMode(for: device)
//    }
//    
//    func computeIsInMacroMode(for virtualDevice: AVCaptureDevice) -> Bool {
//        guard virtualDevice.isVirtualDeviceWithUltraWideCamera,
//              let activeCamera = virtualDevice.activePrimaryConstituent,
//              let ultraWideCamera = macroVideoDeviceDiscoverySession.backBuiltInUltraWideCamera
//        else { return false }
//        
//        // Heuristic from the referenced SO answer.
//        return activeCamera.uniqueID == ultraWideCamera.uniqueID
//        && virtualDevice.videoZoomFactor >= 2.0
//        && ultraWideCamera.videoZoomFactor == 1.0
//    }
//}


// MARK: - LIVE ACTIONS



// MARK: Capture Output
extension CameraManager {
    func captureOutput() {
        guard !isChanging else { return }

        switch attributes.outputType {
            case .photo: photoOutput.capture()
            case .video: videoOutput.toggleRecording()
        }
    }
    
    func startRecording() {
        videoOutput.startRecording()
    }
    
    func stopRecording() {
        videoOutput.stopRecording()
    }
}

// MARK: Set Captured Media
extension CameraManager {
    func setCapturedMedia(_ capturedMedia: MCameraMedia?) { withAnimation(.mSpring) {
        attributes.capturedMedia = capturedMedia
    }}
}

// MARK: Set Camera Output
extension CameraManager {
    func setOutputType(_ outputType: CameraOutputType) {
        guard outputType != attributes.outputType, !isChanging else { return }
        attributes.outputType = outputType
    }
}

// MARK: Set Camera Position
extension CameraManager {
    func setCameraPosition(_ position: CameraPosition) async throws {
        guard position != attributes.cameraPosition, !isChanging else { return }

        await cameraMetalView.beginCameraFlipAnimation()
        try changeCameraInput(position)
        resetAttributesWhenChangingCamera(position)
        
        if let device = getCameraInput()?.device {
            let defaultZoomFactor: CGFloat = getDefaultZoomFactor(of: device)
            try? setCameraZoomFactor(defaultZoomFactor)
        }
        
        await cameraMetalView.finishCameraFlipAnimation()
    }
}
private extension CameraManager {
    func changeCameraInput(_ position: CameraPosition) throws {
        if let input = getCameraInput() { captureSession.remove(input: input) }
        try captureSession.add(input: getCameraInput(position))
    }
    func resetAttributesWhenChangingCamera(_ position: CameraPosition) {
        resetAttributes(device: getCameraInput(position)?.device)
        let device = getCameraInput(position)?.device
        
        // Setup macro observer for back camera, stop for front camera
        if position == .back, let avDevice = device as? AVCaptureDevice {
            macroStateObserver.setup(parent: self, device: avDevice)
        } else {
            macroStateObserver.stop()
            attributes.isMacroMode = false
        }
        
        attributes.cameraPosition = position
    }
}

// MARK: Set Camera Zoom
extension CameraManager {
    func setCameraZoomFactor(_ zoomFactor: CGFloat) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        try setDeviceZoomFactor(zoomFactor, device)
        attributes.zoomFactor = device.videoZoomFactor
    }
    
    func rampZoom(to zoomFactor: CGFloat) throws {
        guard let device = getCameraInput()?.device, zoomFactor != attributes.zoomFactor, !isChanging, !isPerformingFormatTransition else { return }
        try device.lockForConfiguration()
        device.rampZoom(to: zoomFactor)
        attributes.zoomFactor = zoomFactor
        device.unlockForConfiguration()
    }
}
private extension CameraManager {
    func setDeviceZoomFactor(_ zoomFactor: CGFloat, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setZoomFactor(zoomFactor)
        device.unlockForConfiguration()
    }
}

// MARK: Set Camera Focus
extension CameraManager {
    func setCameraFocus(at touchPoint: CGPoint) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        let focusPoint = convertTouchPointToFocusPoint(touchPoint)
        try setDeviceCameraFocus(focusPoint, device)
        cameraMetalView.performCameraFocusAnimation(touchPoint: touchPoint)
    }
}
private extension CameraManager {
    func convertTouchPointToFocusPoint(_ touchPoint: CGPoint) -> CGPoint { .init(
        x: touchPoint.y / cameraView.frame.height,
        y: 1 - touchPoint.x / cameraView.frame.width
    )}
    func setDeviceCameraFocus(_ focusPoint: CGPoint, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setFocusPointOfInterest(focusPoint)
        device.setExposurePointOfInterest(focusPoint)
        device.unlockForConfiguration()
    }
}

// MARK: Set Flash Mode
extension CameraManager {
    func setFlashMode(_ flashMode: CameraFlashMode) {
        guard let device = getCameraInput()?.device, device.hasFlash, flashMode != attributes.flashMode, !isChanging else { return }
        attributes.flashMode = flashMode
    }
}

// MARK: Set Light Mode
extension CameraManager {
    func setLightMode(_ lightMode: CameraLightMode) throws {
        guard let device = getCameraInput()?.device, device.hasTorch, lightMode != attributes.lightMode, !isChanging else { return }

        try setDeviceLightMode(lightMode, device)
        attributes.lightMode = device.lightMode
    }
}
private extension CameraManager {
    func setDeviceLightMode(_ lightMode: CameraLightMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setLightMode(lightMode)
        device.unlockForConfiguration()
    }
}

// MARK: Set Mirror Output
extension CameraManager {
    func setMirrorOutput(_ mirrorOutput: Bool) {
        guard mirrorOutput != attributes.mirrorOutput, !isChanging else { return }
        attributes.mirrorOutput = mirrorOutput
    }
}

// MARK: Set Grid Visibility
extension CameraManager {
    func setGridVisibility(_ isGridVisible: Bool) {
        guard isGridVisible != attributes.isGridVisible, !isChanging else { return }
        cameraGridView.setVisibility(isGridVisible)
    }
}

// MARK: Set Camera Filters
extension CameraManager {
    func setCameraFilters(_ cameraFilters: [CIFilter]) {
        guard cameraFilters != attributes.cameraFilters, !isChanging else { return }
        attributes.cameraFilters = cameraFilters
    }
}

// MARK: Set Exposure Mode
extension CameraManager {
    func setExposureMode(_ exposureMode: AVCaptureDevice.ExposureMode) throws {
        guard let device = getCameraInput()?.device, exposureMode != attributes.cameraExposure.mode, !isChanging else { return }

        try setDeviceExposureMode(exposureMode, device)
        attributes.cameraExposure.mode = device.exposureMode
    }
}
private extension CameraManager {
    func setDeviceExposureMode(_ exposureMode: AVCaptureDevice.ExposureMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(exposureMode, duration: attributes.cameraExposure.duration, iso: attributes.cameraExposure.iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set Exposure Duration
extension CameraManager {
    func setExposureDuration(_ exposureDuration: CMTime) throws {
        guard let device = getCameraInput()?.device, exposureDuration != attributes.cameraExposure.duration, !isChanging else { return }

        try setDeviceExposureDuration(exposureDuration, device)
        attributes.cameraExposure.duration = device.exposureDuration
    }
}
private extension CameraManager {
    func setDeviceExposureDuration(_ exposureDuration: CMTime, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(.custom, duration: exposureDuration, iso: attributes.cameraExposure.iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set ISO
extension CameraManager {
    func setISO(_ iso: Float) throws {
        guard let device = getCameraInput()?.device, iso != attributes.cameraExposure.iso, !isChanging else { return }

        try setDeviceISO(iso, device)
        attributes.cameraExposure.iso = device.iso
    }
}
private extension CameraManager {
    func setDeviceISO(_ iso: Float, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(.custom, duration: attributes.cameraExposure.duration, iso: iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set Exposure Target Bias
extension CameraManager {
    func setExposureTargetBias(_ exposureTargetBias: Float) throws {
        guard let device = getCameraInput()?.device, exposureTargetBias != attributes.cameraExposure.targetBias, !isChanging else { return }

        try setDeviceExposureTargetBias(exposureTargetBias, device)
        attributes.cameraExposure.targetBias = device.exposureTargetBias
    }
}
private extension CameraManager {
    func setDeviceExposureTargetBias(_ exposureTargetBias: Float, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureTargetBias(exposureTargetBias) { [weak self] timestamp in
            // Capture self weakly, and read the device's current bias on the main actor
            Task { @MainActor [weak self] in
                guard let self = self,
                      let currentDevice = self.getCameraInput()?.device else { return }
                self.attributes.cameraExposure.targetBias = currentDevice.exposureTargetBias
            }
        }
        device.unlockForConfiguration()
    }
}

// MARK: Set HDR Mode
extension CameraManager {
    func setHDRMode(_ hdrMode: CameraHDRMode) throws {
        guard let device = getCameraInput()?.device, hdrMode != attributes.hdrMode, !isChanging else { return }

        try setDeviceHDRMode(hdrMode, device)
        attributes.hdrMode = hdrMode
    }
}
private extension CameraManager {
    func setDeviceHDRMode(_ hdrMode: CameraHDRMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.hdrMode = hdrMode
        device.unlockForConfiguration()
    }
}

// MARK: Set Resolution
extension CameraManager {
    func setResolution(_ resolution: AVCaptureSession.Preset) async throws {
        guard resolution != attributes.resolution, !isChanging, !isPerformingFormatTransition else { return }
        
        try await performFormatTransition {
            self.captureSession.sessionPreset = resolution
            self.attributes.resolution = resolution
            if let device = self.getCameraInput()?.device {
                let defaultZoomFactor: CGFloat = self.getDefaultZoomFactor(of: device)
                try? self.setCameraZoomFactor(defaultZoomFactor)
            }
        }
    }
}

// MARK: Set Frame Rate
extension CameraManager {
    func setFrameRate(_ frameRate: Int32) throws {
        guard let device = getCameraInput()?.device, frameRate != attributes.frameRate, !isChanging else { return }

        try setDeviceFrameRate(frameRate, device)
        attributes.frameRate = device.activeVideoMaxFrameDuration.timescale
    }
}
private extension CameraManager {
    func setDeviceFrameRate(_ frameRate: Int32, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setFrameRate(frameRate)
        device.unlockForConfiguration()
    }
}


// MARK: - HELPERS



// MARK: Attributes
extension CameraManager {
    var hasFlash: Bool { getCameraInput()?.device.hasFlash ?? false }
    var hasLight: Bool { getCameraInput()?.device.hasTorch ?? false }
}
private extension CameraManager {
    var isChanging: Bool { cameraMetalView.isAnimating }
}

// MARK: Methods
extension CameraManager {
    func resetAttributes(device: (any CaptureDevice)?) {
        guard let device else { return }

        var newAttributes = attributes
        newAttributes.cameraExposure.mode = device.exposureMode
        newAttributes.cameraExposure.duration = device.exposureDuration
        newAttributes.cameraExposure.iso = device.iso
        newAttributes.cameraExposure.targetBias = device.exposureTargetBias
        newAttributes.frameRate = device.activeVideoMaxFrameDuration.timescale
        newAttributes.zoomFactor = device.videoZoomFactor
        newAttributes.lightMode = device.lightMode
        newAttributes.hdrMode = device.hdrMode

        attributes = newAttributes
    }
    func getCameraInput(_ position: CameraPosition? = nil) -> (any CaptureDeviceInput)? { switch position ?? attributes.cameraPosition {
        case .front: frontCameraInput
        case .back: backCameraInput
    }}
}

// MARK: - Format Transition Animation
extension CameraManager {
    
    /// Captures the current preview layer as an image for transition overlay
    private func captureCurrentPreview() -> UIImage? {
        guard let cameraView = cameraView else { return nil }
        
        // Try to capture from the metal view first (where the actual camera content is)
        if let metalViewImage = captureFromMetalView() {
            return metalViewImage
        }
        
        // Fallback to capturing the entire camera view
        UIGraphicsBeginImageContextWithOptions(cameraView.bounds.size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Make sure we capture all sublayers including the camera layer
        cameraView.layer.render(in: context)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Attempts to capture the current frame from the metal view
    private func captureFromMetalView() -> UIImage? {
        // If you have access to the current frame from cameraMetalView, use that
        // This is a placeholder - you'll need to implement based on your CameraMetalView
        return nil
    }
    
    /// Creates and adds the transition overlay view that follows cameraView but isn't affected by its content changes
    private func createTransitionOverlay(with image: UIImage) {
        removeTransitionOverlay() // Remove any existing overlay
        
        let overlayView = UIImageView(image: image)
        overlayView.contentMode = .scaleAspectFill
        overlayView.clipsToBounds = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        
        // Get the camera view's parent
        guard let parentView = cameraView.superview else { return }
        
        // Add overlay to parent view, on top of camera view
        parentView.addSubview(overlayView)
        
        // Create constraints to match camera view's position and size exactly
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor)
        ])
        
        self.transitionOverlayView = overlayView
    }
    
    /// Removes the transition overlay view and restores camera view
    private func removeTransitionOverlay() {
        transitionOverlayView?.removeFromSuperview()
        transitionOverlayView = nil
        // No need to restore alpha since overlay is now a child, not covering the camera view
    }
    
    /// Animates the blur effect on the overlay
    private func animateBlur() async {
        guard let overlayView = transitionOverlayView else { return }
        
        // Create blur effect
        let blurEffect = UIBlurEffect(style: .regular)
        let blurEffectView = UIVisualEffectView(effect: nil)
        blurEffectView.frame = overlayView.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.addSubview(blurEffectView)
        
        // Animate blur in
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: 0.3, animations: {
                blurEffectView.effect = blurEffect
            }) { _ in
                continuation.resume()
            }
        }
    }
    
    /// Animates the unblur and fade out effect
    private func animateUnblurAndFadeOut() async {
        guard let overlayView = transitionOverlayView else { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: 0.3, animations: {
                // Remove blur effect
                if let blurView = overlayView.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView {
                    blurView.effect = nil
                }
            }) { _ in
                // Fade out the entire overlay - no need to manipulate camera view alpha
                UIView.animate(withDuration: 0.2, animations: {
                    overlayView.alpha = 0
                }) { _ in
                    continuation.resume()
                }
            }
        }
        
        removeTransitionOverlay()
    }
    
    /// Performs the complete format transition animation sequence
    private func performFormatTransition(formatChange: @escaping () throws -> Void) async throws {
        guard !isPerformingFormatTransition else { return }
        isPerformingFormatTransition = true
        
        defer { isPerformingFormatTransition = false }
        
        // Step 1: Capture current preview
        guard let previewImage = captureCurrentPreview() else {
            throw MCameraError.failedToTransition
        }
        
        // Step 2: Create overlay at parent level and hide camera view
        createTransitionOverlay(with: previewImage)
        
        // Step 3: Animate blur
        await animateBlur()
        
        // Step 4: Perform format change behind the blurred overlay
        try formatChange()
        
        // Step 5: Wait for format change to settle
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Step 6: Animate unblur and fade out, revealing updated camera view
        await animateUnblurAndFadeOut()
    }
}
