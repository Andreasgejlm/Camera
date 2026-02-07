//
//  Public+Model+MCameraMedia.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

// MARK: Getters
public extension MCameraMedia {
    /**
     Gets the image from the media object.
     */
    func getImage() -> UIImage? { image }

    /**
     Gets the video URL from the media object.
     */
    func getVideo() -> URL? { video }

    /**
     Gets the paired Live Photo movie URL from the media object.
     */
    func getLivePhotoMovie() -> URL? { livePhotoMovieURL }

    /**
     Gets the Live Photo representation from the media object.
     */
    func getLivePhoto() -> MCameraLivePhoto? { .init(media: self) }
}
