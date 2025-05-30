part of 'camera_preview_view.dart';

/// Khai báo các state của màn hình
abstract class _CameraPreviewState {}

/// State thông báo kèm message
class _InitState extends _CameraPreviewState {}

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