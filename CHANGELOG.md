## 0.0.11
* Fixed `loadingWidget`

## 0.0.11
* Add `loadingWidget`

## 0.0.10
* Add `bypassPermissionCheck` parameter to ignore camera permission check

## 0.0.9
* Removed `permission_handler`
* Fixed camera on IOS

## 0.0.8
* Fixed an issue where photos were rotated when shooting in cover and pause camera modes on IOS
* Fixed the error of switching the front and rear cameras on IOS

## 0.0.7
* Fixed contain view IOS

## 0.0.6
* Update `permission_handler` to `12.0.0+1`

## 0.0.5

### BREAKING CHANGES

* **Architectural Refactor & State Management:**
  * **Removed `flutter_bloc`:** The dependency on `flutter_bloc` has been completely removed. State management is now handled by a simpler controller pattern using `ValueNotifier` and `Listenable`. Code using `BlocProvider` or `BlocBuilder` must be migrated.
  * **Renamed Main Widget:** The primary widget `CameraPreviewView` has been renamed to `NativeCameraView` for better clarity and consistency. All implementations must be updated.
* **Simplified Package Structure:**
  * **Removed `plugin_platform_interface`:** This dependency has been removed to streamline the package architecture.

## 0.0.4

* **iOS:**
  * **Critical Stability Fix (Lifecycle & Deinit):** Resolved persistent `EXC_BREAKPOINT` / `EXC_BAD_ACCESS` crashes during `deinit` by implementing a more robust and synchronized AVFoundation resource cleanup on the `sessionQueue`. This includes corrected order for removing outputs and nilling delegates (delegate is nilled *after* removal from session, all within the same synchronized block).
  * **Preview Fit Enhancement (`contain` mode):** Implemented top-alignment for the "contain" preview mode. When this mode is active, if the camera video's aspect ratio (when scaled to fill the view's width) results in a height shorter than the view, the preview will now fill the width and align to the top, rather than being vertically centered.
  * **Feature: WYSIWYG Photo Cropping for "cover" mode (iOS):** Captured photos in "cover" mode are now automatically cropped using Core Graphics to precisely match the visible area of the `AVCaptureVideoPreviewLayer`. This calculation uses `metadataOutputRectConverted(fromLayerRect:)` and the cropping process is performed asynchronously.
  * **Swift Code Correctness:** Fixed a `'guard' body must not fall through` compiler warning in `setupCamera` by using `throw` for early exit within a `do-catch` block, improving the reliability of camera configuration.
  * Enhanced internal logging for easier debugging of camera lifecycle and preview adjustments.
* **Android:**
  * **Feature: WYSIWYG Photo Cropping for "cover" mode.**
    * Implemented photo cropping for the "cover" preview fit mode (which uses `PreviewView.ScaleType.FILL_CENTER` on Android). Photos captured using `ImageCapture` are now automatically cropped to match the visible area displayed in the `PreviewView`.
    * This provides a "What You See Is What You Get" (WYSIWYG) experience, ensuring the final saved image corresponds to what the user saw.
    * The cropping logic involves `Bitmap` manipulation and correctly handles EXIF orientation of the original image to ensure accurate cropping results.

## 0.0.3

* **iOS:** Enhanced camera stability, fixed critical lifecycle bugs, and improved feature reliability.
  * Resolved `EXC_BAD_ACCESS` crashes encountered during camera switching by overhauling the resource deallocation process (`deinit`) and ensuring thread-safe operations for AVFoundation objects.
  * Corrected `switchCamera` behavior: The iOS native side now allows Flutter to manage view recreation, preventing conflicting camera setups and teardowns between old and new platform view instances.
  * Fixed an `NSGenericException` caused by improper `AVCaptureSession startRunning()` calls relative to `beginConfiguration`/`commitConfiguration`.
  * Addressed Swift-specific issues: resolved a force-unwrap error on non-optional `AVCaptureDevice` and a `guard` statement fall-through warning during camera setup, improving code correctness.
  * Significantly improved the "capture last frame on pause" feature by utilizing `AVCaptureVideoDataOutput` for more reliable frame grabbing, fixing previous issues that resulted in blank images.
  * Strengthened `isDeinitializing` checks in delegate callbacks and various functions to improve safety during instance deallocation.
  * Ensured each `CameraPlatformView` instance uses unique `DispatchQueue` instances for its `sessionQueue` and `videoDataOutputQueue` to prevent potential cross-instance conflicts.


## 0.0.2

* Update Example, Readme.md


## 0.0.1

* TODO: Describe initial release.

