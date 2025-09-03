// File: lib/camera_controller.dart
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint, ValueNotifier; // Chỉ dùng cho debug

// Enum để định nghĩa các chế độ fit cho camera preview
enum CameraPreviewFit {
  fitWidth,
  fitHeight,
  contain,
  cover,
}
class CameraController {
  final MethodChannel _channel;

  bool _isFrontCamera = false;
  bool get isFrontCamera => _isFrontCamera;

  final ValueNotifier<bool> isPaused = ValueNotifier(false);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  // Constructor nhận một MethodChannel đã được khởi tạo.
  // MethodChannel này phải có tên khớp với tên được đăng ký ở phía native.
  CameraController({required MethodChannel channel}) : _channel = channel {
    // Lắng nghe các lệnh từ native
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onCameraReady':
        if (isLoading.value) isLoading.value = false;
        break;
      case 'onCameraError':
        if (isLoading.value) isLoading.value = false;
        final Map? args = call.arguments as Map?;
        errorMessage.value = args?['message'] ?? "Unknown camera error";
        break;
      // case 'onCameraPaused':
      //   if (!isPaused.value) isPaused.value = true;
      //   break;
      // case 'onCameraResumed':
      //   if (isPaused.value) isPaused.value = false;
      //   break;
    }
  }

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
    } on PlatformException catch (e) {
      debugPrint("CameraController: Failed to send initialize command: '${e.message}'.");
    }
  }

  /// Yêu cầu native code chụp ảnh.
  /// Trả về đường dẫn (String) của file ảnh đã lưu nếu thành công, ngược lại trả về null.
  Future<String?> captureImage() async {
    try {
      // Gọi method 'captureImage' trên MethodChannel.
      final String? filePath = await _channel.invokeMethod('captureImage');
      debugPrint('CameraController: Ảnh đã được chụp và lưu tại: $filePath');
      return filePath;
    } on PlatformException catch (e) {
      // Xử lý lỗi nếu có vấn đề khi gọi xuống native.
      debugPrint("CameraController: Chụp ảnh thất bại: '${e.message}'.");
      // Bạn có thể chọn re-throw lỗi hoặc trả về null tùy theo cách xử lý lỗi ở UI.
      // throw Exception("Failed to capture image: ${e.message}");
      return null;
    }
  }

  /// Yêu cầu native code tạm dừng camera.
  Future<void> pauseCamera() async {
    try {
      // Gọi method 'pauseCamera' trên MethodChannel.
      await _channel.invokeMethod('pauseCamera');
      isPaused.value = true;
      debugPrint('CameraController: Lệnh pause camera đã gửi.');
    } on PlatformException catch (e) {
      debugPrint("CameraController: Lỗi khi pause camera: '${e.message}'.");
      // throw Exception("Failed to pause camera: ${e.message}");
    }
  }

  /// Yêu cầu native code tiếp tục (resume) camera.
  Future<void> resumeCamera() async {
    try {
      // Gọi method 'resumeCamera' trên MethodChannel.
      await _channel.invokeMethod('resumeCamera');
      isPaused.value = false;
      debugPrint('CameraController: Lệnh resume camera đã gửi.');
    } on PlatformException catch (e) {
      debugPrint("CameraController: Lỗi khi resume camera: '${e.message}'.");
      // throw Exception("Failed to resume camera: ${e.message}");
    }
  }

  /// Yêu cầu native code chuyển đổi giữa camera trước và sau.
  /// [useFrontCamera]: true nếu muốn sử dụng camera trước, false cho camera sau.
  Future<void> switchCamera(bool useFrontCamera) async {
    try {
      // Gọi method 'switchCamera' trên MethodChannel,
      // truyền một Map làm arguments.
      await _channel.invokeMethod('switchCamera', {'useFrontCamera': useFrontCamera});
      debugPrint('CameraController: Lệnh switch camera (useFront: $useFrontCamera) đã gửi.');
      _isFrontCamera = useFrontCamera;
    } on PlatformException catch (e) {
      debugPrint("CameraController: Lỗi khi chuyển camera: '${e.message}'.");
      // throw Exception("Failed to switch camera: ${e.message}");
    }
  }

  /// Yêu cầu native code xóa tất cả các ảnh đã được chụp và lưu trong thư mục tạm/cache của plugin.
  /// Trả về true nếu thành công (hoặc không có gì để xóa), false nếu có lỗi hoặc không thành công.
  Future<bool> deleteAllCapturedPhotos() async {
    try {
      // Gọi method 'deleteAllCapturedPhotos' trên MethodChannel.
      // Native code sẽ trả về true nếu xóa thành công hoặc không có gì để xóa,
      // và false nếu có lỗi trong quá trình xóa.
      final bool? success = await _channel.invokeMethod('deleteAllCapturedPhotos');
      if (success == true) {
        debugPrint('CameraController: Tất cả ảnh đã chụp đã được xóa (hoặc không có ảnh nào để xóa).');
        return true;
      } else {
        // Bao gồm trường hợp success là null (lỗi giao tiếp) hoặc false (native báo lỗi)
        debugPrint('CameraController: Xóa ảnh thất bại hoặc không có phản hồi thành công từ native.');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint("CameraController: Lỗi khi gọi deleteAllCapturedPhotos: '${e.message}'.");
      return false; // Coi như thất bại nếu có PlatformException
    }
  }

  void dispose() {
    isPaused.dispose();
    isLoading.dispose();
    _channel.setMethodCallHandler(null);
  }
}
