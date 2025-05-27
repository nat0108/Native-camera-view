part of 'camera_preview_view.dart';

/// Khai báo các state của màn hình
abstract class _CameraPreviewState {}

/// State thông báo kèm message
class _InitState extends _CameraPreviewState {}

/// State thông báo kèm message
class _AlertState extends _CameraPreviewState {
  /// Message thông báo
  final String message;

  _AlertState(this.message);
}

/// Gọi SnackBar
class ShowSnackBarState extends _CameraPreviewState {
  String message;
  ShowSnackBarState(this.message);
}

/// Preview anh da chup
class DisplayPictureState extends _CameraPreviewState {
  String filePath;
  DisplayPictureState(this.filePath);
}

/// State màn hình hiển thị giao diện chính
class _CompleteState extends _CameraPreviewState {}