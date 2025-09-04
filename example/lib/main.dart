import 'package:flutter/material.dart';
import 'dart:io';
import 'package:native_camera_view/native_camera_view.dart';

void main() {
  // Đảm bảo rằng các binding của Flutter đã được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Camera View Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var _cameraKey = UniqueKey();

  CameraController? _cameraController;
  CameraPreviewFit _currentFit = CameraPreviewFit.cover;
  final ValueNotifier<bool> isPaused = ValueNotifier(false);
  bool _isFrontCameraSelected = false;

  @override
  void initState() {
    super.initState();
  }

  void _onCameraControllerCreated(CameraController controller) {
    if (mounted) {
      setState(() {
        _cameraController = controller;
      });
      print("Example App: CameraController created and received!");
    }
  }

  Future<void> _togglePauseResume() async {
    if (_cameraController == null) return;
    if (isPaused.value) {
      await _cameraController?.resumeCamera();
      isPaused.value = false;
    } else {
      await _cameraController?.pauseCamera();
      isPaused.value = true;
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Controller chưa sẵn sàng.')),
      );
      return;
    }
    final path = await _cameraController?.captureImage();
    if (path != null && mounted) {
      print("Image captured at: $path");
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(imagePath: path),
        ),
      );

      setState(() {
        _cameraKey = UniqueKey();
      });

    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chụp ảnh thất bại.')),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null || isPaused.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isPaused.value ? 'Resume camera trước.' : 'Controller chưa sẵn sàng.')),
      );
      return;
    }
    final newIsFront = !_isFrontCameraSelected;
    await _cameraController?.switchCamera(newIsFront);
    if (mounted) {
      setState(() {
        _isFrontCameraSelected = newIsFront;
      });
    }
  }

  void _changeCameraFit(CameraPreviewFit? fit) {
    if (fit == null || (isPaused.value)) return;
    if (mounted) {
      setState(() {
        _currentFit = fit;
      });
    }
  }

  Future<void> _deleteAllPhotos() async {
    if (_cameraController == null) return;
    bool? success = await _cameraController?.deleteAllCapturedPhotos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success == true ? 'Đã xóa tất cả ảnh.' : 'Xóa ảnh thất bại hoặc không có ảnh.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        title: Text('Camera Plugin (${Platform.operatingSystem})'),
        actions: [
          if (_cameraController != null)
            ValueListenableBuilder<bool>(
              valueListenable: isPaused,
              builder: (context, isPaused, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                      tooltip: isPaused ? 'Resume' : 'Pause',
                      onPressed: _togglePauseResume,
                    ),
                    IconButton(
                      icon: const Icon(Icons.cameraswitch_outlined),
                      tooltip: 'Switch Camera',
                      onPressed: isPaused ? null : _switchCamera,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: NativeCameraView(
              key: _cameraKey,
              onControllerCreated: _onCameraControllerCreated,
              cameraPreviewFit: _currentFit,
              isFrontCamera: _isFrontCameraSelected,
            ),
          ),

          if (_cameraController != null)
            Positioned(
              top: 16,
              right: 16,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: const Text("Xóa ảnh"),
                onPressed: _deleteAllPhotos,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12)),
              ),
            ),

          if (_cameraController != null)
            Positioned(
              bottom: 30.0,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.center,
                child: FloatingActionButton(
                  onPressed: _captureImage,
                  tooltip: 'Chụp ảnh',
                  backgroundColor: Colors.white.withOpacity(0.8),
                  child: const Icon(Icons.camera_alt, color: Colors.black87, size: 30),
                ),
              ),
            ),

          if (_cameraController != null)
            Positioned(
              bottom: 30.0,
              left: 30.0,
              child: PopupMenuButton<CameraPreviewFit>(
                initialValue: _currentFit,
                onSelected: _changeCameraFit,
                itemBuilder: (BuildContext context) => CameraPreviewFit.values
                    .map((CameraPreviewFit fit) => PopupMenuItem<CameraPreviewFit>(
                  value: fit,
                  child: Text(fit.name),
                ))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.aspect_ratio, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  const DisplayPictureScreen({super.key, required this.imagePath});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh đã chụp')),
      body: Center(child: Image.file(File(imagePath))),
    );
  }
}

