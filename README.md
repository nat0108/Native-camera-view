# 📷 Native Camera View - Flutter Plugin

A Flutter plugin to display a native camera preview for Android and iOS, along with basic camera controls.
The plugin uses `AndroidView` (Android) and `UiKitView` (iOS) to embed the native camera view into the Flutter widget tree.

---

## ✨ Features

* **Native Camera Preview**: View live camera feed directly from the device.
* **Android & iOS Support**: Works reliably across both platforms.
* **Capture Image**: Saves the image to the app's temporary/cache folder and returns the path.
* **Pause/Resume Camera**:

    * iOS: Stops preview at the last frame and suspends session to save battery.
    * Android: Unbinds the PreviewUseCase but still allows capturing.
* **Switch Camera**: Easily toggle between front and back camera.
* **Preview Fit Modes**: `cover`, `contain`, `fitWidth`, `fitHeight`.

    * Android: Supports `FIT_START` (align top/left).
    * iOS: `contain` by default centers the preview.
* **Tap-to-Focus** *(Android only)*: Tap to focus on a specific area.
* **Delete Captured Images**: Clear cached images saved by the plugin.

---

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

---

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
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
```

### 3. Request Camera Permission

```dart
Future<void> _requestCameraPermission() async {
  PermissionStatus status;
  if (Platform.isAndroid) {
    status = await Permission.camera.request();
  } else if (Platform.isIOS) {
    status = await Permission.camera.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      // Keep UI to show alert
    } else {
      status = PermissionStatus.granted;
    }
  } else {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsupported platform.')),
      );
    }
    return;
  }

  if (mounted) {
    setState(() {
      _isPermissionGranted = status.isGranted;
      _isLoading = false;
    });
    if (!status.isGranted && Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera permission denied (\${status.name}). View may not function properly.')),
      );
    }
  }
}
```

### 4. Use `CameraPreviewView`

Basic example with `StatefulWidget`:

```dart
CameraController? _cameraController;
bool _isPermissionGranted = false;
bool _isCameraPaused = false;
CameraPreviewFit _currentFit = CameraPreviewFit.cover;
bool _isFrontCameraSelected = false;

@override
void initState() {
  super.initState();
  _initializeCamera();
}

Future<void> _initializeCamera() async {
  bool granted = await requestCameraPermission(context);
  if (mounted) {
    setState(() {
      _isPermissionGranted = granted;
    });
  }
}

void _onCameraControllerCreated(CameraController controller) {
  _cameraController = controller;
  if (_isCameraPaused) {
    _cameraController?.pauseCamera();
  }
}
```

### 5. UI Widget

```dart
CameraPreviewView(
  key: ValueKey("camera_\${_currentFit.name}_\${_isFrontCameraSelected}"),
  onCameraControllerCreated: _onCameraControllerCreated,
  currentFitMode: _currentFit,
  isFrontCameraSelected: _isFrontCameraSelected,
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
| `key`                       | `Key?`                       | Use `ValueKey` to force view rebuild |
| `onCameraControllerCreated` | `Function(CameraController)` | **Required**                         |
| `currentFitMode`            | `CameraPreviewFit`           | Default: `cover`                     |
| `isFrontCameraSelected`     | `bool`                       | Use front camera: `true`             |
| `isCameraPausedParent`      | `bool?`                      | External pause state                 |

---

## 🐞 Bug Reports & Contributions

Please report issues or contribute at:
👉 [https://github.com/nat0108/Native-camera-view](https://github.com/nat0108/Native-camera-view)
