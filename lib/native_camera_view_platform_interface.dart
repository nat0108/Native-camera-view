import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'native_camera_view_method_channel.dart';

abstract class NativeCameraViewPlatform extends PlatformInterface {
  /// Constructs a NativeCameraViewPlatform.
  NativeCameraViewPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeCameraViewPlatform _instance = MethodChannelNativeCameraView();

  /// The default instance of [NativeCameraViewPlatform] to use.
  ///
  /// Defaults to [MethodChannelNativeCameraView].
  static NativeCameraViewPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NativeCameraViewPlatform] when
  /// they register themselves.
  static set instance(NativeCameraViewPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
