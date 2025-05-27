import Flutter
import UIKit

public class NativeCameraViewPlugin: NSObject, FlutterPlugin {
   public static func register(with registrar: FlutterPluginRegistrar) {
     let viewType = "com.plugin.camera_native.native_camera_view/camera_preview_ios" // Khớp với Dart
     let factory = CameraPlatformViewFactory(messenger: registrar.messenger())
     registrar.register(factory, withId: viewType)
     print("SwiftNativeCameraViewPlugin: Factory registered with viewType: \(viewType)")
   }
 }
}
