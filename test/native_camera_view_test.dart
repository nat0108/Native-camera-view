import 'package:flutter_test/flutter_test.dart';
import 'package:native_camera_view/native_camera_view.dart';
import 'package:native_camera_view/native_camera_view_platform_interface.dart';
import 'package:native_camera_view/native_camera_view_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNativeCameraViewPlatform
    with MockPlatformInterfaceMixin
    implements NativeCameraViewPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NativeCameraViewPlatform initialPlatform = NativeCameraViewPlatform.instance;

  test('$MethodChannelNativeCameraView is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNativeCameraView>());
  });

  test('getPlatformVersion', () async {
    NativeCameraView nativeCameraViewPlugin = NativeCameraView();
    MockNativeCameraViewPlatform fakePlatform = MockNativeCameraViewPlatform();
    NativeCameraViewPlatform.instance = fakePlatform;

    expect(await nativeCameraViewPlugin.getPlatformVersion(), '42');
  });
}
