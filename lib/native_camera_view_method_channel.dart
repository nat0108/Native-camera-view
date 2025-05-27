import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_camera_view_platform_interface.dart';

/// An implementation of [NativeCameraViewPlatform] that uses method channels.
class MethodChannelNativeCameraView extends NativeCameraViewPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('native_camera_view');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
