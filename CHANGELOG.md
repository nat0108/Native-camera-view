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
