//
//  PhotoAspectRatioCrop.swift of MijickCamera
//
//  Crops a captured photo to a CameraAspectRatio. The sensor delivers 4:3, so
//  1:1 and 16:9 are centre crops of it, as in the Camera app; the camera
//  preview fills its frame the same way (scale to fill, centred), so what the
//  host shows in a frame of that shape is what the photo keeps.


import UIKit
import ImageIO

enum PhotoAspectRatioCrop {
    /// Returns the image cropped from its centre, with the pixel sizes in the
    /// metadata updated to match. Nothing changes without a ratio, or when the
    /// image already has it.
    static func apply(_ aspectRatio: CameraAspectRatio?, to image: UIImage?, metadata: [String: Any]?) -> (image: UIImage?, metadata: [String: Any]?) {
        guard let aspectRatio,
              let image,
              let cgImage = image.cgImage,
              let rect = cropRect(width: cgImage.width, height: cgImage.height, longToShortRatio: aspectRatio.longToShortRatio),
              let cropped = cgImage.cropping(to: rect)
        else { return (image, metadata) }

        // Cropping the stored pixels from the centre gives the same result in
        // every orientation, since the long side stays the long side; the
        // orientation is kept as it was.
        let croppedImage = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        return (croppedImage, updatingPixelSize(of: metadata, width: cropped.width, height: cropped.height))
    }

    /// The centred rect of the given long-to-short ratio, in the image's
    /// stored pixels, or nil when the image already has that shape.
    static func cropRect(width: Int, height: Int, longToShortRatio: CGFloat) -> CGRect? {
        guard width > 0, height > 0 else { return nil }

        let isLandscape = width >= height
        let long = CGFloat(max(width, height)), short = CGFloat(min(width, height))
        var targetLong = long, targetShort = short
        if long / short > longToShortRatio { targetLong = (short * longToShortRatio).rounded(.down) }
        else { targetShort = (long / longToShortRatio).rounded(.down) }
        guard targetLong != long || targetShort != short else { return nil }

        let targetWidth = isLandscape ? targetLong : targetShort
        let targetHeight = isLandscape ? targetShort : targetLong
        return CGRect(
            x: ((CGFloat(width) - targetWidth) / 2).rounded(.down),
            y: ((CGFloat(height) - targetHeight) / 2).rounded(.down),
            width: targetWidth,
            height: targetHeight
        )
    }
}
private extension PhotoAspectRatioCrop {
    static func updatingPixelSize(of metadata: [String: Any]?, width: Int, height: Int) -> [String: Any]? {
        guard var metadata else { return nil }

        if metadata[kCGImagePropertyPixelWidth as String] != nil { metadata[kCGImagePropertyPixelWidth as String] = width }
        if metadata[kCGImagePropertyPixelHeight as String] != nil { metadata[kCGImagePropertyPixelHeight as String] = height }
        if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = width
            exif[kCGImagePropertyExifPixelYDimension as String] = height
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }
        return metadata
    }
}
