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

  /// SỬA ĐỔI HÀM NÀY ĐỂ XỬ LÝ QUYỀN ĐÚNG CÁCH
  /// Yêu cầu quyền truy cập camera từ người dùng.
  Future<void> requestCameraPermission() async {
    isLoading.value = true;

    // Đối với CẢ iOS và Android, chúng ta sẽ để cho native view tự xử lý việc
    // kiểm tra quyền và hiển thị dialog. Vai trò của Flutter chỉ là build native view.
    debugPrint("[Flutter Permission] Skipping Dart permission request. Native will handle it.");
    isPermissionGranted.value = true;

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