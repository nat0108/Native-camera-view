// lib/camera/native_camera_view.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../camera_controller.dart';

class NativeCameraView extends StatefulWidget {
  final CameraPreviewFit? cameraPreviewFit;
  final bool? isFrontCamera;
  final Function(CameraController controller) onControllerCreated;
  final bool? bypassPermissionCheck;
  final Widget? loadingWidget;

  const NativeCameraView({
    super.key,
    required this.onControllerCreated,
    this.cameraPreviewFit,
    this.isFrontCamera,
    this.bypassPermissionCheck,
    this.loadingWidget,
  });

  @override
  State<NativeCameraView> createState() => _NativeCameraViewState();
}

class _NativeCameraViewState extends State<NativeCameraView> {
  CameraController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    const String baseChannelName = "com.plugin.camera_native.native_camera_view/camera_method_channel";
    final String channelName = Platform.isIOS ? '${baseChannelName}_ios_$id' : '${baseChannelName}_$id';
    final platformChannel = MethodChannel(channelName);

    // Dùng setState để gán controller và build lại widget
    setState(() {
      _controller = CameraController(channel: platformChannel);
    });

    widget.onControllerCreated(_controller!);
    _controller!.initialize();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ Thêm lại Stack và ValueListenableBuilder để quản lý UI loading ✨
    return Stack(
      alignment: Alignment.center,
      children: [
        // Lớp 1: Camera View luôn được build ở dưới cùng
        _buildPlatformCameraView(),

        // Lớp 2: Lớp loading nằm đè lên trên
        // Chỉ build lớp này khi controller đã được tạo
        if (_controller != null)
          ValueListenableBuilder<bool>(
            valueListenable: _controller!.isLoading,
            builder: (context, isLoading, _) {
              if (isLoading) {
                return Positioned.fill(
                  child: widget.loadingWidget ?? const Center(child: CircularProgressIndicator()),
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
      ],
    );
  }

  Widget _buildPlatformCameraView() {
    const String androidViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_android';
    const String iosViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_ios';

    final creationParams = <String, dynamic>{
      'cameraPreviewFit': widget.cameraPreviewFit?.name ?? 'cover',
      'isFrontCamera': widget.isFrontCamera ?? false,
      'bypassPermissionCheck': widget.bypassPermissionCheck ?? false,
    };

    final key = ValueKey(
        "native_camera_platform_view_${creationParams['isFrontCamera']}");

    if (Platform.isAndroid) {
      return AndroidView(
        key: key,
        viewType: androidViewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (Platform.isIOS) {
      return UiKitView(
        key: key,
        viewType: iosViewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }

    return const Center(child: Text("Nền tảng không được hỗ trợ."));
  }
}