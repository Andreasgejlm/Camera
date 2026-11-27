//
//  CameraView+FocusIndicator.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

@MainActor class CameraFocusIndicatorView {
    var image: UIImage = .init(resource: .mijickIconCrosshair)
    var tintColor: UIColor = .init(resource: .mijickBackgroundYellow)
    var size: CGFloat = 90
}

// MARK: Create
extension CameraFocusIndicatorView {
    func create(at touchPoint: CGPoint, in bounds: CGRect, state: CameraFocusIndicatorContainer.State, showsExposureControl: Bool) -> CameraFocusIndicatorContainer {
        let indicator = CameraFocusIndicatorContainer(image: image, tintColor: tintColor, size: size, showsExposureControl: showsExposureControl)
        indicator.state = state
        indicator.frame = .init(x: touchPoint.x - size / 2, y: touchPoint.y - size / 2, width: size, height: size)
        // The sun goes on the side with room for it, as in the Camera app.
        indicator.sunSide = touchPoint.x + size / 2 + CameraFocusIndicatorContainer.sunReach > bounds.maxX ? .leading : .trailing
        indicator.transform = .init(scaleX: 0, y: 0)
        indicator.tag = .focusIndicatorTag
        return indicator
    }
}


// MARK: - CONTAINER



/// The focus square, with the exposure sun beside it. The sun moves up and
/// down a line while the exposure is dragged; the line shows only then.
@MainActor final class CameraFocusIndicatorContainer: UIView {
    enum SunSide { case leading, trailing }
    /// `pendingLock`: the preview is held and the lock has not taken yet.
    enum State { case focused, pendingLock, locked }

    static let sunSize: CGFloat = 22
    static let sunGap: CGFloat = 12
    static var sunReach: CGFloat { sunGap + sunSize }

    var state: State = .focused
    var isLocked: Bool { state == .locked }
    var sunSide: SunSide = .trailing { didSet { setNeedsLayout() } }
    /// Position of the sun along its line, from -1 (bottom) to 1 (top).
    var exposureFraction: CGFloat = 0 { didSet { setNeedsLayout() } }

    private let squareView: UIImageView
    private let sunView: UIImageView?
    private let upperLine: UIView = .init()
    private let lowerLine: UIView = .init()

    init(image: UIImage, tintColor: UIColor, size: CGFloat, showsExposureControl: Bool) {
        squareView = .init(image: image)
        sunView = showsExposureControl ? .init(image: UIImage(systemName: "sun.max.fill")) : nil
        super.init(frame: .init(origin: .zero, size: .init(width: size, height: size)))

        isUserInteractionEnabled = false
        clipsToBounds = false
        squareView.contentMode = .scaleAspectFit
        squareView.tintColor = tintColor
        addSubview(squareView)

        guard let sunView else { return }
        sunView.contentMode = .scaleAspectFit
        sunView.tintColor = tintColor
        for line in [upperLine, lowerLine] {
            line.backgroundColor = tintColor
            line.alpha = 0
            addSubview(line)
        }
        addSubview(sunView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Laid out from bounds, which a scale transform leaves alone.
        let size = bounds.width
        squareView.frame = bounds

        guard let sunView else { return }
        let sunSize = Self.sunSize
        let travel = Self.sunTravel(size: size)
        let centerX = sunSide == .trailing ? size + Self.sunGap + sunSize / 2 : -Self.sunGap - sunSize / 2
        let centerY = size / 2 - exposureFraction * travel
        sunView.frame = .init(x: centerX - sunSize / 2, y: centerY - sunSize / 2, width: sunSize, height: sunSize)

        let lineTop = size / 2 - travel - sunSize / 2
        let lineBottom = size / 2 + travel + sunSize / 2
        let gap: CGFloat = 4
        let upperBottom = centerY - sunSize / 2 - gap
        let lowerTop = centerY + sunSize / 2 + gap
        upperLine.frame = .init(x: centerX - 0.5, y: lineTop, width: 1, height: max(0, upperBottom - lineTop))
        lowerLine.frame = .init(x: centerX - 0.5, y: lowerTop, width: 1, height: max(0, lineBottom - lowerTop))
    }
    /// The square's opacity rises and falls three times a second while the
    /// lock is pending, as in the Camera app. Ease-in-out half cycles that
    /// reverse give a close match to a sine wave.
    func startThrob() {
        let throb = CABasicAnimation(keyPath: "opacity")
        throb.fromValue = 1
        throb.toValue = 0.35
        throb.duration = 1 / 6
        throb.autoreverses = true
        throb.repeatCount = .infinity
        throb.timingFunction = .init(name: .easeInEaseOut)
        squareView.layer.add(throb, forKey: Self.throbKey)
    }
    func stopThrob() {
        squareView.layer.removeAnimation(forKey: Self.throbKey)
    }
    private static let throbKey = "throb"

    /// How far the sun travels either way from the middle of its line.
    private static func sunTravel(size: CGFloat) -> CGFloat { size * 0.75 }
    /// Margin around the square, the sun and its line in which an exposure drag may start.
    static let exposureDragMargin: CGFloat = 24
    /// Where an exposure drag may start: the square, the sun and the whole of
    /// its line, with a margin. In the coordinates of a square of `size` whose
    /// origin is its top leading corner.
    static func exposureDragArea(size: CGFloat, sunSide: SunSide) -> CGRect {
        let travel = Self.sunTravel(size: size)
        let lineTop = size / 2 - travel - sunSize / 2
        let lineBottom = size / 2 + travel + sunSize / 2
        let minX = sunSide == .trailing ? 0 : -sunReach
        return CGRect(x: minX, y: lineTop, width: size + sunReach, height: lineBottom - lineTop).insetBy(dx: -exposureDragMargin, dy: -exposureDragMargin)
    }
    /// The same area in the superview's coordinates. From the centre and
    /// bounds, which the entrance and lock animations' scale leaves alone.
    var exposureDragArea: CGRect {
        Self.exposureDragArea(size: bounds.width, sunSide: sunSide).offsetBy(dx: center.x - bounds.width / 2, dy: center.y - bounds.height / 2)
    }

    func setExposureLineVisible(_ isVisible: Bool) {
        UIView.animate(withDuration: 0.2) { [self] in
            upperLine.alpha = isVisible ? 1 : 0
            lowerLine.alpha = isVisible ? 1 : 0
        }
    }
}
