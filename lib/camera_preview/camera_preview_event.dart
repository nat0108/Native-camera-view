part of 'camera_preview_view.dart';

/// Khai báo sự kiện giao tiếp giữa View và Bloc
abstract class _CameraPreviewEvent {}

/// Sự kiện khởi tạo màn hình
class InitEvent extends _CameraPreviewEvent {}

/// Gọi SnackBar
class ShowSnackBarEvent extends _CameraPreviewEvent {
  String message;
  ShowSnackBarEvent(this.message);
}



/// Pause camera