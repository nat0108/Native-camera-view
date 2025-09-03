import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:native_camera_view/native_camera_view.dart';

import 'package:native_camera_view/native_camera_view.dart';

void main() {
  // Đảm bảo rằng các binding của Flutter đã được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // ✨ BẬT CHẾ ĐỘ EDGE-TO-EDGE ✨
  // Cho phép ứng dụng vẽ trên toàn bộ màn hình, bao gồm cả khu vực dưới các thanh hệ thống.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Làm cho các thanh hệ thống trong suốt để có thể nhìn thấy nội dung camera bên dưới.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  // ✨ KẾT THÚC THAY ĐỔI ✨

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Camera View Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal, // Sử dụng colorSchemeSeed cho Material 3
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(imagePath: path),
        ),
      );
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
    // Sử dụng Stack làm widget gốc để xếp lớp các widget lên nhau
    return Stack(
      children: [
        // LỚP 1: Camera View làm nền, lấp đầy toàn bộ màn hình
        // Positioned.fill đảm bảo widget này chiếm hết không gian của Stack
        Positioned.fill(
          child: NativeCameraView(
            onControllerCreated: _onCameraControllerCreated,
            cameraPreviewFit: _currentFit,
            isFrontCamera: _isFrontCameraSelected,
          ),
        ),

        // LỚP 2: Scaffold trong suốt nằm đè lên trên để chứa UI
        Scaffold(
          // Làm cho cả Scaffold và AppBar trong suốt để thấy camera bên dưới
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('Camera Plugin (${Platform.operatingSystem})'),
            elevation: 0, // Bỏ bóng mờ dưới AppBar
            actions: [
              if (_cameraController != null)
              // ✨ Lắng nghe isPaused notifier từ CameraController ✨
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
          // Body của Scaffold bây giờ chỉ chứa các nút điều khiển
          // Chúng ta vẫn dùng Stack bên trong để định vị các nút dễ dàng
          body: Stack(
            children: [
              // Nút chụp ảnh ở dưới cùng, chính giữa
              if (_cameraController != null)
                Positioned(
                  bottom: 30.0,
                  // Căn giữa theo chiều ngang
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

              // PopupMenuButton ở góc dưới bên trái để chọn chế độ fit
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

              // Nút xóa ảnh
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
                )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {

    return Stack(
      alignment: Alignment.center, // Căn chỉnh các item trong Stack
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 5.0), // Viền xanh dương, dày 5px
            ),
            child: NativeCameraView(
              onControllerCreated: _onCameraControllerCreated,
              cameraPreviewFit: _currentFit,
              isFrontCamera: _isFrontCameraSelected,
            ),
          ),
        ),

        // Lớp trên: Các nút điều khiển
        // Nút chụp ảnh ở dưới cùng, chính giữa
        if (_cameraController != null)
          Positioned(
            bottom: 30.0,
            child: FloatingActionButton(
              onPressed: _captureImage,
              tooltip: 'Chụp ảnh',
              backgroundColor: Colors.white.withOpacity(0.8),
              child: const Icon(Icons.camera_alt, color: Colors.black87, size: 30),
            ),
          ),

        // PopupMenuButton ở góc dưới bên trái để chọn chế độ fit
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

        // Nút xóa ảnh (có thể đặt ở vị trí khác nếu muốn)
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
                  textStyle: const TextStyle(fontSize: 12)
              ),
            ),
          )
      ],
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
    