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
    func create(at touchPoint: CGPoint, in bounds: CGRect, isLocked: Bool, showsExposureControl: Bool) -> CameraFocusIndicatorContainer {
        let indicator = CameraFocusIndicatorContainer(image: image, tintColor: tintColor, size: size, showsExposureControl: showsExposureControl)
        indicator.isLocked = isLocked
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

    static let sunSize: CGFloat = 22
    static let sunGap: CGFloat = 12
    static var sunReach: CGFloat { sunGap + sunSize }

    var isLocked: Bool = false
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
        let travel = size * 0.75
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
    func setExposureLineVisible(_ isVisible: Bool) {
        UIView.animate(withDuration: 0.2) { [self] in
            upperLine.alpha = isVisible ? 1 : 0
            lowerLine.alpha = isVisible ? 1 : 0
        }
    }
}
