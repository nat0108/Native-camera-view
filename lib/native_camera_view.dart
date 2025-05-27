
import 'native_camera_view_platform_interface.dart';

class NativeCameraView {
  Future<String?> getPlatformVersion() {
    return NativeCameraViewPlatform.instance.getPlatformVersion();
  }
}
