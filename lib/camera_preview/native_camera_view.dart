import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera_controller.dart';
import 'native_camera_controller.dart';


/// Widget để hiển thị camera preview native.
  class NativeCameraView extends StatefulWidget {
  final CameraPreviewFit? cameraPreviewFit;
  final bool? isFrontCamera;
  final Function(CameraController controller) onControllerCreated;
  final bool? bypassPermissionCheck;


  const NativeCameraView({
    super.key,
    required this.onControllerCreated,
    this.cameraPreviewFit,
    this.isFrontCamera,
    this.bypassPermissionCheck,

  });

  @override
  State<NativeCameraView> createState() => _NativeCameraViewState();
}

class _NativeCameraViewState extends State<NativeCameraView> {
  late final NativeCameraController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NativeCameraController(
      onControllerCreated: widget.onControllerCreated,
    );
    // Lắng nghe notifier để hiển thị SnackBar
    _controller.snackbarMessage.addListener(_showSnackbar);
  }

  void _showSnackbar() {
    final message = _controller.snackbarMessage.value;
    if (message != null && message.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      // Xóa tin nhắn sau khi hiển thị để không hiện lại
      _controller.clearSnackbarMessage();
    }
  }

  @override
  void dispose() {
    _controller.snackbarMessage.removeListener(_showSnackbar);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sử dụng ValueListenableBuilder để rebuild UI khi state thay đổi
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _controller.isPermissionGranted,
          builder: (context, isGranted, _) {
            // Nếu đã có quyền, build camera view
            return _buildPlatformCameraView();
          },
        );
      },
    );
  }

  Widget _buildPlatformCameraView() {
    const String androidViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_android';
    const String iosViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_ios';

    // Lấy các tham số từ widget.props thay vì từ state của controller.
    final creationParams = <String, dynamic>{
      'cameraPreviewFit': widget.cameraPreviewFit?.name ?? 'cover',
      'isFrontCamera': widget.isFrontCamera ?? false,
      'bypassPermissionCheck': widget.bypassPermissionCheck ?? false,
    };

    // `key` rất quan trọng. Khi key thay đổi, Flutter sẽ tạo lại native view.
    final key = ValueKey(
        "native_camera_platform_view_${creationParams['cameraPreviewFit']}_${creationParams['isFrontCamera']}");
    if (Platform.isAndroid) {
      return AndroidView(
        key: key,
        viewType: androidViewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _controller.onPlatformViewCreated,
      );
    } else if (Platform.isIOS) {
      return UiKitView(
        key: key,
        viewType: iosViewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _controller.onPlatformViewCreated,
      );
    }

    return const Center(child: Text("Nền tảng không được hỗ trợ."));
  }
}