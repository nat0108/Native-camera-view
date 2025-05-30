import 'package:flutter/material.dart';
import 'package:native_camera_view/native_camera_view.dart'; // Import plugin của bạn
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Camera View Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
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
  bool _isLoading = true;
  bool _isPermissionGranted = false;
  CameraController? _cameraController;
  bool _isCameraPaused = false;

  // Các state này vẫn tồn tại, nhưng CameraPreviewView sẽ được gọi với giá trị cố định
  CameraPreviewFit _currentFit = CameraPreviewFit.cover;
  bool _isFrontCameraSelected = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.camera.request();
    } else if (Platform.isIOS) {
      status = await Permission.camera.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        // Giữ nguyên để UI hiển thị thông báo
      } else {
        status = PermissionStatus.granted;
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nền tảng không được hỗ trợ.')),
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
          SnackBar(content: Text('Quyền camera bị từ chối (${status.name}). View có thể không hoạt động.')),
        );
      }
    }
  }

  // Đổi tên hàm callback theo yêu cầu
  void _setCameraController(CameraController controller) {
    if (mounted) {
      _cameraController = controller;
      print("Example App: CameraController set!");
      if (_isCameraPaused) {
        _cameraController?.pauseCamera();
      }
    }
  }

  Future<void> _togglePauseResume() async {
    if (_cameraController == null) return;
    if (_isCameraPaused) {
      await _cameraController?.resumeCamera();
    } else {
      await _cameraController?.pauseCamera();
    }
    if (mounted) {
      setState(() => _isCameraPaused = !_isCameraPaused);
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || (_isCameraPaused && !Platform.isIOS )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isCameraPaused ? 'Camera đang tạm dừng.' : 'Controller chưa sẵn sàng.')),
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
    if (_cameraController == null || _isCameraPaused) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isCameraPaused ? 'Resume camera trước.' : 'Controller chưa sẵn sàng.')),
      );
      return;
    }
    // Mặc dù CameraPreviewView được gọi với isFrontCamera: false cố định,
    // chúng ta vẫn giữ logic này ở đây để có thể gọi xuống controller nếu cần.
    // Tuy nhiên, UI của CameraPreviewView sẽ không tự động thay đổi theo _isFrontCameraSelected nữa.
    final newIsFront = !_isFrontCameraSelected;
    await _cameraController?.switchCamera(newIsFront);
    if (mounted) {
      setState(() {
        _isFrontCameraSelected = newIsFront; // Cập nhật state cục bộ
      });
      print("Example App: Switched camera state to front: $newIsFront. Note: CameraPreviewView uses fixed params.");
    }
  }

  void _changeCameraFit(CameraPreviewFit? fit) {
    if (fit == null || _isCameraPaused) return;
    if (mounted) {
      setState(() {
        _currentFit = fit; // Cập nhật state cục bộ
      });
      print("Example App: Changed fit mode state to ${fit.name}. Note: CameraPreviewView uses fixed params.");
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
      appBar: AppBar(
        title: const Text('Plugin Camera Example'),
        actions: [
          if (_cameraController != null && _isPermissionGranted) ...[
            IconButton(
              icon: Icon(_isCameraPaused ? Icons.play_arrow : Icons.pause),
              tooltip: _isCameraPaused ? 'Resume' : 'Pause',
              onPressed: _togglePauseResume,
            ),
            IconButton(
              icon: const Icon(Icons.switch_camera),
              tooltip: 'Switch Camera',
              onPressed: _isCameraPaused ? null : _switchCamera,
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          if (_isPermissionGranted && (Platform.isAndroid || Platform.isIOS))
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  const Text("Current App Fit Mode:"), // Hiển thị state của app
                  DropdownButton<CameraPreviewFit>(
                    value: _currentFit, // Giá trị từ state của app
                    onChanged: _isCameraPaused ? null : _changeCameraFit,
                    items: CameraPreviewFit.values
                        .map((fit) => DropdownMenuItem(
                      value: fit,
                      child: Text(fit.name),
                    ))
                        .toList(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : _isPermissionGranted
                  ? CameraPreviewView(
                // Không còn key động dựa trên _currentFit và _isFrontCameraSelected nữa
                // vì các tham số này giờ được hardcode.
                // Nếu bạn muốn CameraPreviewView được tạo lại khi các giá trị hardcode này
                // thay đổi (ví dụ, bạn thay đổi chúng trong code và hot reload),
                // bạn có thể giữ lại một ValueKey tĩnh hoặc UniqueKey().
                key: const ValueKey("fixed_camera_preview"), // Hoặc UniqueKey()
                setCameraController: _setCameraController, // Sử dụng tên callback mới
                // Truyền các giá trị cố định theo yêu cầu
                cameraPreviewFit: CameraPreviewFit.contain,
                isFrontCamera: false,
              )
                  : _buildPermissionDeniedUI(),
            ),
          ),
          if (_cameraController != null && _isPermissionGranted)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text("Xóa tất cả ảnh đã chụp"),
                onPressed: _deleteAllPhotos,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400]),
              ),
            ),
        ],
      ),
      floatingActionButton: _isPermissionGranted && !_isCameraPaused
          ? FloatingActionButton(
        onPressed: _captureImage,
        tooltip: 'Chụp ảnh',
        child: const Icon(Icons.camera_alt),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildPermissionDeniedUI() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_outlined, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Quyền truy cập camera là bắt buộc để sử dụng tính năng này.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              await openAppSettings();
              _requestCameraPermission();
            },
            child: const Text('Mở Cài đặt ứng dụng'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _requestCameraPermission,
            child: const Text('Thử lại xin quyền'),
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
    