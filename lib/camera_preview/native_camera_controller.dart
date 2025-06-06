// lib/camera/native_camera_controller.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// Import service class giao tiếp với native MethodChannel của bạn
import '../camera_controller.dart';

/// Quản lý trạng thái và logic cho NativeCameraView.
class NativeCameraController {
  /// Controller để giao tiếp với native qua MethodChannel.
  /// Sẽ được khởi tạo trong `onPlatformViewCreated`.
  CameraController? _nativeServiceController;

  /// Callback để truyền `CameraController` đã được khởi tạo lên widget cha.
  final Function(CameraController controller) onControllerCreated;

  // --- Các ValueNotifier để quản lý trạng thái ---
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<bool> isPermissionGranted = ValueNotifier(false);

  /// Dùng cho các sự kiện chỉ xảy ra một lần, ví dụ như hiển thị SnackBar.
  final ValueNotifier<String?> snackbarMessage = ValueNotifier(null);

  /// Constructor: Nhận callback và bắt đầu xin quyền ngay lập tức.
  NativeCameraController({required this.onControllerCreated}) {
    requestCameraPermission();
  }

  // --- Các phương thức logic ---

  /// Được gọi từ view khi native PlatformView đã sẵn sàng.
  void onPlatformViewCreated(int id) {
    const String baseChannelName = "com.plugin.camera_native.native_camera_view/camera_method_channel";
    final String channelName = Platform.isIOS ? '${baseChannelName}_ios_$id' : '${baseChannelName}_$id';

    final platformChannel = MethodChannel(channelName);
    _nativeServiceController = CameraController(channel: platformChannel);

    // Truyền controller đã tạo lên widget cha thông qua callback.
    onControllerCreated(_nativeServiceController!);

    debugPrint('PlatformView (id: $id) created. CameraController initialized on channel: $channelName');
  }

  /// Yêu cầu quyền truy cập camera từ người dùng.
  Future<void> requestCameraPermission() async {
    isLoading.value = true;
    if (Platform.isIOS) {
      // Đối với iOS, native code sẽ tự xử lý việc xin quyền.
      // Chúng ta lạc quan coi như quyền đã được cấp để build UI.
      debugPrint("[Flutter Permission] Skipping Dart permission request for iOS. Native will handle.");
      isPermissionGranted.value = true;
    } else if (Platform.isAndroid) {
      debugPrint("[Flutter Permission] Requesting camera permission on Android...");
      final status = await Permission.camera.request();
      debugPrint("[Flutter Permission] Android status received: ${status.name}");
      isPermissionGranted.value = status.isGranted;
      if (!status.isGranted) {
        snackbarMessage.value = 'Quyền truy cập camera bị từ chối (${status.name}).';
      }
    } else {
      snackbarMessage.value = 'Camera không được hỗ trợ trên nền tảng này.';
    }
    isLoading.value = false;
  }

  /// Xóa tin nhắn snackbar sau khi đã hiển thị.
  void clearSnackbarMessage() {
    snackbarMessage.value = null;
  }

  /// Dọn dẹp tài nguyên để tránh rò rỉ bộ nhớ.
  void dispose() {
    isLoading.dispose();
    isPermissionGranted.dispose();
    snackbarMessage.dispose();
    _nativeServiceController = null;
    debugPrint("NativeCameraController disposed.");
  }
}