//
//  MCamera+Config.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import AVFoundation

extension MCamera { @MainActor class Config {
    // MARK: Screens
    var cameraScreen: CameraScreenBuilder = DefaultCameraScreen.init
    var capturedMediaScreen: CapturedMediaScreenBuilder? = DefaultCapturedMediaScreen.init
    var errorScreen: ErrorScreenBuilder = DefaultCameraErrorScreen.init

    // MARK: Actions
    var imageCapturedAction: (UIImage, [String: Any]?, AVCaptureVideoOrientation, MCamera.Controller) -> () = { _,_,_,_ in }
    var videoCapturedAction: (URL, MCamera.Controller) -> () = { _,_ in }
    var closeMCameraAction: () -> () = {}

    // MARK: Others
    var appDelegate: MApplicationDelegate.Type? = nil
    var isCameraConfigured: Bool = false
}}
