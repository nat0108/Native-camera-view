# Changelog

## 0.0.6
- Updated `permission_handler` to `12.0.0+1`.

## 0.0.5
### Architecture & API
- Removed dependency on `flutter_bloc`. State management now uses `ValueNotifier` & `Listenable`.
- Renamed main widget from `CameraPreviewView` to `NativeCameraView`.
- Removed `plugin_platform_interface` for a simpler package structure.

## 0.0.4
### iOS
- Fixed `EXC_BAD_ACCESS` crash during `deinit` by improving resource cleanup.
- Improved `contain` preview mode: aligned preview to top instead of center.
- Implemented **WYSIWYG photo cropping** in `cover` mode using `AVCaptureVideoPreviewLayer`.
- Fixed Swift `guard` warning and enhanced internal debug logging.

### Android
- Added **WYSIWYG photo cropping** in `cover` mode using `Bitmap` and EXIF orientation handling.

## 0.0.3
### iOS Stability Improvements
- Fixed camera switch crash (`EXC_BAD_ACCESS`, `NSGenericException`) by synchronizing `deinit` logic.
- Refactored `switchCamera` to avoid duplicate view conflicts.
- Improved last-frame capture logic using `VideoDataOutput`.
- Fixed force-unwrap and Swift guard handling.
- Ensured each `CameraPlatformView` uses separate `DispatchQueue` instances.

## 0.0.2
- Updated example project and `README.md`.

## 0.0.1
- Initial release.
