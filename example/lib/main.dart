import 'package:flutter/material.dart';
import 'package:native_camera_view/native_camera_view.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: MyHomePage());
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = true;
  bool _isPermissionGranted = false;
  CameraController? _cameraController;
  bool _isCameraPaused = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    // Logic xin quyền cho Android (iOS sẽ do native của plugin xử lý nếu bạn cấu hình vậy)
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (mounted) {
        setState(() {
          _isPermissionGranted = status.isGranted;
          _isLoading = false;
        });
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Quyền camera bị từ chối (Android). View có thể không hoạt động.')));
        }
      }
    } else if (Platform.isIOS) {
      // Plugin sẽ tự xử lý xin quyền ở native khi CameraPreviewWidget được build
      if (mounted) {
        setState(() {
          _isPermissionGranted = true; // Giả định để UI cố gắng build
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nền tảng không được hỗ trợ.')));
      }
    }
  }

  void _onCameraControllerCreated(CameraController controller) {
    if (mounted) {
      setState(() {
        // setState để các widget khác có thể dùng _cameraController nếu cần
        _cameraController = controller;
      });
      print("Example App: CameraController created!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plugin Camera Example'),
        actions: [
          if (_cameraController != null && _isPermissionGranted)
            IconButton(
              icon: Icon(_isCameraPaused ? Icons.play_arrow : Icons.pause),
              onPressed: () async {
                if (_isCameraPaused) {
                  await _cameraController?.resumeCamera();
                } else {
                  await _cameraController?.pauseCamera();
                }
                setState(() => _isCameraPaused = !_isCameraPaused);
              },
            ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? CircularProgressIndicator()
            : _isPermissionGranted
                ? CameraPreviewView(
                    setCameraController: (controller) {
                      _cameraController = controller;
                    },
                    cameraPreviewFit: CameraPreviewFit.contain,
                    isFrontCamera: false,
                  )
                : Text('Vui lòng cấp quyền camera trong cài đặt ứng dụng.'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _cameraController != null && _isPermissionGranted
            ? () async {
                final path = await _cameraController?.captureImage();
                if (path != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ảnh đã lưu tại: $path')));
                  // Ở đây bạn có thể điều hướng đến màn hình hiển thị ảnh
                }
              }
            : null,
        child: Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
