//
//  MCameraMedia.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

public struct MCameraMedia: Sendable {
    let image: UIImage?
    let video: URL?
    let livePhotoMovieURL: URL?
    // Store metadata as raw Data to keep Sendable conformance (e.g., EXIF/XMP blob)
    let metadata: Data?

    // Legacy initializer - maintains backward compatibility
    init?(data: Any?) {
        if let image = data as? UIImage {
            self.image = image
            self.video = nil
            self.livePhotoMovieURL = nil
            self.metadata = nil
        }
        else if let video = data as? URL {
            self.video = video
            self.image = nil
            self.livePhotoMovieURL = nil
            self.metadata = nil
        }
        else {
            return nil
        }
    }

    // New initializer for captured photo with preserved metadata (raw data)
    init(image: UIImage?, metadata: Data? = nil, livePhotoMovieURL: URL? = nil) {
        self.image = image
        self.video = nil
        self.livePhotoMovieURL = livePhotoMovieURL
        self.metadata = metadata
    }

    // Convenience initializer for legacy dictionary metadata; encodes to Data if possible
    init(image: UIImage?, metadata: [String: Any]? = nil, livePhotoMovieURL: URL? = nil) {
        self.image = image
        self.video = nil
        self.livePhotoMovieURL = livePhotoMovieURL
        // Attempt to serialize metadata dictionary to Data in a stable way
        if metadata == nil {
            self.metadata = nil
            return
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0) {
            self.metadata = data
        } else {
            self.metadata = nil
        }
    }

    // New initializer for video (future-proofing)
    init(video: URL, metadata: Data? = nil) {
        self.video = video
        self.image = nil
        self.livePhotoMovieURL = nil
        self.metadata = metadata
    }

    // Helper to check if metadata is preserved
    var hasMetadata: Bool {
        return metadata != nil && !(metadata?.isEmpty ?? true)
    }
    var hasLivePhotoMovie: Bool {
        livePhotoMovieURL != nil
    }
}

// MARK: Equatable
extension MCameraMedia: Equatable {
    public static func == (lhs: MCameraMedia, rhs: MCameraMedia) -> Bool {
        // Compare core media content
        let imageEqual = lhs.image == rhs.image
        let videoEqual = lhs.video == rhs.video
        let livePhotoMovieEqual = lhs.livePhotoMovieURL == rhs.livePhotoMovieURL
        let metadataDataEqual = lhs.metadata == rhs.metadata
        return imageEqual && videoEqual && livePhotoMovieEqual && metadataDataEqual
    }
}

extension MCameraMedia {
    /// Decode metadata as property list if possible.
    public var metadataDictionary: [String: Any]? {
        guard let data = metadata else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data,
                                                            options: [],
                                                            format: nil)) as? [String: Any]
    }
    
    /// Debug print the metadata dictionary, falling back to base64 if not decodable.
    public func printMetadata() {
        if let dict = metadataDictionary {
            print("📎 Metadata dictionary:")
            //dump(dict) // Swift’s built-in recursive pretty-printer
        } else if let data = metadata {
            //print("📎 Metadata raw bytes (\(data.count)):")
            //print(data.base64EncodedString())
        } else {
            print("📎 No metadata")
        }
    }
}
