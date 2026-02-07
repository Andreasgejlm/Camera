//
//  FileManager++.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

// MARK: Prepare Place for Video Output
extension FileManager {
    static func prepareURLForVideoOutput() -> URL? {
        guard let fileUrl = getDocumentsFileUrl(path: videoPath) else { return nil }

        clearPlaceIfTaken(fileUrl)
        return fileUrl
    }

    static func prepareURLForLivePhotoMovieOutput() -> URL? {
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(livePhotoPath)
        clearPlaceIfTaken(fileUrl)
        return fileUrl
    }

    static func clearFileIfExists(_ url: URL?) {
        guard let url else { return }
        clearPlaceIfTaken(url)
    }
}
private extension FileManager {
    static func getDocumentsFileUrl(path: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(path)
    }
    static func clearPlaceIfTaken(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
private extension FileManager {
    static var videoPath: String {
        let id: String = UUID().uuidString
        return "mijick-camera-video-output-\(id).mp4"
    }
    static var livePhotoPath: String {
        let id: String = UUID().uuidString
        return "mijick-camera-live-photo-output-\(id).mov"
    }
}
