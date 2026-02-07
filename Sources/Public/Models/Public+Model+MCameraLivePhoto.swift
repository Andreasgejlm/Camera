//
//  Public+Model+MCameraLivePhoto.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

public struct MCameraLivePhoto: Sendable {
    let image: UIImage?
    let pairedVideo: URL
    let metadata: Data?
}

extension MCameraLivePhoto {
    init?(media: MCameraMedia) {
        guard let pairedVideo = media.livePhotoMovieURL else { return nil }

        self.image = media.image
        self.pairedVideo = pairedVideo
        self.metadata = media.metadata
    }
}

public extension MCameraLivePhoto {
    /**
     Gets the still image from the Live Photo.
     */
    func getImage() -> UIImage? { image }

    /**
     Gets the paired movie URL from the Live Photo.
     */
    func getPairedVideo() -> URL { pairedVideo }
}
