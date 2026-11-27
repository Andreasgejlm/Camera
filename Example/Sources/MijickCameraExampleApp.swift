//
//  MijickCameraExampleApp.swift
//  MijickCameraExample
//
//  The default MijickCamera screens. In the iOS Simulator, run Viewfinder on the
//  Mac to give the simulator a camera; without it the camera runs on mocks.
//

import AVKit
import MijickCamera
import SwiftUI

@main
struct MijickCameraExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class AppDelegate: NSObject, MApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

struct ContentView: View {
    @State private var capture: Capture?

    var body: some View {
        MCamera()
            .lockCameraInPortraitOrientation(AppDelegate.self)
            .onImageCaptured { media, controller in
                if let image = media.getImage() { capture = .photo(image) }
                controller.reopenCameraScreen()
            }
            .onVideoCaptured { url, controller in
                capture = .video(url)
                controller.reopenCameraScreen()
            }
            .startSession()
            .sheet(item: $capture) { CaptureView(capture: $0) }
    }
}

enum Capture: Identifiable {
    case photo(UIImage)
    case video(URL)

    var id: String {
        switch self {
        case .photo(let image): "photo-\(ObjectIdentifier(image).hashValue)"
        case .video(let url): url.absoluteString
        }
    }
}

struct CaptureView: View {
    let capture: Capture

    var body: some View {
        NavigationStack {
            Group {
                switch capture {
                case .photo(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .navigationTitle("Photo \(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale))")
                case .video(let url):
                    VideoPlayer(player: AVPlayer(url: url))
                        .navigationTitle("Video")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
