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
    private(set) var audioSetupError: MCameraError?

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
    private var pendingResolution: AVCaptureSession.Preset?

    // MARK: Others
    private(set) var permissionsManager: CameraManagerPermissionsManager = .init()
    private(set) var motionManager: CameraManagerMotionManager = .init()
    private(set) var notificationCenterManager: CameraManagerNotificationCenter = .init()
    private(set) var macroStateObserver: MacroStateObserver = .init()

    // MARK: Session Lifecycle
    /// Every blocking session call (start, stop, opening the mic) runs here, in
    /// order. `startRunning()` and `stopRunning()` block their caller for
    /// hundreds of milliseconds, which on the main thread
    /// freezes whatever animation is in flight. One serial queue also keeps a
    /// quick stop-then-start (leave the camera and come straight back) from
    /// being applied out of order.
    private let sessionQueue = DispatchQueue(label: "com.mijick.camera.session", qos: .userInitiated)
    private var setupState: SetupState = .idle
    /// Why the session is currently held stopped. It runs only while this is empty.
    private var pauseReasons: Set<SessionPauseReason> = []
    /// The running state last sent to `sessionQueue`. Tracked here instead of
    /// read from `captureSession.isRunning`, which lags behind queued work.
    private var isSessionStartRequested: Bool = false
    /// False until the first start is on `sessionQueue`; pausing before that
    /// only records the reason, so a stop can never be queued ahead of it.
    private var isFirstStartQueued: Bool = false
    private var audioRouteObserver: (any NSObjectProtocol)?
    
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
        super.init()
        // Published from the very first render. The 1.0 default is the lowest
        // lens of a multi-lens device, which the zoom control shows as "0.5×"
        // until setup has run.
        if let device = backCameraInput?.device {
            attributes.zoomFactor = getDefaultZoomFactor(of: device)
        }
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
    /// Builds the capture pipeline and starts the session. Runs once: later
    /// calls return immediately, because a camera that merely left the screen
    /// is paused and resumed (see `pause(_:)`), not rebuilt.
    func setup() async throws(MCameraError) {
        guard setupState == .idle else { return }
        setupState = .inProgress
        defer { if setupState == .inProgress { setupState = .idle } }

        try await permissionsManager.requestAccess(parent: self)

        setupCameraLayer()
        configureAudioSession()
        try setupDeviceInputs()
        configureCenterStageForManualZoomIfNeeded()
        try setupDeviceOutput()
        setRecordingAudioConnectionEnabled(false)
        try setupFrameRecorder()
        notificationCenterManager.setup(parent: self)
        motionManager.setup(parent: self)
        try cameraMetalView.setup(parent: self)
        cameraGridView.setup(parent: self)

        setupState = .ready
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
                                                                                       let photoDims = f.supportedMaxPhotoDimensions
                                                                                           .map { "\($0.width)x\($0.height)" }
                                                                                           .joined(separator: ", ")
                                                                                       print(String(format: "[%02d] VIDEO %dx%d up to %.0f fps | PHOTO %dx%d | PHOTO-MAX [%@] | %@ %@ | FOV %.1f°",
                                                                                                    i, v.width, v.height, fpsMax, p.width, p.height, photoDims, hdr, binned, f.videoFieldOfView))
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
        
        #if DEBUG && !targetEnvironment(simulator)
        dumpVideoAndPhotoRes(position: .back, deviceTypes: [.builtInTripleCamera, .builtInWideAngleCamera])
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
        // The mic input is attached here, before the session starts running.
        // Attaching it later (at recording time) commits a topology change to a
        // running session, which makes AVFoundation rebuild the capture pipeline —
        // visible as a frame gap and an exposure dip on the preview. An attached
        // mic is not an open one: its connection stays off, and the audio session
        // untouched, until a recording starts (see `configureAudioSession`).
        do {
            try attachAudioInput()
            // Verify the input was actually added to the session (canAddInput may
            // have silently returned false inside captureSession.add).
            if attributes.isAudioSourceAvailable, audioInput == nil {
                audioSetupError = .failedToSetupAudioInput
            }
        } catch {
            audioSetupError = (error as? MCameraError) ?? .failedToSetupAudioInput
        }

        // Publish the default zoom factor synchronously, before the preview renders.
        // Otherwise `zoomFactor` stays at its 1.0 default — the lowest lens, which the
        // display multiplier renders as "0.5×" — until `setupDevice` applies the default
        // lens inside the async `startSession` Task. That gap makes the zoom indicator
        // flash 0.5× then snap to 1.0× on launch.
        if let device = getCameraInput()?.device {
            attributes.zoomFactor = getDefaultZoomFactor(of: device)
            // Applied to the device too, before the session starts, so a
            // multi-lens device comes up on the default lens instead of
            // starting on the ultra-wide one and visibly switching.
            try? setDeviceZoomFactor(attributes.zoomFactor, device)
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
        await startCaptureSessionForTheFirstTime()
        
        // Only animate if cameraView is set
        if cameraView != nil {
            cameraMetalView.performCameraEntranceAnimation()
        } else {
            print("📷 DEBUG MODE: cameraView not initialized, skipping entrance animation")
        }
        #else
        guard let device = getCameraInput()?.device else { return }

        await startCaptureSessionForTheFirstTime()
        if let avDevice = device as? AVCaptureDevice { traceLens("first start", avDevice) }
        reconfigureSessionIfNeeded()
        try setupDevice(device)
        resetAttributes(device: device)
        photoOutput.updateMaxPhotoDimensions()

        if attributes.cameraPosition == .front, let avDevice = device as? AVCaptureDevice {
            logFrontCameraZoomRuntimeState(avDevice, context: "startSession.frontActive")
        }
        
        // Setup macro observer for back camera with AVCaptureDevice
        if attributes.cameraPosition == .back, let avDevice = device as? AVCaptureDevice {
            macroStateObserver.setup(parent: self, device: avDevice)
        }

        // The preview stays hidden until the device has settled on its lens,
        // exposure and focus, so none of that is visible as the camera opens.
        await waitForFirstFrame(after: nil)
        await waitForDeviceToSettle()
        cameraMetalView.performCameraEntranceAnimation()
        #endif
    }}
}
private extension CameraManager {
    func reconfigureSessionIfNeeded() {
    }
    func configureCenterStageForManualZoomIfNeeded() {
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
    }

    func logFrontCameraZoomRuntimeState(_ device: AVCaptureDevice, context: String) {
        #if DEBUG
        guard device.position == .front else { return }
        print("📷 FRONT ZOOM [\(context)] centerStageEnabled=\(AVCaptureDevice.isCenterStageEnabled) centerStageActive=\(device.isCenterStageActive) min=\(device.minAvailableVideoZoomFactor) max=\(device.maxAvailableVideoZoomFactor) formatMax=\(device.activeFormat.videoMaxZoomFactor) displayMultiplier=\(device.displayVideoZoomFactorMultiplier) current=\(device.videoZoomFactor)")
        #endif
    }

    private func getAudioInput() -> (any CaptureDeviceInput)? {
        guard let deviceInput = frontCameraInput ?? backCameraInput else { return nil }
        
        let captureDeviceInputType = type(of: deviceInput)
        let audioInput = captureDeviceInputType.get(mediaType: .audio, position: .unspecified)
        return audioInput
    }
    func startCaptureSessionForTheFirstTime() async {
        // From here on a pause queues its stop behind this start. A pause that
        // arrived earlier (the camera left the screen, or the app the
        // foreground, during setup) is applied once the start has finished.
        isFirstStartQueued = true
        isSessionStartRequested = true
        await startCaptureSession()
        reconcileSessionState()
    }
    /// Starts the session on `sessionQueue` and returns once it is running.
    func startCaptureSession() async {
        let session = captureSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                Self.traceAudioSession("session started")
                continuation.resume()
            }
        }
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

    /// Hands the app's audio session to the capture session, mixing with
    /// other apps' audio, and leaves the mic closed until a recording starts.
    ///
    /// The capture session configures and activates the audio session itself,
    /// at the moment the mic's connection is switched on (see
    /// `prepareAudioForRecording`), and does so without the audible dropout in
    /// other apps' audio that activating a hand-configured session causes.
    /// Until then the audio session is not touched at all, so opening the
    /// camera, or returning to it, cannot disturb music that is playing.
    func configureAudioSession() {
        guard let session = captureSession as? AVCaptureSession else { return }

        session.automaticallyConfiguresApplicationAudioSession = true
        session.configuresApplicationAudioSessionToMixWithOthers = true
        // Not part of the category, so it survives the automatic configuration.
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        traceAudioRouteChanges()
    }

    /// Debug aid for "OneLens paused my music" reports: `otherAudioPlaying`
    /// turning false right after one of these lines names the step that did it.
    nonisolated static func traceAudioSession(_ label: String, error: (any Error)? = nil) {
        #if DEBUG
        let audio = AVAudioSession.sharedInstance()
        let outputs = audio.currentRoute.outputs.map(\.portType.rawValue)
        let inputs = audio.currentRoute.inputs.map(\.portType.rawValue)
        let failure = error.map { " error=\($0)" } ?? ""
        print("🎧 \(label) | otherAudioPlaying=\(audio.isOtherAudioPlaying) category=\(audio.category.rawValue) mode=\(audio.mode.rawValue) options=\(audio.categoryOptions.rawValue) rate=\(Int(audio.sampleRate)) outputs=\(outputs) inputs=\(inputs)\(failure)")
        #endif
    }
    func traceAudioRouteChanges() {
        #if DEBUG
        guard audioRouteObserver == nil else { return }
        audioRouteObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Self.traceAudioSession("ROUTE CHANGE reason=\(reason)")
        }
        #endif
    }

    private func deactivateAudioSession() {
        do {
            // Deactivate with notifyOthersOnDeactivation to allow background audio to resume
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    /// Attaches the mic input to the session. Must only be called while the session
    /// is being configured (not running) — see the comment in `setupDeviceInputs`.
    func attachAudioInput() throws(MCameraError) {
        guard attributes.isAudioSourceAvailable else { return }
        guard audioInput == nil else { return } // Already added
        guard let input = getAudioInput() else {
            throw MCameraError.failedToSetupAudioInput
        }

        try captureSession.add(input: input)

        // Verify the input was actually accepted by the session.
        // `captureSession.add(input:)` silently skips `addInput` when
        // `canAddInput` returns false, so `audioInput` must only be set
        // when the session's inputs contain the audio device.
        if let session = captureSession as? AVCaptureSession,
           let avInput = input as? AVCaptureDeviceInput,
           !session.inputs.contains(avInput) {
            throw MCameraError.failedToSetupAudioInput
        }
        self.audioInput = input
    }

    func removeAudioInput() {
        guard let input = audioInput else { return }

        captureSession.remove(input: input)
        self.audioInput = nil
    }
}

// MARK: Recording audio
extension CameraManager {
    /// Opens the mic for a recording by switching the movie output's audio
    /// connection on, which is when the capture session configures and
    /// activates the audio session. The mic input itself has been attached
    /// since setup, so the running session's topology does not change here and
    /// the preview is not rebuilt.
    func prepareAudioForRecording() async {
        guard audioInput != nil else { return }

        let connection = UncheckedSendableBox(value: videoOutput.output.connection(with: .audio))
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                connection.value?.isEnabled = true
                Self.traceAudioSession("recording audio on")
                continuation.resume()
            }
        }
    }
    /// Closes the mic again once a recording has ended.
    func releaseAudioAfterRecording() {
        guard audioInput != nil else { return }

        let connection = UncheckedSendableBox(value: videoOutput.output.connection(with: .audio))
        sessionQueue.async {
            connection.value?.isEnabled = false
            Self.traceAudioSession("recording audio off")
        }
    }
    func setRecordingAudioConnectionEnabled(_ isEnabled: Bool) {
        videoOutput.output.connection(with: .audio)?.isEnabled = isEnabled
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
    /// Tears the capture pipeline down for good. Called when the camera view is
    /// removed from the hierarchy; a camera that only left the screen is paused
    /// instead (see `pause(_:)`). The next `setup()` rebuilds everything.
    func cancel() {
        clearCurrentCapturedLivePhotoIfNeeded()
        removeAudioInput()
        deactivateAudioSession()
        detachReusedSessionObjects()
        captureSession = captureSession.stopRunningAndReturnNewInstance()
        motionManager.reset()
        videoOutput.reset()
        notificationCenterManager.reset()
        macroStateObserver.stop()
        attributes.isMacroMode = false
        setupState = .idle
        isSessionStartRequested = false
        isFirstStartQueued = false
        cameraMetalView.isPresentingFrames = true
    }
}

// MARK: Pause / Resume Session
extension CameraManager {
    enum SetupState { case idle, inProgress, ready }
    enum SessionPauseReason {
        /// The camera screen is not visible, e.g. another screen is pushed on top of it.
        case screenHidden
        /// The host app called `pauseSession()`, e.g. because it entered the background.
        case host
    }

    /// Stops the session for `reason` while keeping its inputs, outputs and
    /// preview wiring intact, so `resume(_:)` restarts it without rebuilding
    /// the pipeline. The reasons are independent: the session runs again only
    /// once every reason it was paused for has been resumed.
    func pause(_ reason: SessionPauseReason) {
        pauseReasons.insert(reason)
        reconcileSessionState()
        // Already stopped for another reason: the cover is up, but it may be
        // the blurred frame, which a host pause must not leave on screen.
        if reason == .host, isFirstStartQueued, !isSessionStartRequested {
            cameraMetalView.showPauseCover(concealingLastFrame: true)
        }
    }
    func resume(_ reason: SessionPauseReason) {
        pauseReasons.remove(reason)
        reconcileSessionState()
    }
}
public extension CameraManager {
    /// Stops the running capture session **without** tearing down inputs,
    /// outputs, or the preview layer.
    ///
    /// Use this when the host app resigns active / enters the background so the
    /// camera and microphone hardware are released to other apps (e.g. the system
    /// Camera app). Unlike `cancel()`, it keeps the same `captureSession` instance
    /// and its Metal preview wiring intact, so `resumeSession()` can restart it
    /// cheaply. Safe to call when the session is already stopped (no-op).
    func pauseSession() { pause(.host) }

    /// Lifts a `pauseSession()`. The session restarts unless the camera screen
    /// is itself off screen, in which case it restarts when the screen returns.
    /// Safe to call when already running (no-op).
    func resumeSession() { resume(.host) }
}
private extension CameraManager {
    func reconcileSessionState() {
        guard setupState == .ready, isFirstStartQueued else { return }

        let shouldRun = pauseReasons.isEmpty
        guard shouldRun != isSessionStartRequested else { return }
        isSessionStartRequested = shouldRun

        if shouldRun { restartCaptureSession() }
        else { stopCaptureSession() }
    }
    func stopCaptureSession() {
        attributes.lightMode = .off
        videoOutput.reset()
        motionManager.reset()
        cameraMetalView.showPauseCover(concealingLastFrame: pauseReasons.contains(.host))

        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
            Self.traceAudioSession("session stopped")
        }
    }
    func restartCaptureSession() {
        motionManager.setup(parent: self)
        macroStateObserver.noteSessionStarting()
        // Before the start, so the device comes back up on the lens the UI shows.
        if let device = getCameraInput()?.device {
            try? setDeviceZoomFactor(attributes.zoomFactor, device)
        }
        let staleFrame = cameraMetalView.currentFrame
        // A restarting session delivers frames that are not fit to show: a
        // black one while the hardware comes up, then lens, exposure and focus
        // changes. They are visible even through the blur, so the preview
        // holds its last frame until the device has settled.
        cameraMetalView.isPresentingFrames = false
        Task {
            await startCaptureSession()
            restoreDeviceStateAfterRestart()

            await waitForFirstFrame(after: staleFrame)
            await waitForDeviceToSettle()
            // Paused again in the meantime: that pause owns the cover now, and
            // the restart that follows it resumes drawing.
            guard isSessionStartRequested else { return }
            cameraMetalView.isPresentingFrames = true
            // A live frame must have replaced the held one before the cover
            // lifts. Without one, a cover that conceals the last frame stays.
            let isShowingLiveFrame = await waitForPresentedFrame()
            guard isSessionStartRequested else { return }
            if isShowingLiveFrame || !cameraMetalView.pauseCoverConcealsLastFrame {
                cameraMetalView.hidePauseCover()
            }
        }
    }
    func waitForPresentedFrame() async -> Bool {
        let countBefore = cameraMetalView.presentedFrameCount
        let deadline = ContinuousClock.now + .milliseconds(500)
        while ContinuousClock.now < deadline {
            if cameraMetalView.presentedFrameCount != countBefore { return true }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        return false
    }
    /// The first frames after a start are not the final picture: a multi-lens
    /// device comes up on one lens and may still switch to the one the zoom
    /// factor calls for, and exposure and focus are still converging, which
    /// shows as a jump if revealed. Waits until the device is on the expected
    /// lens and has reported itself settled for 100 ms, or gives up after 1 s
    /// (a close subject legitimately keeps the device on the ultra-wide lens).
    func waitForDeviceToSettle() async {
        guard let device = getCameraInput()?.device as? AVCaptureDevice else { return }

        let start = ContinuousClock.now
        let deadline = start + .seconds(1)
        var activeLens = device.activePrimaryConstituent?.uniqueID
        var settledPolls = 0
        traceLens("settle begins", device)
        while ContinuousClock.now < deadline, settledPolls < 3 {
            try? await Task.sleep(nanoseconds: 33_000_000)

            let currentLens = device.activePrimaryConstituent?.uniqueID
            let expectedLens = expectedLensID(of: device)
            let isSettled = currentLens == activeLens
                && (expectedLens == nil || currentLens == expectedLens)
                && device.videoZoomFactor == attributes.zoomFactor
                && !device.isAdjustingExposure
                && !device.isAdjustingFocus
                && !device.isRampingVideoZoom
            settledPolls = isSettled ? settledPolls + 1 : 0
            if currentLens != activeLens { traceLens("lens changed after \(ContinuousClock.now - start)", device) }
            activeLens = currentLens
        }
        traceLens("settle ends after \(ContinuousClock.now - start), settled=\(settledPolls >= 3)", device)
    }
    /// The lens a virtual device uses for its current zoom factor when nothing
    /// (such as a close subject) makes it fall back to another one.
    func expectedLensID(of device: AVCaptureDevice) -> String? {
        guard device.isVirtualDevice else { return nil }

        let lenses = device.constituentDevices
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let index = switchOvers.filter { device.videoZoomFactor >= $0 }.count
        return lenses.indices.contains(index) ? lenses[index].uniqueID : nil
    }
    /// Debug aid for "the camera opens on the wrong lens" reports.
    func traceLens(_ label: String, _ device: AVCaptureDevice) {
        #if DEBUG
        let lens = device.activePrimaryConstituent?.deviceType.rawValue ?? "none"
        print("🔭 \(label) | deviceZoom=\(device.videoZoomFactor) shownZoom=\(attributes.zoomFactor) lens=\(lens) onExpectedLens=\(device.activePrimaryConstituent?.uniqueID == expectedLensID(of: device))")
        #endif
    }
    /// Polls until the preview has rendered a frame newer than `staleFrame`,
    /// with a timeout in case frames never resume.
    func waitForFirstFrame(after staleFrame: CIImage?) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if let frame = cameraMetalView.currentFrame, frame !== staleFrame { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
    /// The device keeps its configuration across a stop/start of the same
    /// session, so this normally does nothing. It only touches the device when
    /// zoom or frame rate came back different from what the UI shows.
    func restoreDeviceStateAfterRestart() {
        guard isSessionStartRequested, let device = getCameraInput()?.device else { return }

        if let avDevice = device as? AVCaptureDevice { traceLens("restarted", avDevice) }
        if device.videoZoomFactor != attributes.zoomFactor {
            try? setDeviceZoomFactor(attributes.zoomFactor, device)
        }
        if device.activeVideoMaxFrameDuration.timescale != attributes.frameRate {
            try? setDeviceFrameRate(attributes.frameRate, device)
        }
    }
}
private extension CameraManager {
    func detachReusedSessionObjects() {
        guard let session = captureSession as? AVCaptureSession else { return }
        session.beginConfiguration()
        if let input = getCameraInput() as? AVCaptureDeviceInput {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()
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
        clearReplacedLivePhotoIfNeeded(nextMedia: capturedMedia)
        attributes.capturedMedia = capturedMedia
    }}

    func clearCapturedLivePhotoTempFile() {
        clearCurrentCapturedLivePhotoIfNeeded()
    }
}
private extension CameraManager {
    func clearCurrentCapturedLivePhotoIfNeeded() {
        FileManager.clearFileIfExists(attributes.capturedMedia?.getLivePhotoMovie())
    }
    func clearReplacedLivePhotoIfNeeded(nextMedia: MCameraMedia?) {
        guard nextMedia != nil else { return }

        let currentLivePhotoMovie = attributes.capturedMedia?.getLivePhotoMovie()
        let nextLivePhotoMovie = nextMedia?.getLivePhotoMovie()

        guard currentLivePhotoMovie != nextLivePhotoMovie else { return }
        FileManager.clearFileIfExists(currentLivePhotoMovie)
    }
}

// MARK: Set Camera Output
extension CameraManager {
    func setPhotoCaptureMode(_ mode: PhotoCaptureMode) {
        guard mode != attributes.photoCaptureMode, !isChanging else { return }
        attributes.photoCaptureMode = mode
    }

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
        attributes.cameraPosition = position

        let device = getCameraInput()?.device
        resetAttributes(device: device)
        photoOutput.updateMaxPhotoDimensions()

        if position == .front {
            configureCenterStageForManualZoomIfNeeded()
            if let avDevice = device as? AVCaptureDevice {
                logFrontCameraZoomRuntimeState(avDevice, context: "setCameraPosition.frontActivated")
            }
        }

        // While flip animation is running, setCameraZoomFactor() is blocked by `isChanging`.
        // Apply default zoom directly so the newly selected camera starts from a stable baseline.
        if let device {
            let defaultZoomFactor: CGFloat = getDefaultZoomFactor(of: device)
            try? setDeviceZoomFactor(defaultZoomFactor, device)
            attributes.zoomFactor = device.videoZoomFactor

            if position == .front, let avDevice = device as? AVCaptureDevice {
                logFrontCameraZoomRuntimeState(avDevice, context: "setCameraPosition.frontDefaultZoomApplied")
            }
        }

        updateMacroObservation(position: position, device: device)
        
        await cameraMetalView.finishCameraFlipAnimation()
    }
}
private extension CameraManager {
    func changeCameraInput(_ position: CameraPosition) throws {
        if let input = getCameraInput() { captureSession.remove(input: input) }
        try captureSession.add(input: getCameraInput(position))
    }
    func updateMacroObservation(position: CameraPosition, device: (any CaptureDevice)?) {
        // Setup macro observer for back camera, stop for front camera
        if position == .back, let avDevice = device as? AVCaptureDevice {
            macroStateObserver.setup(parent: self, device: avDevice)
        } else {
            macroStateObserver.stop()
            attributes.isMacroMode = false
        }
    }
}

// MARK: Set Camera Zoom
extension CameraManager {
    func setCameraZoomFactor(_ zoomFactor: CGFloat) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        try setDeviceZoomFactor(zoomFactor, device)
        attributes.zoomFactor = device.videoZoomFactor

        if attributes.cameraPosition == .front, let avDevice = device as? AVCaptureDevice {
            logFrontCameraZoomRuntimeState(avDevice, context: "setCameraZoomFactor")
        }
    }
    
    func rampZoom(to zoomFactor: CGFloat) throws {
        guard let device = getCameraInput()?.device, !isChanging, !isPerformingFormatTransition else { return }

        let clampedTarget = device.clampedZoomFactor(for: zoomFactor)
        guard clampedTarget != attributes.zoomFactor else { return }

        try device.lockForConfiguration()
        device.rampZoom(to: clampedTarget)
        attributes.zoomFactor = clampedTarget
        device.unlockForConfiguration()

        if attributes.cameraPosition == .front, let avDevice = device as? AVCaptureDevice {
            logFrontCameraZoomRuntimeState(avDevice, context: "rampZoom")
        }
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
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()
        print("🎯 TAP focus set at \(focusPoint) | focusMode=\(device.focusMode.rawValue) monitoring=\(device.isSubjectAreaChangeMonitoringEnabled) focusPOISupported=\(device.isFocusPointOfInterestSupported)")
    }
}

// MARK: Reset Camera Focus
extension CameraManager {
    func resetCameraFocusToContinuousAutoFocus() {
        guard let device = getCameraInput()?.device else {
            print("🎯 RESET skipped: no camera input device")
            return
        }
        guard device.isSubjectAreaChangeMonitoringEnabled else {
            print("🎯 RESET skipped: monitoring already off (focusMode=\(device.focusMode.rawValue))")
            return
        }

        try? device.lockForConfiguration()
        device.resetFocusToContinuousAutoFocus()
        device.unlockForConfiguration()
        print("🎯 RESET to continuousAutoFocus | focusMode=\(device.focusMode.rawValue) monitoring=\(device.isSubjectAreaChangeMonitoringEnabled)")
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

// MARK: Set Video Stabilization Mode
extension CameraManager {
    func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) {
        guard mode != attributes.videoStabilizationMode else { return }
        attributes.videoStabilizationMode = mode
        // Apply immediately if a video connection already exists. If it doesn't
        // yet (or the format doesn't support stabilization), the mode is stored
        // and applied when recording is configured.
        applyVideoStabilizationModeIfPossible()
    }

    func applyVideoStabilizationModeIfPossible() {
        guard let connection = videoOutput.output.connection(with: .video),
              connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = attributes.videoStabilizationMode
    }
}

// MARK: Set Auto Macro Mode
extension CameraManager {
    func setAutoMacroMode(_ isEnabled: Bool) {
        guard isEnabled != attributes.isAutoMacroModeEnabled else { return }

        attributes.isAutoMacroModeEnabled = isEnabled
        macroStateObserver.setAutoMacroModeEnabled(isEnabled)
        if !isEnabled { attributes.isMacroMode = false }
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
        guard !isChanging else { return }

        // Primary behavior: do not drop requests; wait for active transition to finish.
        // Failsafe: keep only the latest queued resolution if multiple requests arrive.
        pendingResolution = resolution

        while let targetResolution = pendingResolution {
            pendingResolution = nil

            try await waitForFormatTransitionToFinish()
            guard targetResolution != attributes.resolution else { continue }

            try await performFormatTransition {
                await self.applySessionPresetOffMain(targetResolution)
                self.attributes.resolution = targetResolution
            } afterFramesResume: {
                // Applied only once frames flow at the new format — setting the zoom
                // while the session is still reconfiguring lets the reconfiguration
                // override it, leaving the wrong lens/perspective visible.
                if let device = self.getCameraInput()?.device {
                    let defaultZoomFactor: CGFloat = self.getDefaultZoomFactor(of: device)
                    try? self.setCameraZoomFactor(defaultZoomFactor)
                    // Swapping the active format resets the device's frame
                    // durations to the format default; reapply the requested rate.
                    try? self.setDeviceFrameRate(self.attributes.frameRate, device)
                }
                // The format change also resets the photo output's
                // maxPhotoDimensions to the new format's default (~13 MP binned
                // instead of 24 MP); raise the ceiling again.
                self.photoOutput.updateMaxPhotoDimensions()
            }
        }
    }
}
private extension CameraManager {
    func waitForFormatTransitionToFinish() async throws {
        while isPerformingFormatTransition {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Changing the preset of a running session blocks the calling thread while
    /// AVFoundation rebuilds the capture pipeline (hundreds of ms). On the main
    /// thread that freezes any in-flight SwiftUI layout animation (e.g. the
    /// viewfinder aspect-ratio resize), which then jumps to its end state when
    /// the thread unblocks. Hopping to a background queue keeps the main thread
    /// free to drive the animation while the format changes behind the blur.
    func applySessionPresetOffMain(_ preset: AVCaptureSession.Preset) async {
        guard let session = captureSession as? AVCaptureSession else {
            captureSession.sessionPreset = preset
            return
        }

        let box = UncheckedSendableBox(value: session)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                box.value.sessionPreset = preset
                continuation.resume()
            }
        }
    }
}

/// AVCaptureSession is internally synchronized for configuration but not marked
/// Sendable; this box carries it across the hop to the configuration queue.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

// MARK: Set Frame Rate
extension CameraManager {
    func setFrameRate(_ frameRate: Int32) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        // Store the requested rate, not the device's clamped result: format
        // transitions reset the device, and the post-transition reapply must
        // use the intended value (the device clamps per-format at apply time).
        // No early return on an unchanged value — the device may have been
        // silently reset to the format default in the meantime.
        attributes.frameRate = frameRate
        try setDeviceFrameRate(frameRate, device)
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
            UIView.animate(withDuration: 0.25, animations: {
                // Remove blur effect
                if let blurView = overlayView.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView {
                    blurView.effect = nil
                }
            }) { _ in
                // Fade out the entire overlay - no need to manipulate camera view alpha
                UIView.animate(withDuration: 0.15, animations: {
                    overlayView.alpha = 0
                }) { _ in
                    continuation.resume()
                }
            }
        }
        
        removeTransitionOverlay()
    }
    
    /// Performs the complete format transition animation sequence
    private func performFormatTransition(
        formatChange: @MainActor @escaping () async throws -> Void,
        afterFramesResume: @MainActor @escaping () throws -> Void = {}
    ) async throws {
        guard !isPerformingFormatTransition else { return }
        isPerformingFormatTransition = true

        defer { isPerformingFormatTransition = false }

        // Step 1: Capture current preview
        guard let previewImage = captureCurrentPreview() else {
            // If we cannot capture a snapshot for the visual transition,
            // still apply the format change to keep camera state consistent.
            try await formatChange()
            try afterFramesResume()
            return
        }

        // Step 2: Create overlay at parent level and hide camera view
        createTransitionOverlay(with: previewImage)

        // Steps 3+4 run concurrently: the preset change executes off the main thread
        // while the blur animates in. The change's first visible effect — the first
        // new-format frame — takes longer than the blur-in to arrive, so the blur is
        // up before anything changes on screen, and the transition saves the time it
        // previously spent blurring and reconfiguring sequentially.
        let extentBeforeChange = cameraMetalView.currentFrame?.extent
        let blurIn = Task { await self.animateBlur() }
        try await formatChange()
        await blurIn.value

        // Step 5: Wait until a frame in the new format has actually been rendered.
        // A fixed delay races the session: the first new-format frame can take a few
        // hundred ms to arrive and also forces a Metal drawable resize, so unblurring
        // on a timer could reveal the preview mid drawable-swap (black flash).
        await waitForFirstFrameAfterFormatChange(previousExtent: extentBeforeChange)

        // Step 6: Work that must run on the fully-reconfigured session (zoom reset)
        try afterFramesResume()

        // Step 7: Hold the blur briefly while the device finishes settling. On
        // multi-lens devices the first resumed frame is not the end of the story:
        // the virtual device may still switch its active constituent lens and
        // re-converge exposure, which shows as a black blink and a perspective snap
        // if revealed. The gradual unblur in step 8 masks the tail end of this.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Step 8: Animate unblur and fade out, revealing updated camera view
        await animateUnblurAndFadeOut()
    }

    /// Polls until the preview renders a frame whose dimensions differ from the
    /// pre-change frame (the new format), with a timeout in case the format change
    /// produced identically-sized buffers or frames never resume.
    private func waitForFirstFrameAfterFormatChange(previousExtent: CGRect?) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if let extent = cameraMetalView.currentFrame?.extent, extent.size != previousExtent?.size { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}
