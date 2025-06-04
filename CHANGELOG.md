## 0.0.1

* TODO: Describe initial release.

## 0.0.2

* Update Example, Readme.md

## 0.0.3

* **iOS:** Enhanced camera stability, fixed critical lifecycle bugs, and improved feature reliability.
    * Resolved `EXC_BAD_ACCESS` crashes encountered during camera switching by overhauling the resource deallocation process (`deinit`) and ensuring thread-safe operations for AVFoundation objects.
    * Corrected `switchCamera` behavior: The iOS native side now allows Flutter to manage view recreation, preventing conflicting camera setups and teardowns between old and new platform view instances.
    * Fixed an `NSGenericException` caused by improper `AVCaptureSession startRunning()` calls relative to `beginConfiguration`/`commitConfiguration`.
    * Addressed Swift-specific issues: resolved a force-unwrap error on non-optional `AVCaptureDevice` and a `guard` statement fall-through warning during camera setup, improving code correctness.
    * Significantly improved the "capture last frame on pause" feature by utilizing `AVCaptureVideoDataOutput` for more reliable frame grabbing, fixing previous issues that resulted in blank images.
    * Strengthened `isDeinitializing` checks in delegate callbacks and various functions to improve safety during instance deallocation.
    * Ensured each `CameraPlatformView` instance uses unique `DispatchQueue` instances for its `sessionQueue` and `videoDataOutputQueue` to prevent potential cross-instance conflicts.

## 0.0.4

* **iOS:**
  * **Critical Stability Fix (Lifecycle & Deinit):** Resolved persistent `EXC_BREAKPOINT` / `EXC_BAD_ACCESS` crashes that occurred during the deinitialization (`deinit`) of the camera view, especially when rapidly switching cameras or changing `cameraPreviewFit` modes.
    * Implemented a more robust deinitialization sequence by consolidating all AVFoundation object cleanup (stopping session, removing all inputs/outputs, and critically, nilling the `AVCaptureVideoDataOutput`'s delegate) into a **single, strictly ordered, synchronous block on the dedicated `sessionQueue`**.
    * Ensured the `AVCaptureVideoDataOutput` delegate is nilled *after* the output has been removed from the session, all within the same synchronized `sessionQueue` block, to prevent messaging deallocated or invalid objects.
  * **Preview Fit Enhancement (`contain` mode):** Implemented top-alignment for the "contain" preview mode. When this mode is active, if the camera video's aspect ratio (when scaled to fill the view's width) results in a height shorter than the view, the preview will now fill the width and align to the top, rather than being vertically centered. This provides more control over the "letterboxed" space.
  * **Feature: WYSIWYG Photo Cropping for "cover" mode:**
    * When `cameraPreviewFit` is set to "cover", captured photos are now automatically cropped to precisely match the visible area of the `AVCaptureVideoPreviewLayer`. This ensures the final image is what the user saw in the preview.
    * Implemented image cropping logic using Core Graphics, calculating the crop rectangle based on normalized coordinates obtained via `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`.
    * The photo cropping process is performed asynchronously to maintain UI responsiveness after capture.
  * Improved internal logging for camera setup, deinitialization, and preview adjustment steps to aid in future debugging.