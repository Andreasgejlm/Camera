//
//  CameraView+Metal.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import MetalKit
import AVKit

@MainActor class CameraMetalView: MTKView {
    private(set) var parent: CameraManager!
    private(set) var ciContext: CIContext!
    private(set) var commandQueue: MTLCommandQueue!
    private(set) var currentFrame: CIImage?
    private(set) var focusIndicator: CameraFocusIndicatorView = .init()
    private(set) var isAnimating: Bool = false
    /// While false, incoming frames are tracked in `currentFrame` but not
    /// drawn, so the view keeps showing the last frame it presented.
    var isPresentingFrames: Bool = true
}

// MARK: Setup
extension CameraMetalView {
    func setup(parent: CameraManager) throws(MCameraError) {
        #if targetEnvironment(simulator)
        // Minimal setup for DEBUG/simulator mode
        print("📷 DEBUG MODE: Skipping Metal view setup (no camera frames)")
        self.parent = parent
        #else
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { throw .cannotSetupMetalDevice }

        self.assignInitialValues(parent: parent, metalDevice: metalDevice)
        self.configureMetalView(metalDevice: metalDevice)
        self.addToParent(parent.cameraView)
        #endif
    }
}
private extension CameraMetalView {
    func assignInitialValues(parent: CameraManager, metalDevice: MTLDevice) {
        self.parent = parent
        self.ciContext = CIContext(mtlDevice: metalDevice)
        self.commandQueue = metalDevice.makeCommandQueue()
    }
    func configureMetalView(metalDevice: MTLDevice) {
        guard let cameraView = self.parent.cameraView else { return }
        cameraView.alpha = 0

        self.delegate = self
        self.device = metalDevice
        self.isPaused = true
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false
        self.autoResizeDrawable = false
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
    }
}


// MARK: - ANIMATIONS



// MARK: Camera Entrance
extension CameraMetalView {
    func performCameraEntranceAnimation() {
        #if targetEnvironment(simulator)
        // Skip animation in DEBUG mode if parent not set
        guard let parent = parent else {
            print("📷 DEBUG MODE: Skipping entrance animation (parent not set)")
            return
        }
        #endif
        
        UIView.animate(withDuration: 0.33) { [self] in
            parent.cameraView.alpha = 1
        }
    }
}

// MARK: Image Capture
extension CameraMetalView {
    func performImageCaptureAnimation() {
        guard let cameraView = parent.cameraView else { return }
        let blackMatte = createBlackMatte()

        cameraView.addSubview(blackMatte)
        animateBlackMatte(blackMatte)
    }
}
private extension CameraMetalView {
    func createBlackMatte() -> UIView {
        guard let cameraView = parent.cameraView else { return UIView() }
        let view = UIView()
        view.frame = cameraView.frame
        view.backgroundColor = .init(resource: .mijickBackgroundPrimary)
        view.alpha = 0
        return view
    }
    func animateBlackMatte(_ view: UIView) {
        UIView.animate(withDuration: 0.16, animations: { view.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.16, animations: { view.alpha = 0 }) { _ in
                view.removeFromSuperview()
            }
        }
    }
}

// MARK: Camera Flip
extension CameraMetalView {
    func beginCameraFlipAnimation() async {
        let snapshot = createSnapshot()
        isAnimating = true
        insertBlurView(snapshot)
        animateBlurFlip()

        await Task.sleep(seconds: 0.01)
    }
    func finishCameraFlipAnimation() async {
        guard let blurView = parent.cameraView.viewWithTag(.blurViewTag) else { return }

        await Task.sleep(seconds: 0.44)
        UIView.animate(withDuration: 0.3, animations: { blurView.alpha = 0 }) { [self] _ in
            blurView.removeFromSuperview()
            isAnimating = false
        }
    }
}
private extension CameraMetalView {
    func createSnapshot() -> UIImage? {
        guard let currentFrame else { return nil }

        let image = UIImage(ciImage: currentFrame)
        return image
    }
    func insertBlurView(_ snapshot: UIImage?) {
        guard let cameraView = parent.cameraView else { return }
        let blurView = UIImageView(frame: cameraView.frame)
        blurView.image = snapshot
        blurView.contentMode = .scaleAspectFill
        blurView.clipsToBounds = true
        blurView.tag = .blurViewTag
        blurView.applyBlurEffect(style: .regular)

        cameraView.addSubview(blurView)
    }
    func animateBlurFlip() {
        guard let cameraView = parent.cameraView else { return }
        UIView.transition(with: cameraView, duration: 0.44, options: cameraFlipAnimationTransition) {}
    }
}
private extension CameraMetalView {
    var cameraFlipAnimationTransition: UIView.AnimationOptions { parent.attributes.cameraPosition == .back ? .transitionFlipFromLeft : .transitionFlipFromRight }
}

// MARK: Session Pause
extension CameraMetalView {
    /// Covers the preview with a blurred copy of its last frame while the
    /// session is stopped. On restart the preview holds that frame until the
    /// device has settled (see `isPresentingFrames`), and the scene may be a
    /// different one by then, so the cover dissolves into the live feed
    /// instead of the frame underneath it being swapped in one step.
    func showPauseCover() {
        guard let cameraView = parent?.cameraView, cameraView.viewWithTag(.pauseCoverTag) == nil else { return }

        let cover = makePauseCover(width: cameraView.bounds.width)
        cover.tag = .pauseCoverTag
        cover.frame = cameraView.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cameraView.addSubview(cover)
    }
    func hidePauseCover() {
        guard let cover = parent?.cameraView?.viewWithTag(.pauseCoverTag) else { return }

        // Untagged first, so a pause during the fade gets a fresh cover.
        cover.tag = 0
        UIView.animate(withDuration: 0.3, animations: { cover.alpha = 0 }) { _ in
            cover.removeFromSuperview()
        }
    }
}
private extension CameraMetalView {
    func makePauseCover(width: CGFloat) -> UIView {
        // A rendered blur rather than a UIVisualEffectView: it adds no tint to
        // the frame, and its opacity can be animated, which an effect view's cannot.
        guard let snapshot = makeBlurredSnapshot(width: width) else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        }

        let imageView = UIImageView(image: snapshot)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }
    /// Rendered at point size, not sensor size: the result is blurred anyway
    /// and this runs on the main thread.
    func makeBlurredSnapshot(width: CGFloat) -> UIImage? {
        guard let frame = currentFrame, let ciContext, frame.extent.width > 0, width > 0 else { return nil }

        let scale = width / frame.extent.width
        let scaledFrame = frame.transformed(by: .init(scaleX: scale, y: scale))
        let blurredFrame = scaledFrame
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 30)
            .cropped(to: scaledFrame.extent)

        // Same color space the preview is drawn in, so the cover matches it.
        guard let cgImage = ciContext.createCGImage(blurredFrame, from: scaledFrame.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: Camera Focus
extension CameraMetalView {
    func performCameraFocusAnimation(touchPoint: CGPoint) {
        guard let cameraView = parent.cameraView else { return }
        removeExistingFocusIndicatorAnimations()

        let focusIndicator = focusIndicator.create(at: touchPoint)
        cameraView.addSubview(focusIndicator)
        animateFocusIndicator(focusIndicator)
    }
}
private extension CameraMetalView {
    func removeExistingFocusIndicatorAnimations() {
        guard let cameraView = parent.cameraView else { return }
        if let view = cameraView.viewWithTag(.focusIndicatorTag) {
            view.removeFromSuperview()
        }
    }
    func animateFocusIndicator(_ focusIndicator: UIImageView) {
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, animations: { focusIndicator.transform = .init(scaleX: 1, y: 1) }) { _ in
            UIView.animate(withDuration: 0.44, delay: 1.44, animations: { focusIndicator.alpha = 0.2 }) { _ in
                UIView.animate(withDuration: 0.44, delay: 1.44, animations: { focusIndicator.alpha = 0 })
            }
        }
    }
}

// MARK: Camera Orientation
extension CameraMetalView {
    func beginCameraOrientationAnimation(if shouldAnimate: Bool) async { if shouldAnimate {
        // Removed alpha manipulation - no black flash during orientation changes
        await Task.sleep(seconds: 0.1)
    }}
    func finishCameraOrientationAnimation(if shouldAnimate: Bool) { if shouldAnimate {
        // Removed alpha manipulation - smooth orientation transition
    }}
}


// MARK: - CAPTURING FRAMES



// MARK: Capture
extension CameraMetalView: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentFrame = captureCurrentFrame(cvImageBuffer)
        let currentFrameWithFiltersApplied = applyingFiltersToCurrentFrame(currentFrame)
        redrawCameraView(currentFrameWithFiltersApplied)
    }
}
private extension CameraMetalView {
    func captureCurrentFrame(_ cvImageBuffer: CVImageBuffer) -> CIImage {
        let currentFrame = CIImage(cvImageBuffer: cvImageBuffer)
        return currentFrame.oriented(parent.attributes.frameOrientation)
    }
    func applyingFiltersToCurrentFrame(_ currentFrame: CIImage) -> CIImage {
        currentFrame.applyingFilters(parent.attributes.cameraFilters)
    }
    func redrawCameraView(_ frame: CIImage) {
        currentFrame = frame
        if isPresentingFrames { draw() }
    }
}

// MARK: Draw
extension CameraMetalView: MTKViewDelegate {
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciImage = currentFrame,
              let currentDrawable = view.currentDrawable
        else { return }

        changeDrawableSize(view, ciImage)
        renderView(view, currentDrawable, commandBuffer, ciImage)
        commitBuffer(currentDrawable, commandBuffer)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
private extension CameraMetalView {
    func changeDrawableSize(_ view: MTKView, _ ciImage: CIImage) {
        view.drawableSize = ciImage.extent.size
    }
    func renderView(_ view: MTKView, _ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer, _ ciImage: CIImage) { ciContext.render(
        ciImage,
        to: currentDrawable.texture,
        commandBuffer: commandBuffer,
        bounds: .init(origin: .zero, size: view.drawableSize),
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )}
    func commitBuffer(_ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
