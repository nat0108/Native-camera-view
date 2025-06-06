# 📷 Native Camera View - Flutter Plugin

A Flutter plugin to display a native camera preview for Android and iOS, along with basic camera controls.
The plugin uses `AndroidView` (Android) and `UiKitView` (iOS) to embed the native camera view into the Flutter widget tree.

---

## ✨ Features

* **High-Performance Native Camera Preview**: Directly embeds the device's camera feed for a smooth, live preview experience.
* **Android & iOS Support**: Tailored implementations for both Android (using CameraX) and iOS (using AVFoundation) ensuring reliable operation.
* **Still Image Capture**: Saves the image to the app's temporary/cache folder and returns the path.
* **Advanced Pause/Resume Functionality**:
    * iOS: Pausing freezes the preview on its last visible frame. This exact frame can be captured even while the camera is "paused". The underlying camera session is suspended to optimize battery and resource usage.
    * Android: Pausing unbinds the PreviewUseCase to stop the live feed, while the ImageCaptureUseCase can remain active for photo taking.
* **Front/Back Camera Switching**: Easily toggle between front and back camera.
* **Flexible Preview Scaling & Fit Modes:**: `cover`, `contain`, `fitWidth`, `fitHeight`.
    * `cover`: The preview scales to completely fill the bounds of its view. If the video's aspect ratio differs from the view's, some parts of the video will be cropped to ensure full coverage.
        * ✨ **WYSIWYG "Cover" Mode Capture (iOS & Android)**: Captured photos taken when the preview is in "cover" mode are automatically cropped to precisely match what the user saw, ensuring a "What You See Is What You Get" experience.
    * `contain`: The preview scales to fit entirely within the view bounds while maintaining its original aspect ratio. This may result in "letterboxing" (empty bars) if aspect ratios differ.
        * **iOS Customization**: contain mode intelligently aligns the preview to the top of the view when the video (after being scaled to fill the view's width) is shorter than the view.
        * **Android Customization**: contain mode utilizes `PreviewView.ScaleType.FIT_START`, aligning the preview to the top/start of the view.
    * `fitWidth` / `fitHeight`: Additional scaling options to primarily fit by width or height (e.g., Android supports `FILL_START` / `FILL_END`; on iOS, current behavior for these modes is similar to cover).

* **Focus Management**: Tap to focus on a specific area.
    * Supports continuous auto-focus capabilities on both platforms.
    * **Android (beta)**: Includes tap-to-focus interaction, allowing users to specify focus points directly on the preview.
* **Clear Cached Images (Beta):**: Provides a utility to delete all photos previously captured and stored in the cache directory by this plugin.

<img alt="CleanShot 2025-06-06 at 11.41.15.png" src="CleanShot%202025-06-06%20at%2011.41.15.png" title="camera"/>

## 🚀 Installation Requirements

### iOS

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to preview and capture photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to the photo library to save your photos.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs permission to add photos to your library.</string>
```

### Android

* **Minimum API Level:** 21 (Android 5.0 - due to CameraX usage)

Add permissions to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```



## 🛠️ How to Use

### 1. Add Dependency

```yaml
dependencies:
  flutter:
    sdk: flutter
  native_camera_view: ^0.0.2 # Replace with the latest version
```

Run:

```bash
flutter pub get
```

### 2. Import Plugin

```dart
import 'package:native_camera_view/native_camera_view.dart';
```

### 3. Use `NativeCameraView`

Basic example with `StatefulWidget`:

```dart
CameraController? _cameraController;

void _onCameraControllerCreated(CameraController controller) {
    _cameraController = controller;
    print("CameraController created and received!");
}
```

### 4. UI Widget

```dart
NativeCameraView(
    onControllerCreated: _onCameraControllerCreated,
    cameraPreviewFit: CameraPreviewFit.cover,
    isFrontCamera: false,
)
```

---

## 📦 `CameraController` API

```dart
final path = await _cameraController?.captureImage(); // Capture photo
await _cameraController?.pauseCamera();               // Pause preview
await _cameraController?.resumeCamera();              // Resume preview
await _cameraController?.switchCamera(true);          // Switch to front camera
await _cameraController?.deleteAllCapturedPhotos();   // Delete cached images
```

---

## ⚙️ CameraPreviewView Parameters

| Parameter                   | Type                         | Description                          |
| --------------------------- | ---------------------------- | ------------------------------------ |
| `onCameraControllerCreated` | `Function(CameraController)` | **Required**                         |
| `currentFitMode`            | `CameraPreviewFit`           | Default: `cover`                     |
| `isFrontCameraSelected`     | `bool`                       | Use front camera: `true`             |
| `isCameraPausedParent`      | `bool?`                      | External pause state                 |

---

## 🐞 Bug Reports & Contributions

Please report issues or contribute at:

🔗 [https://github.com/nat0108/Native-camera-view](https://github.com/nat0108/Native-camera-view)

✉️ nat.anhthai@gmail.com
